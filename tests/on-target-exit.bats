#!/usr/bin/env bats
# platform: host-agnostic -- plain sh against a given version; fetches nothing; runs on ultimate-hat and modern macOS

setup() {
  export PRODUCT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  check="$PRODUCT_ROOT/build/check-on-target-exit.sh"
}

@test "an older plugin in mavericks-vm@v1 keeps the deviation" {
  run sh "$check" --version v0.20261005.8
  [ "$status" -eq 0 ]
  [ "$output" = "check-on-target-exit: mavericks-vm@v1 has packer-plugin-macosx v0.20261005.8, older than v0.20261005.9; publish still does not need on-mavericks" ]
}

@test "an older date with a larger count is still older" {
  run sh "$check" --version v0.20260930.12
  [ "$status" -eq 0 ]
}

@test "the plugin with Aqua Transport 2026.10.25 fails, naming the exit" {
  run sh "$check" --version v0.20261005.9
  [ "$status" -eq 1 ]
  [ "$output" = "check-on-target-exit: mavericks-vm@v1 has packer-plugin-macosx v0.20261005.9, which carries Aqua Transport 2026.10.25: make publish need on-mavericks and builds-on-mavericks again, require them on main, and remove this check and INGREDIENTS.md's on-target deviation" ]
}

@test "a later plugin fails too" {
  run sh "$check" --version v0.20261005.10
  [ "$status" -eq 1 ]
  run sh "$check" --version v0.20261101.1
  [ "$status" -eq 1 ]
}

@test "a malformed version is refused, naming it" {
  for bad in 0.20261005.9 v0.2026105.9 v1.20261005.9 v0.20261005 garbage ""; do
    run sh "$check" --version "$bad"
    [ "$status" -eq 2 ]
    [ "$output" = "check-on-target-exit: '$bad' is not v0.YYYYMMDD.N" ]
  done
}

@test "the deviation it guards is declared" {
  grep -q '^- on-target: ' "$PRODUCT_ROOT/INGREDIENTS.md"
}

@test "both workflows run it, and neither publish needs its 10.9 job" {
  for w in builds release; do
    grep -q 'sh build/check-on-target-exit.sh$' "$PRODUCT_ROOT/.github/workflows/$w.yml"
    sed -n '/^  publish:/,/^    if:/p' "$PRODUCT_ROOT/.github/workflows/$w.yml" | grep -q '^    needs: \[[a-z-]*, scan\]$'
  done
}
