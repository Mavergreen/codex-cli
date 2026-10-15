#!/bin/sh
# platform: host-agnostic -- plain sh; runs on ultimate-hat and modern macOS
set -eu
BUILD_DIR=${MAVERICKS_BUILD_DIR:?set MAVERICKS_BUILD_DIR before sourcing build/lib.sh}
MAVERICKS_ROOT=$(CDPATH= cd -- "$BUILD_DIR/.." && pwd)
export MAVERICKS_ROOT

. "$BUILD_DIR/msc.sh"
. "$SHIPYARD_SCRIPTS/lib.sh"

mavericks_build_root() {
  sh "$BUILD_DIR/resolve-build-root.sh"
}

mavericks_apply_patches() {
  source_dir=$1
  patch_dir=$2
  for patch in "$patch_dir"/*.patch; do
    [ -f "$patch" ] || continue
    git -C "$source_dir" apply --check "$patch"
  done
  for patch in "$patch_dir"/*.patch; do
    [ -f "$patch" ] || continue
    git -C "$source_dir" apply "$patch"
  done
}
