#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Fill PKG_HASH for the tyfza1 firmware packages from locally built archives.
# Usage: firmware-hash.sh <archive> — prints the sha256 to paste into the
# package Makefile (or set it when building with a pre-seeded dl/ directory).
set -eu
for archive in "$@"; do
    sha256sum "$archive"
done
