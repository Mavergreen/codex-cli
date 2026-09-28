#!/usr/bin/env bats

setup() {
  export PRODUCT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export SHIPYARD_SCRIPTS="${SHIPYARD_SCRIPTS:-/home/schmonz/Documents/trees/mavergreen-shipyard/scripts}"
  export MAVERICKS_BUILD_ROOT="$BATS_TEST_TMPDIR/local-build"
  mkdir -p "$MAVERICKS_BUILD_ROOT/codex-native" "$MAVERICKS_BUILD_ROOT/codex-cross"
  source_revision=$(cat "$PRODUCT_ROOT/build/codex-revision")
  rust_revision=$(cat "$PRODUCT_ROOT/mavericks-rust.pin")
  printf 'mode=native\ntarget=x86_64-apple-darwin\ndeployment_target=10.9\nsource_revision=%s\nrust_revision=%s\n' \
    "$source_revision" "$rust_revision" > "$MAVERICKS_BUILD_ROOT/codex-native/build-manifest"
  printf 'mode=cross\ntarget=x86_64-apple-darwin\ndeployment_target=10.9\nsource_revision=%s\nrust_revision=%s\n' \
    "$source_revision" "$rust_revision" > "$MAVERICKS_BUILD_ROOT/codex-cross/build-manifest"
}

@test "native and cross manifests agree on pinned source and toolchain" {
  run sh "$PRODUCT_ROOT/build/check-build-manifests.sh"
  [ "$status" -eq 0 ]
}

@test "cross manifest must match the committed Codex revision" {
  sed -i.bak 's/^source_revision=.*/source_revision=wrong/' \
    "$MAVERICKS_BUILD_ROOT/codex-cross/build-manifest"
  run sh "$PRODUCT_ROOT/build/check-build-manifests.sh"
  [ "$status" -ne 0 ]
}

@test "cross manifest must target x86_64 and macOS 10.9" {
  sed -i.bak 's/^target=.*/target=aarch64-apple-darwin/' \
    "$MAVERICKS_BUILD_ROOT/codex-cross/build-manifest"
  run sh "$PRODUCT_ROOT/build/check-build-manifests.sh"
  [ "$status" -ne 0 ]
}

@test "build manifests are rejected when the build root is in the product source" {
  export MAVERICKS_BUILD_ROOT="$PRODUCT_ROOT/build-output"
  run sh "$PRODUCT_ROOT/build/check-build-manifests.sh"
  [ "$status" -ne 0 ]
}
