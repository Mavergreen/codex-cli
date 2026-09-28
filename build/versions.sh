#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MAVERICKS_BUILD_DIR=$HERE
export MAVERICKS_BUILD_DIR
. "$HERE/lib.sh"
sh "$SHIPYARD_SCRIPTS/version.sh" "${1:-auto}" | sed -n 's/^FULL=//p'
