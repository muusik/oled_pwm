#!/bin/sh
# DKMS PRE_BUILD: unpack i915 from Debian's linux-source into ./src and apply
# the i915 part of upstream's patch, then patches/*.patch. Run from the DKMS
# build directory with the kernel version.
set -eu

kver=$1
series=$(echo "$kver" | cut -d. -f1,2)
tarball=/usr/src/linux-source-$series.tar.xz
top=linux-source-$series

die() { echo "i915-legacy-oled: $*" >&2; exit 1; }

[ -f "$tarball" ] || die "$tarball missing: apt install linux-source-$series"

# i915 from another kernel version would build but not match the kernel's
# own code: build nothing then, and the stock i915 stays in use.
src_ver=$(dpkg-query -W -f='${Version}' "linux-source-$series" 2>/dev/null) ||
	die "linux-source-$series is not installed"
hdr_ver=$(dpkg-query -W -f='${Version}' "linux-headers-$kver" 2>/dev/null) ||
	die "linux-headers-$kver is not installed"
[ "$src_ver" = "$hdr_ver" ] ||
	die "linux-source-$series is $src_ver, the $kver kernel is $hdr_ver; install the matching linux-source-$series"

rm -rf src
mkdir -p src/include/trace
# intel_rps.c includes ../../../platform/x86/intel_ips.h, which the headers
# package does not have.
tar -xJf "$tarball" -C src --strip-components=1 \
	"$top/drivers/gpu/drm/i915" "$top/drivers/platform/x86/intel_ips.h"

# Upstream's patch also adds its object to the Xe driver's Makefile; only i915
# is rebuilt here, so only its files are patched.
up=upstream/linux-legacy-oled-brightness.patch
[ -f "$up" ] || die "$up missing"
awk '/^diff --git /{ keep = ($3 ~ /^a\/drivers\/gpu\/drm\/i915\//) } keep' "$up" \
	>src/upstream-i915.patch
[ -s src/upstream-i915.patch ] || die "$up has no i915 part"
echo "i915-legacy-oled: applying $up (i915 part)"
patch -d src -p1 -F0 --no-backup-if-mismatch -s < src/upstream-i915.patch ||
	die "$up does not apply to linux-source-$series $src_ver"

for p in patches/*.patch; do
	echo "i915-legacy-oled: applying $p"
	patch -d src -p1 -F0 --no-backup-if-mismatch -s < "$p" ||
		die "$p does not apply to linux-source-$series $src_ver"
done
