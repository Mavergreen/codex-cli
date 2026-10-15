#!/usr/bin/env bats
# platform: macOS-only -- verify-artifact.sh reads load commands with otool, and some fixtures are
#           compiled with cc and edited with install_name_tool

setup() {
  export PRODUCT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export SHIPYARD_SCRIPTS="${SHIPYARD_SCRIPTS:-/home/schmonz/Documents/trees/mavergreen-shipyard/scripts}"
  export MAVERICKS_BUILD_ROOT="$BATS_TEST_TMPDIR/local-build"
  mkdir -p "$MAVERICKS_BUILD_ROOT/input"
  export CODEX_ARTIFACT="$MAVERICKS_BUILD_ROOT/input/codex"
  export HOST_ARTIFACT="$MAVERICKS_BUILD_ROOT/input/codex-code-mode-host"
  export BUILD_MANIFEST="$MAVERICKS_BUILD_ROOT/input/build-manifest"
  export ARCHIVE="$MAVERICKS_BUILD_ROOT/input/codex.tar"
  export CHECKSUM="$ARCHIVE.sha256"
  make_manifest x86_64-apple-darwin 10.9 "$(cat "$PRODUCT_ROOT/build/codex-revision")" \
    "$(cat "$PRODUCT_ROOT/components/rust/version")"
  make_binary x86_64 "$CODEX_ARTIFACT"
  make_binary x86_64 "$HOST_ARTIFACT"
  echo "Apache License" > "$MAVERICKS_BUILD_ROOT/input/LICENSE"
  echo "Copyright OpenAI" > "$MAVERICKS_BUILD_ROOT/input/NOTICE"
  make_archive
}

make_manifest() {
  printf 'target=%s\ndeployment_target=%s\nsource_revision=%s\nrust_version=%s\nrusty_v8_version=150.4.0\n' \
    "$1" "$2" "$3" "$4" > "$BUILD_MANIFEST"
}

make_binary() {
  case "$1" in
    x86_64) cpu='\007\000\000\001' ;;
    arm64) cpu='\014\000\000\001' ;;
    *) cpu='\007\000\000\001' ;;
  esac
  printf '\317\372\355\376%b\003\000\000\000\002\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000' \
    "$cpu" > "$2"
  chmod +x "$2"
}

make_archive() {
  tar -cf "$ARCHIVE" -C "$(dirname "$CODEX_ARTIFACT")" codex codex-code-mode-host build-manifest LICENSE NOTICE
  (cd "$(dirname "$ARCHIVE")" && shasum -a 256 "$(basename "$ARCHIVE")" > "$(basename "$CHECKSUM")")
}

@test "verifies a matching x86_64 Mavericks artifact" {
  run sh "$PRODUCT_ROOT/build/verify-artifact.sh" "$ARCHIVE" "$CHECKSUM" x86_64-apple-darwin
  [ "$status" -eq 0 ]
}

# Apple's /usr/bin/file spells the type "Mach-O 64-bit executable x86_64", not upstream's
# "Mach-O 64-bit x86_64 executable". Putting /usr/bin first keeps a host's pkgsrc or Homebrew
# file(1) from answering for it.
@test "verifies a matching artifact with Apple's file(1)" {
  [ -x /usr/bin/file ] || skip "no /usr/bin/file"
  PATH="/usr/bin:/bin:$PATH" run sh "$PRODUCT_ROOT/build/verify-artifact.sh" "$ARCHIVE" "$CHECKSUM" x86_64-apple-darwin
  [ "$status" -eq 0 ]
  [ "$output" = "verify-artifact: ok (x86_64-apple-darwin, macOS 10.9)" ]
}

@test "rejects an arm64 codex with Apple's file(1)" {
  [ -x /usr/bin/file ] || skip "no /usr/bin/file"
  make_binary arm64 "$CODEX_ARTIFACT"
  make_archive
  PATH="/usr/bin:/bin:$PATH" run sh "$PRODUCT_ROOT/build/verify-artifact.sh" "$ARCHIVE" "$CHECKSUM" x86_64-apple-darwin
  [ "$status" -eq 1 ]
  [ "$output" = "verify-artifact: codex is not an x86_64 Mach-O executable" ]
}

@test "rejects an archive whose bytes no longer match its checksum" {
  printf x >> "$ARCHIVE"
  run sh "$PRODUCT_ROOT/build/verify-artifact.sh" "$ARCHIVE" "$CHECKSUM" x86_64-apple-darwin
  [ "$status" -ne 0 ]
}

@test "rejects an artifact built from a different pinned revision" {
  make_manifest x86_64-apple-darwin 10.9 wrong-revision \
    "$(cat "$PRODUCT_ROOT/components/rust/version")"
  make_archive
  run sh "$PRODUCT_ROOT/build/verify-artifact.sh" "$ARCHIVE" "$CHECKSUM" x86_64-apple-darwin
  [ "$status" -ne 0 ]
}

