#!/usr/bin/env bats
# platform: macOS-only -- the fixtures are compiled with cc and edited with install_name_tool

setup() {
  export PRODUCT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  stub="$BATS_TEST_TMPDIR/stub"
  printf 'int main(void) { return 0; }\n' > "$BATS_TEST_TMPDIR/stub.c"
  # It links libz weakly and CoreFoundation, so each kind of OS load path is present to rewrite.
  cc -o "$stub" "$BATS_TEST_TMPDIR/stub.c" -framework CoreFoundation \
    -Wl,-weak_library,/usr/lib/libz.dylib -Wl,-headerpad_max_install_names
}

check() { sh "$PRODUCT_ROOT/build/check-load-paths.sh" "$@"; }

# libpath NAME BINARY: the path BINARY loads whose leaf starts with NAME
libpath() { otool -L "$2" | awk -v n="$1" 'NR > 1 && $1 ~ ("/" n "[^/]*$") { print $1 }'; }

@test "a binary that loads only /usr/lib and /System/Library libraries passes" {
  run check "$stub"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a library outside /usr/lib and /System/Library is refused" {
  install_name_tool -change "$(libpath libSystem "$stub")" /opt/pkg/lib/libSystem.B.dylib "$stub"
  run check "$stub"
  [ "$status" -eq 1 ]
  [ "$output" = "check-load-paths: $stub: LC_LOAD_DYLIB /opt/pkg/lib/libSystem.B.dylib is outside /usr/lib/ and /System/Library/" ]
}

@test "a weak library outside /usr/lib and /System/Library is refused" {
  install_name_tool -change "$(libpath libz "$stub")" /opt/pkg/lib/libz.1.dylib "$stub"
  run check "$stub"
  [ "$status" -eq 1 ]
  [ "$output" = "check-load-paths: $stub: LC_LOAD_WEAK_DYLIB /opt/pkg/lib/libz.1.dylib is outside /usr/lib/ and /System/Library/" ]
}

@test "a re-exported library outside /usr/lib and /System/Library is refused" {
  cc -dynamiclib -o "$BATS_TEST_TMPDIR/libstub.dylib" "$BATS_TEST_TMPDIR/stub.c" \
    -Wl,-reexport_library,/usr/lib/libz.dylib -Wl,-headerpad_max_install_names
  run check "$BATS_TEST_TMPDIR/libstub.dylib"
  [ "$status" -eq 0 ]
  install_name_tool -change "$(libpath libz "$BATS_TEST_TMPDIR/libstub.dylib")" \
    /usr/local/lib/libz.1.dylib "$BATS_TEST_TMPDIR/libstub.dylib"
  run check "$BATS_TEST_TMPDIR/libstub.dylib"
  [ "$status" -eq 1 ]
  [ "$output" = "check-load-paths: $BATS_TEST_TMPDIR/libstub.dylib: LC_REEXPORT_DYLIB /usr/local/lib/libz.1.dylib is outside /usr/lib/ and /System/Library/" ]
}

@test "a path that climbs out of /usr/lib is refused" {
  install_name_tool -change "$(libpath libSystem "$stub")" /usr/lib/../../opt/pkg/lib/libSystem.B.dylib "$stub"
  run check "$stub"
  [ "$status" -eq 1 ]
  [ "$output" = "check-load-paths: $stub: LC_LOAD_DYLIB /usr/lib/../../opt/pkg/lib/libSystem.B.dylib is outside /usr/lib/ and /System/Library/" ]
}

@test "any LC_RPATH is refused, even one inside /usr/lib" {
  install_name_tool -add_rpath /usr/lib "$stub"
  run check "$stub"
  [ "$status" -eq 1 ]
  [ "$output" = "check-load-paths: $stub: LC_RPATH /usr/lib (an rpath can reach any directory)" ]
}

@test "every binary named is checked, and each refusal is reported" {
  cp "$stub" "$BATS_TEST_TMPDIR/clean"
  install_name_tool -add_rpath /opt/pkg/lib "$stub"
  run check "$BATS_TEST_TMPDIR/clean" "$stub"
  [ "$status" -eq 1 ]
  [ "$output" = "check-load-paths: $stub: LC_RPATH /opt/pkg/lib (an rpath can reach any directory)" ]
  install_name_tool -change "$(libpath libSystem "$stub")" /opt/pkg/lib/libSystem.B.dylib "$stub"
  run check "$stub" "$BATS_TEST_TMPDIR/clean"
  [ "$status" -eq 1 ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "a file that is not Mach-O is refused" {
  printf 'not a binary\n' > "$BATS_TEST_TMPDIR/text"
  run check "$BATS_TEST_TMPDIR/text"
  [ "$status" -eq 1 ]
  [ "$output" = "check-load-paths: $BATS_TEST_TMPDIR/text is not a Mach-O file" ]
}

@test "no binary, or a missing one, is a usage error" {
  run check
  [ "$status" -eq 2 ]
  run check "$BATS_TEST_TMPDIR/missing"
  [ "$status" -eq 2 ]
}
