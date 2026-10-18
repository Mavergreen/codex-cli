#!/usr/bin/env bats
# platform: host-agnostic -- fixtures and plain sh; runs on ultimate-hat and modern macOS

# Each test checks a scratch copy of build/ and components/, so it can write its own pin.
setup() {
  export PRODUCT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  product="$BATS_TEST_TMPDIR/product"
  mkdir -p "$product"
  cp -R "$PRODUCT_ROOT/build" "$PRODUCT_ROOT/components" "$product/"
}

# gate PIN [ARG...]: run the check with components/aquatransport/min-version holding PIN
gate() {
  printf '%s\n' "$1" > "$product/components/aquatransport/min-version"
  shift
  sh "$product/build/check-aquatransport-pin.sh" "$@"
}

@test "a released-looking pin passes" {
  run gate 2026.10.20
  [ "$status" -eq 0 ]
  [ "$output" = "check-aquatransport-pin: the package needs AquaTransport 2026.10.20 or newer" ]
}

@test "unreleased is refused, saying why" {
  run gate unreleased
  [ "$status" -eq 1 ]
  [ "$output" = "check-aquatransport-pin: components/aquatransport/min-version is 'unreleased': no AquaTransport release has the fixes Codex needs yet, so this package cannot be released" ]
}

@test "unreleased passes when the caller is not releasing" {
  run gate unreleased --allow-unreleased
  [ "$status" -eq 0 ]
}

@test "malformed pins are refused, naming the value, even when unreleased is allowed" {
  for bad in 2026.9.21 20260921 2026-09-21 v2026.09.21 2026.09.21.1 abc ""; do
    run gate "$bad" --allow-unreleased
    [ "$status" -eq 1 ]
    [ "$output" = "check-aquatransport-pin: components/aquatransport/min-version is '$bad', not YYYY.MM.DD or unreleased" ]
  done
}

@test "a missing pin file is refused" {
  rm "$product/components/aquatransport/min-version"
  run sh "$product/build/check-aquatransport-pin.sh"
  [ "$status" -eq 1 ]
  [ "$output" = "check-aquatransport-pin: cannot read $product/components/aquatransport/min-version" ]
}

@test "the committed pin is shaped right" {
  run sh "$PRODUCT_ROOT/build/check-aquatransport-pin.sh" --allow-unreleased
  [ "$status" -eq 0 ]
}