@test "rejects the wrong Mach-O architecture" {
  make_binary arm64 "$CODEX_ARTIFACT"
  make_archive
  run sh "$PRODUCT_ROOT/build/verify-artifact.sh" "$ARCHIVE" "$CHECKSUM" x86_64-apple-darwin
  [ "$status" -ne 0 ]
}

@test "rejects a binary without its executable bit" {
  chmod -x "$CODEX_ARTIFACT"
  make_archive
  run sh "$PRODUCT_ROOT/build/verify-artifact.sh" "$ARCHIVE" "$CHECKSUM" x86_64-apple-darwin
  [ "$status" -ne 0 ]
}

@test "rejects an archive missing NOTICE" {
  tar -cf "$ARCHIVE" -C "$(dirname "$CODEX_ARTIFACT")" codex codex-code-mode-host build-manifest LICENSE
  (cd "$(dirname "$ARCHIVE")" && shasum -a 256 "$(basename "$ARCHIVE")" > "$(basename "$CHECKSUM")")
  run sh "$PRODUCT_ROOT/build/verify-artifact.sh" "$ARCHIVE" "$CHECKSUM" x86_64-apple-darwin
  [ "$status" -ne 0 ]
  [[ "$output" == *"LICENSE and NOTICE"* ]] || false
}

@test "rejects an archive missing codex-code-mode-host" {
  tar -cf "$ARCHIVE" -C "$(dirname "$CODEX_ARTIFACT")" codex build-manifest LICENSE NOTICE
  (cd "$(dirname "$ARCHIVE")" && shasum -a 256 "$(basename "$ARCHIVE")" > "$(basename "$CHECKSUM")")
  run sh "$PRODUCT_ROOT/build/verify-artifact.sh" "$ARCHIVE" "$CHECKSUM" x86_64-apple-darwin
  [ "$status" -ne 0 ]
}

@test "rejects a codex-code-mode-host without its executable bit" {
  chmod -x "$HOST_ARTIFACT"
  make_archive
  run sh "$PRODUCT_ROOT/build/verify-artifact.sh" "$ARCHIVE" "$CHECKSUM" x86_64-apple-darwin
  [ "$status" -ne 0 ]
}

@test "rejects an arm64 codex-code-mode-host" {
  make_binary arm64 "$HOST_ARTIFACT"
  make_archive
  run sh "$PRODUCT_ROOT/build/verify-artifact.sh" "$ARCHIVE" "$CHECKSUM" x86_64-apple-darwin
  [ "$status" -ne 0 ]
}

# make_leaky_binary PATH: an x86_64 executable with an LC_RPATH into /opt/pkg
make_leaky_binary() {
  printf 'int main(void) { return 0; }\n' > "$BATS_TEST_TMPDIR/stub.c"
  cc -arch x86_64 -o "$1" "$BATS_TEST_TMPDIR/stub.c" -Wl,-headerpad_max_install_names
  install_name_tool -add_rpath /opt/pkg/lib "$1"
}

@test "rejects a codex that loads from outside the OS" {
  make_leaky_binary "$CODEX_ARTIFACT"
  make_archive
  run sh "$PRODUCT_ROOT/build/verify-artifact.sh" "$ARCHIVE" "$CHECKSUM" x86_64-apple-darwin
  [ "$status" -eq 1 ]
  [ "${lines[1]}" = "verify-artifact: a member loads a library from outside the OS" ]
  [[ "${lines[0]}" == *"/codex: LC_RPATH /opt/pkg/lib"* ]] || false
}

@test "rejects a codex-code-mode-host that loads from outside the OS" {
  make_leaky_binary "$HOST_ARTIFACT"
  make_archive
  run sh "$PRODUCT_ROOT/build/verify-artifact.sh" "$ARCHIVE" "$CHECKSUM" x86_64-apple-darwin
  [ "$status" -eq 1 ]
  [ "${lines[1]}" = "verify-artifact: a member loads a library from outside the OS" ]
  [[ "${lines[0]}" == *"/codex-code-mode-host: LC_RPATH /opt/pkg/lib"* ]] || false
}

@test "rejects a manifest without a well-formed rusty_v8_version" {
  sed 's/^rusty_v8_version=.*/rusty_v8_version=bogus/' "$BUILD_MANIFEST" > "$BUILD_MANIFEST.new"
  mv "$BUILD_MANIFEST.new" "$BUILD_MANIFEST"
  make_archive
  run sh "$PRODUCT_ROOT/build/verify-artifact.sh" "$ARCHIVE" "$CHECKSUM" x86_64-apple-darwin
  [ "$status" -ne 0 ]
}
