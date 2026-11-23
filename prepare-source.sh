#!/bin/sh
# DKMS PRE_BUILD: unpack i915 from Debian's linux-source (or the copy kept of
# it, see below) into ./src and apply the i915 part of upstream's patch, then
# patches/*.patch. Run from the DKMS build directory with the kernel version.
set -eu

kver=$1
series=$(echo "$kver" | cut -d. -f1,2)
tarball=/usr/src/linux-source-$series.tar.xz
top=linux-source-$series

die() { echo "i915-legacy-oled: $*" >&2; exit 1; }

# i915 from another kernel version would build but not match the kernel's
# own code: build nothing then, and the stock i915 stays in use.
hdr_ver=$(dpkg-query -W -f='${Version}' "linux-headers-$kver" 2>/dev/null) ||
	die "linux-headers-$kver is not installed"
src_ver=$(dpkg-query -W -f='${Version}' "linux-source-$series" 2>/dev/null) || src_ver=

# The i915 sources of every kernel built for, kept after linux-source moves
# on to a newer version, so that the module can still be rebuilt for the
# older kernels (an upgrade of this package removes their modules first).
# Same name in dkms.conf.
cache=/var/cache/i915-legacy-oled/src
cached=$cache/linux-source-${series}_$hdr_ver.tar.xz

rm -rf src
mkdir -p src/include/trace
if [ -f "$tarball" ] && [ "$src_ver" = "$hdr_ver" ]; then
	# intel_rps.c includes ../../../platform/x86/intel_ips.h, which the
	# headers package does not have.
	tar -xJf "$tarball" -C src --strip-components=1 \
		"$top/drivers/gpu/drm/i915" "$top/drivers/platform/x86/intel_ips.h"
	if [ ! -f "$cached" ]; then
		mkdir -p "$cache"
		tar -cJf "$cached.part" -C src drivers
		mv "$cached.part" "$cached"
		echo "i915-legacy-oled: kept the i915 source of $hdr_ver in $cached"
	fi
	from="linux-source-$series $src_ver"
elif [ -f "$cached" ]; then
	tar -xJf "$cached" -C src
	from=$cached
else
	die "no i915 source of $hdr_ver for $kver: install linux-source-$series $hdr_ver"
fi

# Sources of kernels whose headers are gone are of no more use.
for f in "$cache"/linux-source-*.tar.xz; do
	[ -f "$f" ] || continue
	v=${f##*_}
	v=${v%.tar.xz}
	dpkg-query -W -f='${db:Status-Abbrev} ${Version}\n' 'linux-headers-*' 2>/dev/null |
		grep -qxF "ii  $v" || rm -f "$f"
done

# Upstream's patch also adds its object to the Xe driver's Makefile; only i915
# is rebuilt here, so only its files are patched. Its hunk for i915's Makefile
# is left out too: the object list around it changes between kernels (7.3
# added intel_dp_link_caps.o), so the object is added after
# intel_dp_aux_backlight.o below instead. Its hunks for
# intel_dp_aux_backlight.c are left out as well: 7.3.5 changed the code around
# them (the DPCD backlight quirk), and
# patches/0001-aux-backlight-legacy-interface.patch has them rebased.
up=upstream/linux-legacy-oled-brightness.patch
[ -f "$up" ] || die "$up missing"
awk '/^diff --git /{ keep = ($3 ~ /^a\/drivers\/gpu\/drm\/i915\//) &&
	$3 != "a/drivers/gpu/drm/i915/Makefile" &&
	$3 != "a/drivers/gpu/drm/i915/display/intel_dp_aux_backlight.c" } keep' "$up" \
	>src/upstream-i915.patch
[ -s src/upstream-i915.patch ] || die "$up has no i915 part"
echo "i915-legacy-oled: applying $up (i915 part)"
patch -d src -p1 -F0 --no-backup-if-mismatch -s < src/upstream-i915.patch ||
	die "$up does not apply to $from"

mk=src/drivers/gpu/drm/i915/Makefile
# shellcheck disable=SC1003  # the trailing backslash is the Makefile's
anchor='display/intel_dp_aux_backlight.o \'
# shellcheck disable=SC1003
obj='display/intel_dp_legacy_oled_brightness.o \'
[ "$(grep -cxF "	$anchor" "$mk")" = 1 ] ||
	die "$mk of $from has no single line $anchor"
A="	$anchor" O="	$obj" awk '{ print } $0 == ENVIRON["A"] { print ENVIRON["O"] }' \
	"$mk" >"$mk.new"
mv "$mk.new" "$mk"
[ "$(grep -cxF "	$obj" "$mk")" = 1 ] || die "could not add $obj to $mk"

for p in patches/*.patch; do
	echo "i915-legacy-oled: applying $p"
	patch -d src -p1 -F0 --no-backup-if-mismatch -s < "$p" ||
		die "$p does not apply to $from"
done
