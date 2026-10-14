#!/usr/bin/env bats
# platform: macOS-only -- the fixture is built with pkgbuild and productbuild

setup() {
  export PRODUCT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export SHIPYARD_SCRIPTS="${SHIPYARD_SCRIPTS:-/home/schmonz/Documents/trees/mavergreen-shipyard/scripts}"
  export MAVERICKS_BUILD_ROOT="$BATS_TEST_TMPDIR/local-build"
  version=$(tr -d '[:space:]' < "$PRODUCT_ROOT/components/rust/version")
  short=$(sh "$PRODUCT_ROOT/build/rust-toolchain.sh" "$(sh "$SHIPYARD_SCRIPTS/mavericks_mode.sh")" "$(uname -m)")
  pkg="$short-$version.pkg"
  release="$BATS_TEST_TMPDIR/release/$version"
  mkdir -p "$release" "$BATS_TEST_TMPDIR/payload/usr/local/mavergreen/$short/bin"
  for tool in cargo rustc; do
    printf '#!/bin/sh\necho fake %s\n' "$tool" > "$BATS_TEST_TMPDIR/payload/usr/local/mavergreen/$short/bin/$tool"
    chmod +x "$BATS_TEST_TMPDIR/payload/usr/local/mavergreen/$short/bin/$tool"
  done
  pkgbuild --quiet --root "$BATS_TEST_TMPDIR/payload" --identifier test.fake-rust \
    --version 1 "$BATS_TEST_TMPDIR/$short-component.pkg"
  productbuild --quiet --package "$BATS_TEST_TMPDIR/$short-component.pkg" "$release/$pkg"
  write_sums
  export RUST_RELEASES_URL="file://$BATS_TEST_TMPDIR/release"
  dir="$(sh "$PRODUCT_ROOT/build/resolve-build-root.sh")/toolchain/$short-$version"
}

write_sums() {
  (cd "$release" && shasum -a 256 "$pkg" > SHA256SUMS)
}

@test "prints the extracted toolchain prefix" {
  out=$(sh "$PRODUCT_ROOT/build/fetch-rust.sh" 2>/dev/null)
  [ "$out" = "$dir/root/usr/local/mavergreen/$short" ]
  [ -x "$out/bin/cargo" ]
  [ -x "$out/bin/rustc" ]
}

@test "refuses a pkg that SHA256SUMS does not list" {
  (cd "$release" && printf '%s  other.pkg\n' "$(printf x | shasum -a 256 | cut -c1-64)" > SHA256SUMS)
  run sh "$PRODUCT_ROOT/build/fetch-rust.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"$pkg"* ]] || false
  [ ! -e "$dir/root" ]
}

@test "refuses a pkg whose bytes do not match" {
  printf 'tampered\n' >> "$release/$pkg"
  run sh "$PRODUCT_ROOT/build/fetch-rust.sh"
  [ "$status" -ne 0 ]
  [ ! -e "$dir/root" ]
  [ ! -e "$dir/$pkg" ]
}

@test "a second run with the toolchain extracted downloads nothing" {
  first=$(sh "$PRODUCT_ROOT/build/fetch-rust.sh" 2>/dev/null)
  rm -rf "$BATS_TEST_TMPDIR/release"
  again=$(sh "$PRODUCT_ROOT/build/fetch-rust.sh" 2>/dev/null)
  [ "$again" = "$first" ]
}
