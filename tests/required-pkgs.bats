#!/usr/bin/env bats
# platform: host-agnostic -- fixtures and a fake gh; runs on ultimate-hat and modern macOS

# The rg and ed25519 packages the 10.9 smokes install beside codex-cli's are the releases pinned in
# components/<name>/version, never whatever is newest. gh is a fake on PATH that serves FAKE_PKG and
# a SHA256SUMS naming it.
setup() {
  export PRODUCT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  product="$BATS_TEST_TMPDIR/product"
  mkdir -p "$product/build" "$product/components/rg" "$BATS_TEST_TMPDIR/bin"
  cp "$PRODUCT_ROOT/build/fetch-required-pkg.sh" "$product/build/"
  echo 15.2.0-mavericks.6 > "$product/components/rg/version"
  export FAKE_LOG="$BATS_TEST_TMPDIR/gh.log"
  export FAKE_PKG=rg-15.2.0-mavericks.6.pkg
  : > "$FAKE_LOG"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  cat > "$BATS_TEST_TMPDIR/bin/gh" <<'FAKE'
#!/bin/sh
echo "$*" >> "$FAKE_LOG"
while [ "$#" -gt 0 ]; do
  case "$1" in --dir) dir=$2; shift ;; esac
  shift
done
mkdir -p "$dir"
echo pkg-bytes > "$dir/$FAKE_PKG"
sum=$(shasum -a 256 "$dir/$FAKE_PKG" | awk '{print $1}')
[ -z "${FAKE_BAD_SUM:-}" ] || sum=0000000000000000000000000000000000000000000000000000000000000000
printf '%s  %s\n' "$sum" "${FAKE_LISTED:-$FAKE_PKG}" > "$dir/SHA256SUMS"
FAKE
  chmod +x "$BATS_TEST_TMPDIR/bin/gh"
}

@test "the pinned release is fetched by its tag, and the pkg's path printed" {
  run sh "$product/build/fetch-required-pkg.sh" rg "$BATS_TEST_TMPDIR/deps"
  [ "$status" -eq 0 ]
  [ "${lines[${#lines[@]}-1]}" = "$BATS_TEST_TMPDIR/deps/rg/$FAKE_PKG" ]
  [[ "$(cat "$FAKE_LOG")" == "release download 15.2.0-mavericks.6 -R Mavergreen/rg "* ]] || false
}

@test "the committed pins are Mavergreen release tags" {
  for p in rg ed25519; do
    grep -Eqx '[0-9][0-9.]*-mavericks\.[0-9]+' "$PRODUCT_ROOT/components/$p/version"
  done
}

@test "a missing or malformed pin is refused before any fetch" {
  run sh "$product/build/fetch-required-pkg.sh" ed25519 "$BATS_TEST_TMPDIR/deps"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no components/ed25519/version"* ]] || false
  echo latest > "$product/components/rg/version"
  run sh "$product/build/fetch-required-pkg.sh" rg "$BATS_TEST_TMPDIR/deps"
  [ "$status" -eq 1 ]
  [[ "$output" == *"'latest' is not a Mavergreen release tag"* ]] || false
  [ ! -s "$FAKE_LOG" ]
}

@test "a pkg whose checksum does not match its SHA256SUMS is refused" {
  FAKE_BAD_SUM=1 run sh "$product/build/fetch-required-pkg.sh" rg "$BATS_TEST_TMPDIR/deps"
  [ "$status" -eq 1 ]
  [[ "$output" == *"$FAKE_PKG does not match"* ]] || false
}

@test "a pkg its release's SHA256SUMS does not list is refused" {
  FAKE_LISTED=other.pkg run sh "$product/build/fetch-required-pkg.sh" rg "$BATS_TEST_TMPDIR/deps"
  [ "$status" -eq 1 ]
  [[ "$output" == *"$FAKE_PKG is not in"*"SHA256SUMS"* ]] || false
}

@test "a usage error for anything but NAME and DIR" {
  run sh "$PRODUCT_ROOT/build/fetch-required-pkg.sh" rg
  [ "$status" -eq 2 ]
}
