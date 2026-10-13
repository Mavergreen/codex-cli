#!/usr/bin/env bats
# platform: macOS-only -- the fixture is built with pkgbuild and productbuild

setup() {
  export PRODUCT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export SHIPYARD_SCRIPTS="${SHIPYARD_SCRIPTS:-/home/schmonz/Documents/trees/mavergreen-shipyard/scripts}"
  export MAVERICKS_BUILD_ROOT="$BATS_TEST_TMPDIR/local-build"
  version=$(tr -d '[:space:]' < "$PRODUCT_ROOT/components/clang-22/version")
  release="$BATS_TEST_TMPDIR/release/$version"
  mkdir -p "$release"
  : > "$release/SHA256SUMS"
  export CLANG22_RELEASES_URL="file://$BATS_TEST_TMPDIR/release"
  build_root=$(sh "$PRODUCT_ROOT/build/resolve-build-root.sh")
}

# fake_release SHORT STEM FILE...: a release pkg for SHORT whose component is STEM-component.pkg
fake_release() {
  short=$1 stem=$2
  shift 2
  payload="$BATS_TEST_TMPDIR/payload-$short"
  for file in "$@"; do
    mkdir -p "$(dirname "$payload/usr/local/mavergreen/$short/$file")"
    printf '#!/bin/sh\necho fake %s\n' "$file" > "$payload/usr/local/mavergreen/$short/$file"
    chmod +x "$payload/usr/local/mavergreen/$short/$file"
  done
  pkgbuild --quiet --root "$payload" --identifier "test.fake-$short" \
    --version 1 "$BATS_TEST_TMPDIR/$stem-component.pkg"
  productbuild --quiet --package "$BATS_TEST_TMPDIR/$stem-component.pkg" "$release/$stem-$version.pkg"
  (cd "$release" && shasum -a 256 "$stem-$version.pkg" >> SHA256SUMS)
}

@test "prints the extracted clang22 prefix" {
  fake_release clang22 mavericks-clang-22-native bin/clang bin/clang++
  out=$(sh "$PRODUCT_ROOT/build/fetch-clang-22.sh" clang22 2>/dev/null)
  [ "$out" = "$build_root/toolchain/clang22-$version/root/usr/local/mavergreen/clang22" ]
  [ -x "$out/bin/clang++" ]
}

@test "prints the extracted clang22-cross prefix" {
  fake_release clang22-cross mavericks-clang-22-cross bin/clang bin/clang++
  out=$(sh "$PRODUCT_ROOT/build/fetch-clang-22.sh" clang22-cross 2>/dev/null)
  [ "$out" = "$build_root/toolchain/clang22-cross-$version/root/usr/local/mavergreen/clang22-cross" ]
  [ -x "$out/bin/clang++" ]
}

@test "prints the extracted libcxx22 prefix" {
  fake_release libcxx22 libcxx22 lib/libc++.1.dylib lib/libc++abi.1.dylib
  out=$(sh "$PRODUCT_ROOT/build/fetch-clang-22.sh" libcxx22 2>/dev/null)
  [ "$out" = "$build_root/toolchain/libcxx22-$version/root/usr/local/mavergreen/libcxx22" ]
  [ -f "$out/lib/libc++abi.1.dylib" ]
}

@test "refuses a product the release does not make" {
  run sh "$PRODUCT_ROOT/build/fetch-clang-22.sh" clang21
  [ "$status" -eq 2 ]
}

@test "refuses a pkg that SHA256SUMS does not list" {
  fake_release libcxx22 libcxx22 lib/libc++.1.dylib
  (cd "$release" && printf '%s  other.pkg\n' "$(printf x | shasum -a 256 | cut -c1-64)" > SHA256SUMS)
  run sh "$PRODUCT_ROOT/build/fetch-clang-22.sh" libcxx22
  [ "$status" -ne 0 ]
  [[ "$output" == *"libcxx22-$version.pkg"* ]]
  [ ! -e "$build_root/toolchain/libcxx22-$version/root" ]
}

@test "refuses a pkg whose bytes do not match" {
  fake_release libcxx22 libcxx22 lib/libc++.1.dylib
  printf 'tampered\n' >> "$release/libcxx22-$version.pkg"
  run sh "$PRODUCT_ROOT/build/fetch-clang-22.sh" libcxx22
  [ "$status" -ne 0 ]
  [ ! -e "$build_root/toolchain/libcxx22-$version/root" ]
  [ ! -e "$build_root/toolchain/libcxx22-$version/libcxx22-$version.pkg" ]
}

@test "a second run with the product extracted downloads nothing" {
  fake_release libcxx22 libcxx22 lib/libc++.1.dylib
  first=$(sh "$PRODUCT_ROOT/build/fetch-clang-22.sh" libcxx22 2>/dev/null)
  rm -rf "$BATS_TEST_TMPDIR/release"
  again=$(sh "$PRODUCT_ROOT/build/fetch-clang-22.sh" libcxx22 2>/dev/null)
  [ "$again" = "$first" ]
}
