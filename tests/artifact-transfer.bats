#!/usr/bin/env bats

setup() {
  export PRODUCT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export SHIPYARD_SCRIPTS="${SHIPYARD_SCRIPTS:-/home/schmonz/Documents/trees/mavergreen-shipyard/scripts}"
  export MAVERICKS_BUILD_ROOT="$BATS_TEST_TMPDIR/local-build"
  mkdir -p "$MAVERICKS_BUILD_ROOT/input"
  export CODEX_ARTIFACT="$MAVERICKS_BUILD_ROOT/input/codex"
  export BUILD_MANIFEST="$MAVERICKS_BUILD_ROOT/input/build-manifest"
  export ARCHIVE="$MAVERICKS_BUILD_ROOT/input/codex.tar"
  export CHECKSUM="$ARCHIVE.sha256"
  make_manifest x86_64-apple-darwin 10.9 "$(cat "$PRODUCT_ROOT/build/codex-revision")" \
    "$(cat "$PRODUCT_ROOT/mavericks-rust.pin")"
  make_binary x86_64
  make_archive
}

make_manifest() {
  printf 'target=%s\ndeployment_target=%s\nsource_revision=%s\nrust_revision=%s\n' \
    "$1" "$2" "$3" "$4" > "$BUILD_MANIFEST"
}

make_binary() {
  case "$1" in
    x86_64) cpu='\007\000\000\001' ;;
    arm64) cpu='\014\000\000\001' ;;
    *) cpu='\007\000\000\001' ;;
  esac
  printf '\317\372\355\376%b\003\000\000\000\002\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000' \
    "$cpu" > "$CODEX_ARTIFACT"
  chmod +x "$CODEX_ARTIFACT"
}

make_archive() {
  tar -cf "$ARCHIVE" -C "$(dirname "$CODEX_ARTIFACT")" codex build-manifest
  (cd "$(dirname "$ARCHIVE")" && shasum -a 256 "$(basename "$ARCHIVE")" > "$(basename "$CHECKSUM")")
}

@test "verifies a matching x86_64 Mavericks artifact" {
  run sh "$PRODUCT_ROOT/build/verify-artifact.sh" "$ARCHIVE" "$CHECKSUM" x86_64-apple-darwin
  [ "$status" -eq 0 ]
}

@test "rejects an archive whose bytes no longer match its checksum" {
  printf x >> "$ARCHIVE"
  run sh "$PRODUCT_ROOT/build/verify-artifact.sh" "$ARCHIVE" "$CHECKSUM" x86_64-apple-darwin
  [ "$status" -ne 0 ]
}

@test "rejects an artifact built from a different pinned revision" {
  make_manifest x86_64-apple-darwin 10.9 wrong-revision \
    "$(cat "$PRODUCT_ROOT/mavericks-rust.pin")"
  make_archive
  run sh "$PRODUCT_ROOT/build/verify-artifact.sh" "$ARCHIVE" "$CHECKSUM" x86_64-apple-darwin
  [ "$status" -ne 0 ]
}

@test "rejects the wrong Mach-O architecture" {
  make_binary arm64
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
