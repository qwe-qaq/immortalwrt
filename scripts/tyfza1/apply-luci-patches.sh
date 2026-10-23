#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Apply the TYFZA1 LuCI feed patches after ./scripts/feeds update luci.
# Safe to re-run: already-applied patches are detected and skipped.
set -eu
SCRIPTS=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPTS/../.." && pwd)
LUCI=${1:-$ROOT/feeds/luci}
test -d "$LUCI/.git" || {
    echo "No git checkout at $LUCI; run ./scripts/feeds update luci first" >&2
    exit 1
}

for change in "$SCRIPTS"/luci-patches/*.patch; do
	if ! git -C "$LUCI" apply --reverse --check "$change" 2>/dev/null; then
		git -C "$LUCI" apply --check "$change"
		git -C "$LUCI" apply "$change"
	fi
done
echo "Applied TYFZA1 LuCI patches to $LUCI"
