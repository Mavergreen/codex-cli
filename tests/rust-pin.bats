#!/usr/bin/env bats

setup() {
  export PRODUCT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export SHIPYARD_SCRIPTS="${SHIPYARD_SCRIPTS:-/home/schmonz/Documents/trees/mavergreen-shipyard/scripts}"
}

guard() { sh "$PRODUCT_ROOT/build/check-rust-pin.sh" "$1" "$2"; }

@test "a pin older than Codex's channel is refused" {
  run guard 1.95.0 1.94.1-mavericks.3
  [ "$status" -eq 1 ]
  [ "$output" = "build-codex: Codex wants Rust >= 1.95.0, components/rust/version is 1.94.1-mavericks.3" ]
}

@test "a pin at Codex's channel passes the guard" {
  run guard 1.95.0 1.95.0-mavericks.2
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a pin newer than Codex's channel passes the guard" {
  run guard 1.95.0 1.99.0-mavericks.2
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "versions compare numerically, not as strings" {
  run guard 1.95.0 1.100.0-mavericks.1
  [ "$status" -eq 0 ]
  run guard 1.100.0 1.99.0-mavericks.2
  [ "$status" -eq 1 ]
}

@test "the pin's upstream version is the part before its first dash" {
  run guard 1.99.0 1.95.0-mavericks.99
  [ "$status" -eq 1 ]
  [[ "$output" == *"is 1.95.0-mavericks.99" ]]
}

@test "an empty channel or pin is refused" {
  run guard "" 1.99.0-mavericks.2
  [ "$status" -eq 1 ]
  [[ "$output" == *"no Rust channel"* ]]
  run guard 1.95.0 ""
  [ "$status" -eq 1 ]
  [[ "$output" == *"no Rust version"* ]]
}

@test "the committed pin builds the pinned Codex revision's channel" {
  channel=$(git -C "$PRODUCT_ROOT/codex" show \
    "$(cat "$PRODUCT_ROOT/build/codex-revision"):codex-rs/rust-toolchain.toml" |
    sed -n 's/^channel = "\(.*\)"$/\1/p')
  [ -n "$channel" ]
  run guard "$channel" "$(cat "$PRODUCT_ROOT/components/rust/version")"
  [ "$status" -eq 0 ]
}
