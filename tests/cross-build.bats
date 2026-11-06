#!/usr/bin/env bats
# platform: host-agnostic -- fixtures and plain sh; runs on ultimate-hat and modern macOS

setup() {
  export PRODUCT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export SHIPYARD_SCRIPTS="${SHIPYARD_SCRIPTS:-/home/schmonz/Documents/trees/mavergreen-shipyard/scripts}"
  export MAVERICKS_BUILD_ROOT="$BATS_TEST_TMPDIR/local-build"
  mkdir -p "$MAVERICKS_BUILD_ROOT/codex-native" "$MAVERICKS_BUILD_ROOT/codex-cross"
  source_revision=$(sh "$PRODUCT_ROOT/build/codex-pin.sh" revision)
  rust_version=$(cat "$PRODUCT_ROOT/components/rust/version")
  clang_version=$(cat "$PRODUCT_ROOT/components/clang-22/version")
  printf 'mode=native\ntarget=x86_64-apple-darwin\ndeployment_target=10.9\nsource_revision=%s\nrust_version=%s\nrusty_v8_version=150.4.0\nclang_version=%s\nprotoc_runtime=libcxx22-%s\nsdk=MacOSX10.9.sdk\n' \
    "$source_revision" "$rust_version" "$clang_version" "$clang_version" > "$MAVERICKS_BUILD_ROOT/codex-native/build-manifest"
  printf 'mode=cross\ntarget=x86_64-apple-darwin\ndeployment_target=10.9\nsource_revision=%s\nrust_version=%s\nrusty_v8_version=150.4.0\nclang_version=%s\nprotoc_runtime=host\nsdk=MacOSX10.9.sdk\n' \
    "$source_revision" "$rust_version" "$clang_version" > "$MAVERICKS_BUILD_ROOT/codex-cross/build-manifest"
  # spec: build/build-codex.sh -- both builds link the same released Recaulk provider
  for mode in native cross; do
    printf 'recaulk_origin=released\nrecaulk_version=20261201.1\nrecaulk_archive_sha256=%s\nrecaulk_declaration_sha256=%s\n' \
      "$(printf a%.0s $(seq 64))" "$(printf b%.0s $(seq 64))" >> "$MAVERICKS_BUILD_ROOT/codex-$mode/build-manifest"
  done
}

@test "native and cross manifests agree on pinned source and toolchain" {
  run sh "$PRODUCT_ROOT/build/check-build-manifests.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "check-build-manifests: native and cross inputs match" ]
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

@test "native and cross manifests must agree on the V8 version" {
  sed -i.bak 's/^rusty_v8_version=.*/rusty_v8_version=150.5.0/' \
    "$MAVERICKS_BUILD_ROOT/codex-cross/build-manifest"
  run sh "$PRODUCT_ROOT/build/check-build-manifests.sh"
  [ "$status" -ne 0 ]
}

@test "native and cross manifests must agree on the clang-22 version" {
  sed -i.bak 's/^clang_version=.*/clang_version=22.1.1-mavericks.1/' \
    "$MAVERICKS_BUILD_ROOT/codex-cross/build-manifest"
  run sh "$PRODUCT_ROOT/build/check-build-manifests.sh"
  [ "$status" -ne 0 ]
}

@test "the native protoc runtime must be the pinned libcxx22" {
  sed -i.bak 's/^protoc_runtime=.*/protoc_runtime=host/' \
    "$MAVERICKS_BUILD_ROOT/codex-native/build-manifest"
  run sh "$PRODUCT_ROOT/build/check-build-manifests.sh"
  [ "$status" -ne 0 ]
}

@test "the cross protoc runtime must be the host's own" {
  sed -i.bak "s/^protoc_runtime=.*/protoc_runtime=libcxx22-$clang_version/" \
    "$MAVERICKS_BUILD_ROOT/codex-cross/build-manifest"
  run sh "$PRODUCT_ROOT/build/check-build-manifests.sh"
  [ "$status" -ne 0 ]
}

@test "native and cross manifests must both name the same SDK" {
  sed -i.bak 's/^sdk=.*/sdk=MacOSX11.3.sdk/' "$MAVERICKS_BUILD_ROOT/codex-cross/build-manifest"
  run sh "$PRODUCT_ROOT/build/check-build-manifests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"SDK differs"* ]] || false

  sed -i.bak '/^sdk=/d' "$MAVERICKS_BUILD_ROOT/codex-cross/build-manifest"
  run sh "$PRODUCT_ROOT/build/check-build-manifests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing or malformed sdk"* ]] || false
}

