#!/bin/sh
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MAVERICKS_ROOT=$(CDPATH= cd -- "$HERE/.." && pwd)
ROOT=${MAVERICKS_BUILD_ROOT:-${TMPDIR:-/tmp}/mm-build}

case "$ROOT" in
  /*) ;;
  *) ROOT="$PWD/$ROOT" ;;
esac
mkdir -p "$ROOT"
ROOT=$(CDPATH= cd -- "$ROOT" && pwd)
case "$ROOT/" in
  "$MAVERICKS_ROOT/"*)
    echo "resolve-build-root: build root must be outside the product source tree: $ROOT" >&2
    exit 1
    ;;
esac
printf '%s\n' "$ROOT"
