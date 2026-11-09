#!/bin/sh
# Build the i915-legacy-oled-dkms .deb in a Debian 14 container (Podman).
# The package lands in dist/.
set -eu

repo=$(cd "$(dirname "$0")" && pwd)
image=localhost/oled_pwm-deb

# Upstream's patch and panel data generator come from the submodule upstream/.
[ -f "$repo/upstream/gen_panel_prop.py" ] || {
	echo "upstream/ is empty: git submodule update --init" >&2
	exit 1
}

# apt-cacher-ng for the image's packages; BL_APT_PROXY= (empty) goes direct.
BL_APT_PROXY=${BL_APT_PROXY-http://interval.jazz:3142}
export BL_APT_PROXY
podman build -q -t "$image" --secret id=apt_proxy,env=BL_APT_PROXY \
	"$repo/packaging" >/dev/null

mkdir -p "$repo/dist"
podman run --rm -v "$repo:/repo:ro" -v "$repo/dist:/dist" "$image" sh -euc '
	cp -r /repo /tmp/i915-legacy-oled
	cd /tmp/i915-legacy-oled
	rm -rf dist test/build.log .git upstream/.git
	dpkg-buildpackage -us -uc -b
	cp ../*.deb /dist/
'
ls -l "$repo"/dist/*.deb
