#!/bin/sh
# Build the .deb (build-deb.sh) and install, exercise and remove it in a
# Debian 14 container with the laptop's kernel, as apt does there.
# Usage: test/build.sh [kernel version]  (output also in test/build.log)
set -eu
# shellcheck disable=SC3040  # dash has it (Debian 12 on)
set -o pipefail

here=$(cd "$(dirname "$0")" && pwd)
repo=$(dirname "$here")
kver=${1:-7.3.4+deb14-amd64}
series=$(echo "$kver" | cut -d. -f1,2)
image=localhost/oled_pwm-build

# An apt-cacher-ng for the image's packages when BL_APT_PROXY names one
# (http://host:3142); without it apt goes direct.
proxy_secret=
if [ -n "${BL_APT_PROXY:-}" ]; then
	export BL_APT_PROXY
	proxy_secret="--secret id=apt_proxy,env=BL_APT_PROXY"
fi

{
"$repo/build-deb.sh"
# shellcheck disable=SC2086  # proxy_secret is empty or two words
podman build -q -t "$image" --build-arg KVER="$kver" --build-arg SERIES="$series" \
	$proxy_secret "$here" >/dev/null

podman run --rm -v "$repo/dist:/dist:ro" -e KVER="$kver" -e SERIES="$series" -e P="${BL_APT_PROXY:-}" "$image" sh -euc '
	apt="apt-get -y -q ${P:+-o Acquire::http::Proxy=$P -o Acquire::https::Proxy=DIRECT}"
	initrd=/boot/initrd.img-$KVER
	mods() { modinfo -k "$KVER" -n i915 kvmgt; }
	in_initrd() { lsinitramfs "$initrd" | grep -E "/i915/i915\.ko|/i915\.ko|intel_legacy_panel_data|i915-legacy-oled" || echo "(none)"; }
	built() { dkms status -k "$KVER" | grep -q "i915-legacy-oled.*: installed"; }
	# The panel data generated at installation: what upstream'"'"'s
	# gen_panel_prop.py writes.
	fw=/usr/lib/firmware/intel_legacy_panel_data.bin
	fw_ok() { echo "c31bf01346f6271af7b26cf924431dde7afcc05ab639d8300d4372edc4d5d28d  $fw" | sha256sum -c -; }

	# i915 in the initramfs, as plymouth puts it there: its firmware and
	# options then have to be in it too.
	echo i915 >> /etc/initramfs-tools/modules

	echo "== 1. install the package"
	$apt install /dist/i915-legacy-oled-dkms_*_all.deb
	built
	mods
	modinfo -k "$KVER" -F vermagic i915
	modinfo -k "$KVER" -F signer i915
	xz -dc "$(modinfo -k "$KVER" -n i915)" | strings |
		grep -E "^(intel_dp_aux_legacy_[a-z_]+|firmware=intel_legacy_.*)$" | sort -u
	modprobe -c | grep "enable_dpcd_backlight"
	fw_ok
	echo "-- in the initramfs"
	in_initrd

	echo "== 2. a failed download: installed anyway, then a retry"
	rm "$fw"
	https_proxy=http://127.0.0.1:9 dpkg-reconfigure -f noninteractive i915-legacy-oled-dkms
	[ ! -e "$fw" ]
	! ls /usr/lib/firmware/intel_legacy_panel_data.bin.* 2>/dev/null || exit 1
	built
	i915-legacy-oled-fetch
	fw_ok
	in_initrd

	echo "== 3. a kernel that comes before its linux-source"
	dkms remove i915-legacy-oled/0.1 -k "$KVER"
	mv /usr/src/linux-source-$SERIES.tar.xz /root/
	rc=0; /etc/kernel/postinst.d/dkms "$KVER" || rc=$?
	echo "kernel hook exit status: $rc"
	[ "$rc" = 0 ]
	! built || exit 1
	echo "-- linux-source arrives: the trigger builds it"
	rm /root/linux-source-$SERIES.tar.xz
	$apt update -qq
	$apt install --reinstall linux-source-$SERIES
	built
	mods
	in_initrd

	echo "== 4. remove the package"
	$apt remove i915-legacy-oled-dkms
	! built || exit 1
	modinfo -k "$KVER" -n i915
	modprobe -c | grep "enable_dpcd_backlight" && exit 1
	[ ! -e "$fw" ]
	in_initrd
	echo "== all steps passed"
'
} 2>&1 | grep -vE "^debconf: |^(Get|Selecting|Preparing|Unpacking|Setting up|Processing)" | tee "$here/build.log"