@test "every build script with a shebang has it on line 1" {
  for script in "$PRODUCT_ROOT"/build/*.sh; do
    grep -q '^#!/bin/sh$' "$script" || continue
    [ "$(head -n 1 "$script")" = '#!/bin/sh' ] || { echo "no shebang on line 1: $script"; return 1; }
  done
}

@test "--cross-only checks the cross manifest alone, as CI must with no native build" {
  rm "$MAVERICKS_BUILD_ROOT/codex-native/build-manifest"
  run sh "$PRODUCT_ROOT/build/check-build-manifests.sh"
  [ "$status" -ne 0 ]
  run sh "$PRODUCT_ROOT/build/check-build-manifests.sh" --cross-only
  [ "$status" -eq 0 ]
  [ "$output" = "check-build-manifests: cross inputs match the committed pins (no native manifest compared)" ]
}

@test "--cross-only still refuses a cross manifest that is not the committed pins" {
  rm "$MAVERICKS_BUILD_ROOT/codex-native/build-manifest"
  sed -i.bak 's/^source_revision=.*/source_revision=wrong/' \
    "$MAVERICKS_BUILD_ROOT/codex-cross/build-manifest"
  run sh "$PRODUCT_ROOT/build/check-build-manifests.sh" --cross-only
  [ "$status" -ne 0 ]
  [[ "$output" == *"Codex source revision mismatch"* ]] || false
}

@test "--cross-only still requires the cross manifest to use the host's protoc" {
  rm "$MAVERICKS_BUILD_ROOT/codex-native/build-manifest"
  sed -i.bak 's/^protoc_runtime=.*/protoc_runtime=libcxx22-22.1.1-mavericks.8/' \
    "$MAVERICKS_BUILD_ROOT/codex-cross/build-manifest"
  run sh "$PRODUCT_ROOT/build/check-build-manifests.sh" --cross-only
  [ "$status" -ne 0 ]
}

@test "an unknown check-build-manifests option is a usage error" {
  run sh "$PRODUCT_ROOT/build/check-build-manifests.sh" --bogus
  [ "$status" -eq 2 ]
}

@test "a development provider in either manifest cannot claim release equivalence" {
  for mode in native cross; do
    cp "$MAVERICKS_BUILD_ROOT/codex-$mode/build-manifest" "$BATS_TEST_TMPDIR/keep"
    sed -i.bak 's/^recaulk_origin=.*/recaulk_origin=development/; s/^recaulk_version=.*/recaulk_version=development/' \
      "$MAVERICKS_BUILD_ROOT/codex-$mode/build-manifest"
    run sh "$PRODUCT_ROOT/build/check-build-manifests.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"development Recaulk provider"* ]] || false
    cp "$BATS_TEST_TMPDIR/keep" "$MAVERICKS_BUILD_ROOT/codex-$mode/build-manifest"
  done
  sed -i.bak 's/^recaulk_origin=.*/recaulk_origin=development/' "$MAVERICKS_BUILD_ROOT/codex-cross/build-manifest"
  run sh "$PRODUCT_ROOT/build/check-build-manifests.sh" --cross-only
  [ "$status" -ne 0 ]
}

@test "native and cross manifests must link the same provider bytes" {
  for field in recaulk_version recaulk_archive_sha256 recaulk_declaration_sha256; do
    cp "$MAVERICKS_BUILD_ROOT/codex-cross/build-manifest" "$BATS_TEST_TMPDIR/keep"
    sed -i.bak "s/^$field=.*/$field=20261202.1/" "$MAVERICKS_BUILD_ROOT/codex-cross/build-manifest"
    run sh "$PRODUCT_ROOT/build/check-build-manifests.sh"
    [ "$status" -ne 0 ] || { echo "accepted a different $field"; false; }
    cp "$BATS_TEST_TMPDIR/keep" "$MAVERICKS_BUILD_ROOT/codex-cross/build-manifest"
  done
}

@test "a manifest that does not say which provider it linked is refused" {
  sed -i.bak '/^recaulk_/d' "$MAVERICKS_BUILD_ROOT/codex-cross/build-manifest"
  run sh "$PRODUCT_ROOT/build/check-build-manifests.sh" --cross-only
  [ "$status" -ne 0 ]
}
