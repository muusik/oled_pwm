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

# An apt-cacher-ng for the image's packages when BL_APT_PROXY names one
# (http://host:3142); without it apt goes direct.
proxy_secret=
if [ -n "${BL_APT_PROXY:-}" ]; then
	export BL_APT_PROXY
	proxy_secret="--secret id=apt_proxy,env=BL_APT_PROXY"
fi
# shellcheck disable=SC2086  # proxy_secret is empty or two words
podman build -q -t "$image" $proxy_secret \
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
