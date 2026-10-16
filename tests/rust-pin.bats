#!/usr/bin/env bats
# platform: host-agnostic -- fixtures and plain sh; runs on ultimate-hat and modern macOS

# Each test checks a scratch copy of build/ and components/, so it can write its own pin, against a
# source directory holding only codex-rs/rust-toolchain.toml.
setup() {
  export PRODUCT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export SHIPYARD_SCRIPTS="${SHIPYARD_SCRIPTS:-/home/schmonz/Documents/trees/mavergreen-shipyard/scripts}"
  product="$BATS_TEST_TMPDIR/product"
  source_dir="$BATS_TEST_TMPDIR/source"
  mkdir -p "$product" "$source_dir/codex-rs"
  cp -R "$PRODUCT_ROOT/build" "$PRODUCT_ROOT/components" "$product/"
  toolchain="$source_dir/codex-rs/rust-toolchain.toml"
}

# guard CHANNEL PIN: run the check with Codex's channel CHANNEL and components/rust/version PIN
guard() {
  printf '[toolchain]\nchannel = "%s"\ncomponents = ["clippy"]\n' "$1" > "$toolchain"
  printf '%s\n' "$2" > "$product/components/rust/version"
  sh "$product/build/check-rust-pin.sh" "$source_dir"
}

@test "a pin older than Codex's channel is refused, naming the toolchain file" {
  run guard 1.95.0 1.94.1-mavericks.3
  [ "$status" -eq 1 ]
  [ "$output" = "check-rust-pin: $toolchain wants Rust >= 1.95.0, components/rust/version is 1.94.1-mavericks.3" ]
}

@test "a pin at Codex's channel passes the guard" {
  run guard 1.95.0 1.95.0-mavericks.2
  [ "$status" -eq 0 ]
  [ "$output" = "check-rust-pin: Rust 1.95.0 (components/rust/version 1.95.0-mavericks.2) builds channel 1.95.0" ]
}

@test "a pin newer than Codex's channel passes the guard" {
  run guard 1.95.0 1.99.0-mavericks.2
  [ "$status" -eq 0 ]
  [ "$output" = "check-rust-pin: Rust 1.99.0 (components/rust/version 1.99.0-mavericks.2) builds channel 1.95.0" ]
}

@test "versions compare numerically, not as strings" {
  run guard 1.95.0 1.100.0-mavericks.1
  [ "$status" -eq 0 ]
  run guard 1.100.0 1.99.0-mavericks.2
  [ "$status" -eq 1 ]
}

@test "the pin's upstream version is the part before its first dash" {
  run guard 1.0 1.95.0-mavericks.99
  [ "$status" -eq 0 ]
  [ "$output" = "check-rust-pin: Rust 1.95.0 (components/rust/version 1.95.0-mavericks.99) builds channel 1.0" ]
  run guard 1.0 1.95.0-mavericks.2-rc.1
  [ "$status" -eq 0 ]
  [ "$output" = "check-rust-pin: Rust 1.95.0 (components/rust/version 1.95.0-mavericks.2-rc.1) builds channel 1.0" ]
  run guard 1.0 1.96.1
  [ "$status" -eq 0 ]
  [ "$output" = "check-rust-pin: Rust 1.96.1 (components/rust/version 1.96.1) builds channel 1.0" ]
}

@test "a channel that is not a dotted number is refused" {
  for channel in "" stable nightly-2026-01-01 1.95.0-beta .95 1.95. 1..95; do
    run guard "$channel" 1.99.0-mavericks.2
    [ "$status" -eq 1 ] || { echo "accepted channel '$channel'"; return 1; }
    [ "$output" = "check-rust-pin: the channel in $toolchain is '$channel', not a dotted version number" ]
  done
}

@test "a pin whose upstream part is not a dotted number is refused" {
  for pin in "" -mavericks.2 v1.99.0-mavericks.2 1.99.x-mavericks.2 1..99-mavericks.2 1.99.-mavericks.2; do
    run guard 1.95.0 "$pin"
    [ "$status" -eq 1 ] || { echo "accepted pin '$pin'"; return 1; }
    [ "$output" = "check-rust-pin: components/rust/version is '$pin', whose upstream part '${pin%%-*}' is not a dotted version number" ]
  done
}

@test "a source directory without rust-toolchain.toml is refused" {
  run sh "$product/build/check-rust-pin.sh" "$BATS_TEST_TMPDIR/missing"
  [ "$status" -eq 1 ]
  [ "$output" = "check-rust-pin: cannot read $BATS_TEST_TMPDIR/missing/codex-rs/rust-toolchain.toml" ]
  run sh "$product/build/check-rust-pin.sh"
  [ "$status" -eq 2 ]
}

# need_codex_checkout: the gitignored codex/ inspection checkout is the only local copy of the
# pinned revision's history, and a clean checkout (CI's actions/checkout, a git archive copy) lacks
# it. Skip unless it holds the pinned revision; build-codex.sh runs check-rust-pin on the real fetch.
need_codex_checkout() {
  revision=$(cat "$PRODUCT_ROOT/build/codex-revision")
  git -C "$PRODUCT_ROOT/codex" cat-file -e "$revision^{commit}" 2>/dev/null ||
    skip "codex/ is not a git checkout holding the pinned revision $revision"
}

@test "the committed pin builds the pinned Codex revision's channel" {
  need_codex_checkout
  git -C "$PRODUCT_ROOT/codex" show \
    "$(cat "$PRODUCT_ROOT/build/codex-revision"):codex-rs/rust-toolchain.toml" > "$toolchain"
  run sh "$PRODUCT_ROOT/build/check-rust-pin.sh" "$source_dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"(components/rust/version $(cat "$PRODUCT_ROOT/components/rust/version")) builds channel "* ]] || false
}
