#!/bin/sh
# platform: modern macOS -- require matching native and cross build inputs before packaging.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PRODUCT_ROOT=$(CDPATH= cd -- "$HERE/.." && pwd)
BUILD_ROOT=$(sh "$HERE/resolve-build-root.sh")
NATIVE="$BUILD_ROOT/codex-native/build-manifest"
CROSS="$BUILD_ROOT/codex-cross/build-manifest"

for manifest in "$NATIVE" "$CROSS"; do
  [ -f "$manifest" ] || { echo "check-build-manifests: missing $manifest" >&2; exit 1; }
done

field() { sed -n "s/^$1=//p" "$2"; }
EXPECTED_SOURCE=$(tr -d '[:space:]' < "$HERE/codex-revision")
EXPECTED_RUST=$(tr -d '[:space:]' < "$PRODUCT_ROOT/mavericks-rust.pin")

check_manifest() {
  manifest=$1
  wanted_mode=$2
  [ "$(field mode "$manifest")" = "$wanted_mode" ] || {
    echo "check-build-manifests: wrong mode in $manifest" >&2; exit 1;
  }
  [ "$(field target "$manifest")" = x86_64-apple-darwin ] || {
    echo "check-build-manifests: wrong target in $manifest" >&2; exit 1;
  }
  [ "$(field deployment_target "$manifest")" = 10.9 ] || {
    echo "check-build-manifests: wrong deployment target in $manifest" >&2; exit 1;
  }
  [ "$(field source_revision "$manifest")" = "$EXPECTED_SOURCE" ] || {
    echo "check-build-manifests: Codex source revision mismatch in $manifest" >&2; exit 1;
  }
  [ "$(field rust_revision "$manifest")" = "$EXPECTED_RUST" ] || {
    echo "check-build-manifests: Rust toolchain revision mismatch in $manifest" >&2; exit 1;
  }
}

check_manifest "$NATIVE" native
check_manifest "$CROSS" cross
echo "check-build-manifests: native and cross inputs match"
