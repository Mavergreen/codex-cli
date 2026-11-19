#!/usr/bin/env bats
# platform: macOS-only -- the LLVM tools come from the pinned clang-22 pkg, which fetch-clang-22.sh expands

# build/strip-v8-cxxabi.sh against stand-ins for OpenAI's rusty_v8 archive
# (tests/fixtures/v8-strip/make-fixtures.sh writes them).
setup_file() {
  ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export SHIPYARD_SCRIPTS="${SHIPYARD_SCRIPTS:-/usr/local/mavergreen/shipyard/share/cmake/MavericksShipyard/scripts}"
  bin=$(sh "$ROOT/tests/lib/llvm-bin.sh") || { rc=$?; [ "$rc" -eq 77 ] && skip "not on macOS"; return "$rc"; }
  export AR="$bin/llvm-ar" NM="$bin/llvm-nm" LIPO="$bin/llvm-lipo" OTOOL="$bin/llvm-otool"
}

setup() {
  ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  FIX="$ROOT/tests/fixtures/v8-strip"
  STRIP="$ROOT/build/strip-v8-cxxabi.sh"
  [ -r "$SHIPYARD_SCRIPTS/macho-cxxabi.sh" ] || skip "no macho-cxxabi.sh in $SHIPYARD_SCRIPTS"
}

machinery() { sh "$SHIPYARD_SCRIPTS/macho-cxxabi.sh" "$1" | grep ' defines ' || true; }

@test "strips the listed members" {
  run sh "$STRIP" "$FIX/good.a" "$BATS_TEST_TMPDIR/out.a"
  [ "$status" -eq 0 ]
  [ "$output" = "$(sh "$STRIP" --list)" ]
  members=$("$AR" t "$BATS_TEST_TMPDIR/out.a")
  [ "$members" = "v8code.pic.o" ]
  [ -z "$(machinery "$BATS_TEST_TMPDIR/out.a")" ]
}

@test "--list names the sixteen libc++abi members" {
  run sh "$STRIP" --list
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 16 ]
  printf '%s\n' "$output" | grep -qx 'cxa_personality.pic.o'
  printf '%s\n' "$output" | grep -qx 'private_typeinfo.pic.o'
}

@test "accepts a gzipped archive" {
  gzip -c "$FIX/good.a" > "$BATS_TEST_TMPDIR/good.a.gz"
  sh "$STRIP" "$FIX/good.a" "$BATS_TEST_TMPDIR/plain.a" >/dev/null
  run sh "$STRIP" "$BATS_TEST_TMPDIR/good.a.gz" "$BATS_TEST_TMPDIR/gz.a"
  [ "$status" -eq 0 ]
  cmp "$BATS_TEST_TMPDIR/plain.a" "$BATS_TEST_TMPDIR/gz.a"
}

@test "is deterministic" {
  sh "$STRIP" "$FIX/good.a" "$BATS_TEST_TMPDIR/one.a" >/dev/null
  sleep 1
  sh "$STRIP" "$FIX/good.a" "$BATS_TEST_TMPDIR/two.a" >/dev/null
  cmp "$BATS_TEST_TMPDIR/one.a" "$BATS_TEST_TMPDIR/two.a"
}

@test "leaves its input untouched" {
  before=$(shasum -a 256 < "$FIX/good.a")
  sh "$STRIP" "$FIX/good.a" "$BATS_TEST_TMPDIR/out.a" >/dev/null
  [ "$(shasum -a 256 < "$FIX/good.a")" = "$before" ]
}

@test "refuses a missing member" {
  run sh "$STRIP" "$FIX/missing.a" "$BATS_TEST_TMPDIR/out.a"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cxa_guard.pic.o"* ]] || false
  [ ! -e "$BATS_TEST_TMPDIR/out.a" ]
}

@test "refuses leftover machinery" {
  run sh "$STRIP" "$FIX/extra.a" "$BATS_TEST_TMPDIR/out.a"
  [ "$status" -eq 1 ]
  [[ "$output" == *"___cxa_thread_atexit"* ]] || false
  [ ! -e "$BATS_TEST_TMPDIR/out.a" ]
}

@test "refuses leftover machinery when the output path has a space" {
  mkdir -p "$BATS_TEST_TMPDIR/with space"
  run sh "$STRIP" "$FIX/extra.a" "$BATS_TEST_TMPDIR/with space/out.a"
  [ "$status" -eq 1 ]
  [[ "$output" == *"___cxa_thread_atexit"* ]] || false
  [ ! -e "$BATS_TEST_TMPDIR/with space/out.a" ]
}

@test "removes every copy of a repeated member" {
  run sh "$STRIP" "$FIX/twice.a" "$BATS_TEST_TMPDIR/out.a"
  [ "$status" -eq 0 ]
  ! "$AR" t "$BATS_TEST_TMPDIR/out.a" | grep -q 'cxa_vector' || false
}

@test "leaves an existing output alone when it refuses" {
  printf 'previous\n' > "$BATS_TEST_TMPDIR/out.a"
  run sh "$STRIP" "$FIX/extra.a" "$BATS_TEST_TMPDIR/out.a"
  [ "$status" -eq 1 ]
  [ "$(cat "$BATS_TEST_TMPDIR/out.a")" = previous ]
}

@test "usage" {
  run sh "$STRIP"
  [ "$status" -eq 2 ]
}
