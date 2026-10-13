#!/usr/bin/env bats

setup() {
  export MAVERGREEN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export MAVERICKS_ROOT="$MAVERGREEN_ROOT"
  export SHIPYARD_SCRIPTS="${SHIPYARD_SCRIPTS:-/home/schmonz/Documents/trees/mavergreen-shipyard/scripts}"
  export MAVERICKS_BUILD_ROOT="$BATS_TEST_TMPDIR/local-build"
  profile=ptrcomp_sandbox_release
  target=x86_64-apple-darwin
  archive="librusty_v8_${profile}_${target}.a.gz"
  binding="src_binding_${profile}_${target}.rs"
  sums="rusty_v8_${profile}_${target}.sha256"
  release="$BATS_TEST_TMPDIR/release/rusty-v8-v150.4.0"
  source_dir="$BATS_TEST_TMPDIR/SOURCE"
  mkdir -p "$release" "$source_dir/codex-rs"
  printf 'fake archive bytes\n' > "$release/$archive"
  printf '// fake binding\n' > "$release/$binding"
  printf '[[package]]\nname = "v8"\nversion = "150.4.0"\nsource = "registry"\n' > "$source_dir/codex-rs/Cargo.lock"
  write_sums
  export RUSTY_V8_BASE_URL="file://$BATS_TEST_TMPDIR/release"
}

write_sums() {
  (cd "$release" && shasum -a 256 "$archive" "$binding" > "$sums")
}

@test "derives the V8 version from Cargo.lock" {
  run sh "$MAVERGREEN_ROOT/build/fetch-rusty-v8.sh" "$source_dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"fetch-rusty-v8: v8 150.4.0"* ]]
  dir="$(sh "$MAVERGREEN_ROOT/build/resolve-build-root.sh")/rusty-v8-150.4.0"
  [ -f "$dir/$archive" ]
  [ -f "$dir/$binding" ]
  out=$(sh "$MAVERGREEN_ROOT/build/fetch-rusty-v8.sh" "$source_dir" 2>/dev/null)
  [ "$out" = "$dir/$archive
$dir/$binding" ]
}

@test "rejects an asset the checksums file does not list" {
  (cd "$release" && shasum -a 256 "$binding" > "$sums")
  run sh "$MAVERGREEN_ROOT/build/fetch-rusty-v8.sh" "$source_dir"
  [ "$status" -ne 0 ]
  [[ "$output" == *"$archive"* ]]
  [ ! -e "$MAVERICKS_BUILD_ROOT/rusty-v8-150.4.0/$archive" ]
}

@test "rejects an asset whose bytes do not match" {
  printf 'tampered\n' > "$release/$archive"
  run sh "$MAVERGREEN_ROOT/build/fetch-rusty-v8.sh" "$source_dir"
  [ "$status" -ne 0 ]
  [ ! -e "$MAVERICKS_BUILD_ROOT/rusty-v8-150.4.0/$archive" ]
}

@test "refuses a Cargo.lock without exactly one v8 package" {
  printf '[[package]]\nname = "other"\nversion = "1.0.0"\n' > "$source_dir/codex-rs/Cargo.lock"
  run sh "$MAVERGREEN_ROOT/build/fetch-rusty-v8.sh" "$source_dir"
  [ "$status" -eq 2 ]
  printf '[[package]]\nname = "v8"\nversion = "1.0.0"\n[[package]]\nname = "v8"\nversion = "2.0.0"\n' > "$source_dir/codex-rs/Cargo.lock"
  run sh "$MAVERGREEN_ROOT/build/fetch-rusty-v8.sh" "$source_dir"
  [ "$status" -eq 2 ]
}

@test "exits 2 with usage when given no source dir" {
  run sh "$MAVERGREEN_ROOT/build/fetch-rusty-v8.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage: fetch-rusty-v8.sh SOURCE-DIR"* ]]
}

@test "re-verifies a cached archive" {
  run sh "$MAVERGREEN_ROOT/build/fetch-rusty-v8.sh" "$source_dir"
  [ "$status" -eq 0 ]
  cached="$MAVERICKS_BUILD_ROOT/rusty-v8-150.4.0/$archive"
  : > "$cached"
  run sh "$MAVERGREEN_ROOT/build/fetch-rusty-v8.sh" "$source_dir"
  [ "$status" -eq 0 ]
  cmp "$cached" "$release/$archive"
}

@test "leaves no temporary files in the build root" {
  run sh "$MAVERGREEN_ROOT/build/fetch-rusty-v8.sh" "$source_dir"
  [ "$status" -eq 0 ]
  [ -z "$(find "$MAVERICKS_BUILD_ROOT" -name '.rusty-v8.*')" ]
}
