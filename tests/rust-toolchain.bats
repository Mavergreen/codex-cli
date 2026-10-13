#!/usr/bin/env bats

setup() {
  export PRODUCT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
}

pick() { sh "$PRODUCT_ROOT/build/rust-toolchain.sh" "$1" "$2"; }

@test "native x86_64 builds with the native toolchain" {
  run pick native x86_64
  [ "$status" -eq 0 ]
  [ "$output" = rust ]
}

@test "a modern Intel Mac gets rust, since rust-cross is arm64-only" {
  run pick cross x86_64
  [ "$status" -eq 0 ]
  [ "$output" = rust ]
}

@test "Apple Silicon builds with rust-cross" {
  run pick cross arm64
  [ "$status" -eq 0 ]
  [ "$output" = rust-cross ]
}

@test "a native arm64 host does not exist" {
  run pick native arm64
  [ "$status" -eq 1 ]
}

@test "an unknown arch is refused" {
  run pick cross ppc
  [ "$status" -eq 1 ]
}
