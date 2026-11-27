#!/usr/bin/env bats
# platform: host-agnostic -- fixtures and plain sh; runs on ultimate-hat and modern macOS

setup() {
  export PRODUCT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
}

pick() { sh "$PRODUCT_ROOT/build/rust-toolchain.sh" "$1" "$2"; }

@test "10.9 builds with the native toolchain" {
  run pick mavericks x86_64
  [ "$status" -eq 0 ]
  [ "$output" = rust ]
}

@test "a modern Intel Mac gets rust, since rust-cross is arm64-only" {
  run pick modern x86_64
  [ "$status" -eq 0 ]
  [ "$output" = rust ]
}

@test "Apple Silicon builds with rust-cross" {
  run pick modern arm64
  [ "$status" -eq 0 ]
  [ "$output" = rust-cross ]
}

@test "a 10.9 arm64 host does not exist" {
  run pick mavericks arm64
  [ "$status" -eq 1 ]
}

@test "an unknown arch is refused" {
  run pick modern ppc
  [ "$status" -eq 1 ]
}

@test "shipyard's retired mode names are refused" {
  run pick native x86_64
  [ "$status" -eq 1 ]
  run pick cross arm64
  [ "$status" -eq 1 ]
}
