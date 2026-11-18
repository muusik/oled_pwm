#!/bin/sh
# Build the i915-legacy-oled-dkms .deb with this machine's Debian tools
# (debian/control Build-Depends, on Debian 14). The package lands in dist/.
set -eu

repo=$(cd "$(dirname "$0")" && pwd)

# Upstream's patch and panel data generator come from the submodule upstream/.
[ -f "$repo/upstream/gen_panel_prop.py" ] || {
	echo "upstream/ is empty: git submodule update --init" >&2
	exit 1
}

# Build in a copy: dpkg-buildpackage writes the .deb next to the source tree
# and leaves build files in it.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/i915-legacy-oled"
tar -C "$repo" --exclude=./.git --exclude=./upstream/.git --exclude=./dist \
	--exclude=./test/build.log -cf - . | tar -C "$tmp/i915-legacy-oled" -xf -

(cd "$tmp/i915-legacy-oled" && dpkg-buildpackage -us -uc -b)

mkdir -p "$repo/dist"
cp "$tmp"/*.deb "$repo/dist/"
ls -l "$repo"/dist/*.deb
