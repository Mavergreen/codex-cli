#!/usr/bin/env bats
# platform: macOS-only -- the LLVM tools come from the pinned clang-22 pkg, which fetch-clang-22.sh expands

# build/check-cxxabi.sh against tiny dylibs linked here: one C++ runtime per Codex binary.
setup_file() {
  ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export SHIPYARD_SCRIPTS="${SHIPYARD_SCRIPTS:-/usr/local/mavergreen/shipyard/share/cmake/MavericksShipyard/scripts}"
  bin=$(sh "$ROOT/tests/lib/llvm-bin.sh") || { rc=$?; [ "$rc" -eq 77 ] && skip "not on macOS"; return "$rc"; }
  export LLVM_BIN="$bin" AR="$bin/llvm-ar" NM="$bin/llvm-nm" LIPO="$bin/llvm-lipo" OTOOL="$bin/llvm-otool"
}

setup() {
  ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CHECK="$ROOT/build/check-cxxabi.sh"
  [ -r "$SHIPYARD_SCRIPTS/macho-cxxabi.sh" ] || skip "no macho-cxxabi.sh in $SHIPYARD_SCRIPTS"
  # An allow-list archive standing in for Recaulk: it defines one runtime symbol, visibly.
  printf 'void __cxa_recaulk_backfill(void) {}\n' > "$BATS_TEST_TMPDIR/recaulk.c"
  "$LLVM_BIN/clang" --no-default-config --target=x86_64-apple-macos10.9 -c \
    -o "$BATS_TEST_TMPDIR/recaulk.o" "$BATS_TEST_TMPDIR/recaulk.c"
  "$AR" rcsD "$BATS_TEST_TMPDIR/librecaulk.a" "$BATS_TEST_TMPDIR/recaulk.o"
  export CODEX_CXXABI_RECAULK_ARCHIVE="$BATS_TEST_TMPDIR/librecaulk.a"
}

# dylib NAME SOURCE [EXTRA...]: links a dylib that needs no SDK
dylib() {
  name=$1; src=$2; shift 2
  printf '%s\n' "$src" > "$BATS_TEST_TMPDIR/$name.c"
  "$LLVM_BIN/clang" --no-default-config --target=x86_64-apple-macos10.9 -fuse-ld=lld -nostdlib \
    -dynamiclib -Wl,-undefined,dynamic_lookup -o "$BATS_TEST_TMPDIR/$name.dylib" "$BATS_TEST_TMPDIR/$name.c" "$@"
}

@test "a binary with no C++ runtime of its own passes" {
  dylib clean 'void v8_entry(void) {}'
  run sh "$CHECK" "$BATS_TEST_TMPDIR/clean.dylib"
  [ "$status" -eq 0 ]
}

@test "a binary that defines a C++ runtime fails, naming the symbol" {
  dylib runtime 'void __cxa_throw(void) {}'
  run sh "$CHECK" "$BATS_TEST_TMPDIR/runtime.dylib"
  [ "$status" -eq 1 ]
  [[ "$output" == *"___cxa_throw"* ]] || false
}

@test "a hidden runtime definition fails too" {
  dylib hidden '__attribute__((visibility("hidden"))) void __cxa_throw(void) {} void v8_entry(void) { __cxa_throw(); }'
  run sh "$CHECK" "$BATS_TEST_TMPDIR/hidden.dylib"
  [ "$status" -eq 1 ]
  [[ "$output" == *"___cxa_throw hidden"* ]] || false
}

@test "what the pinned Recaulk defines is allowed" {
  dylib backfill 'void __cxa_recaulk_backfill(void) {}'
  run sh "$CHECK" "$BATS_TEST_TMPDIR/backfill.dylib"
  [ "$status" -eq 0 ]
}

@test "loading a libc++abi other than the system's fails, naming it" {
  dylib abi 'void f(void) {}' -install_name /opt/elsewhere/libc++abi.1.dylib
  dylib loader 'void g(void) {}' "$BATS_TEST_TMPDIR/abi.dylib"
  run sh "$CHECK" "$BATS_TEST_TMPDIR/loader.dylib"
  [ "$status" -eq 1 ]
  [[ "$output" == *"/opt/elsewhere/libc++abi.1.dylib"* ]] || false
}

@test "loading the system's libc++abi passes" {
  dylib abi 'void f(void) {}' -install_name /usr/lib/libc++abi.dylib
  dylib loader 'void g(void) {}' "$BATS_TEST_TMPDIR/abi.dylib"
  run sh "$CHECK" "$BATS_TEST_TMPDIR/loader.dylib"
  [ "$status" -eq 0 ]
}

@test "a file it cannot read fails rather than passes" {
  printf 'not mach-o\n' > "$BATS_TEST_TMPDIR/text"
  run sh "$CHECK" "$BATS_TEST_TMPDIR/text"
  [ "$status" -ne 0 ]
}

@test "usage" {
  run sh "$CHECK"
  [ "$status" -eq 2 ]
}
