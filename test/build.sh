#!/bin/sh
# Build and install the DKMS module in a Debian 14 container, as on the laptop.
# Usage: test/build.sh [kernel version]  (output also in test/build.log)
set -eu
# shellcheck disable=SC3040  # dash has it (Debian 12 on)
set -o pipefail

here=$(cd "$(dirname "$0")" && pwd)
repo=$(dirname "$here")
kver=${1:-7.2.15+deb14-amd64}
image=localhost/oled_pwm-build

# apt-cacher-ng for the image's packages; BL_APT_PROXY= (empty) goes direct.
BL_APT_PROXY=${BL_APT_PROXY-http://interval.jazz:3142}
export BL_APT_PROXY
podman build -q -t "$image" --build-arg KVER="$kver" \
	--secret id=apt_proxy,env=BL_APT_PROXY "$here" >/dev/null

podman run --rm -v "$repo:/repo:ro" -e KVER="$kver" "$image" sh -euc '
	ver=$(sed -n "s/^PACKAGE_VERSION=\"\(.*\)\"/\1/p" /repo/dkms.conf)
	dst=/usr/src/i915-legacy-oled-$ver
	mkdir -p "$dst"
	cp -r /repo/dkms.conf /repo/prepare-source.sh /repo/patches "$dst"
	mkdir "$dst/upstream"
	cp /repo/upstream/linux-legacy-oled-brightness.patch "$dst/upstream/"
	dkms add "i915-legacy-oled/$ver"
	dkms install "i915-legacy-oled/$ver" -k "$KVER" ||
		{ cat /var/lib/dkms/i915-legacy-oled/"$ver"/build/make.log; exit 1; }
	dkms status
	echo "== modules modprobe would load for $KVER"
	modinfo -k "$KVER" -n i915 kvmgt
	modinfo -k "$KVER" -F firmware i915 | grep legacy
	modinfo -k "$KVER" -F vermagic i915
	modinfo -k "$KVER" -F signer i915
	modinfo -k "$KVER" i915 | grep "^parm: *enable_dpcd_backlight"
	echo "== new code in the module"
	xz -dc "$(modinfo -k "$KVER" -n i915)" | strings | grep -E "^(intel_dp_aux_legacy_[a-z_]+|firmware=intel_legacy_.*)$" | sort -u
	echo "== firmware"
	cd /tmp && python3 -I /repo/upstream/gen_panel_prop.py && ls -l intel_legacy_panel_data.bin
' 2>&1 | tee "$here/build.log"
