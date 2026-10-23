#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# The build system's host mkimage is built with TOOLS_LIBCRYPTO disabled,
# which cannot produce the signed TYFZA1 FIT. Build the upstream U-Boot host
# utilities with crypto enabled from the same pinned release the port
# validated (2026.07), without altering the tree's own mkimage.
set -eu
export LC_ALL=C
VERSION=2026.07
SHA256=78e8bfc382fe388f9b55aa1daf8c563522a037779b5d4c349d1415e381f1243e
URL=https://git.u-boot-project.org/u-boot/u-boot/-/releases/v$VERSION/downloads
OUT=${1:?Usage: build-fit-tools.sh new-output-dir [u-boot-archive]}
ARCHIVE=${2:-$(dirname "$OUT")/u-boot-$VERSION.tar.bz2}
[ ! -e "$OUT" ] || { echo "Output already exists: $OUT" >&2; exit 1; }
if [ ! -s "$ARCHIVE" ]; then
    mkdir -p "$(dirname "$ARCHIVE")"
    curl -fL --retry 3 -o "$ARCHIVE" "$URL/u-boot-$VERSION.tar.bz2"
fi
printf '%s  %s\n' "$SHA256" "$ARCHIVE" | sha256sum -c -
mkdir -p "$OUT/source" "$OUT/bin"
OUT=$(realpath "$OUT")
tar -xjf "$ARCHIVE" --strip-components=1 -C "$OUT/source"
make -C "$OUT/source" tools-only_defconfig
"$OUT/source/scripts/config" --file "$OUT/source/.config" \
    --enable TOOLS_LIBCRYPTO --disable TOOLS_MKEFICAPSULE --disable TOOLS_KWBIMAGE
make -C "$OUT/source" olddefconfig
grep -q '^CONFIG_TOOLS_LIBCRYPTO=y' "$OUT/source/.config"
make -C "$OUT/source" -j"$(nproc 2>/dev/null || echo 2)" tools-only
for tool in mkimage dumpimage fit_check_sign; do
    install -m 755 "$OUT/source/tools/$tool" "$OUT/bin/$tool"
done
cp "$OUT/source/.config" "$OUT/bin/uboot-tools.config"
"$OUT/bin/mkimage" -V
echo "Crypto-enabled host FIT tools: $OUT/bin"
echo "Use with: make TYFZA1_MKIMAGE=$OUT/bin/mkimage"
