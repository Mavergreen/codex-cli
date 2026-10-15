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

# platform: macOS 27's bsdtar adds `._` AppleDouble members and pax xattr headers for the
#           com.apple.provenance xattr, which 10.9's tar cannot read. A provenance xattr cannot be
#           made on 10.9, so these tests check what transfer-artifact.sh asks tar to do and what it
#           writes, not the xattr handling itself.
make_transfer_source() {
  export TRANSFER_SOURCE="$BATS_TEST_TMPDIR/source"
  mkdir -p "$TRANSFER_SOURCE"
  cp "$CODEX_ARTIFACT" "$HOST_ARTIFACT" "$BUILD_MANIFEST" \
    "$MAVERICKS_BUILD_ROOT/input/LICENSE" "$MAVERICKS_BUILD_ROOT/input/NOTICE" "$TRANSFER_SOURCE/"
}

# A tar that records COPYFILE_DISABLE and its arguments, then runs the real one.
make_tar_spy() {
  mkdir -p "$BATS_TEST_TMPDIR/spy"
  real_tar=$(command -v tar)
  cat > "$BATS_TEST_TMPDIR/spy/tar" <<SPY
#!/bin/sh
printf 'COPYFILE_DISABLE=%s ARGS=%s\n' "\${COPYFILE_DISABLE-unset}" "\$*" >> "$BATS_TEST_TMPDIR/tar-calls"
exec "$real_tar" "\$@"
SPY
  chmod +x "$BATS_TEST_TMPDIR/spy/tar"
}

@test "transfer-artifact.sh archives with COPYFILE_DISABLE=1 and no AppleDouble member" {
  make_transfer_source
  make_tar_spy
  PATH="$BATS_TEST_TMPDIR/spy:$PATH" run sh "$PRODUCT_ROOT/build/transfer-artifact.sh" \
    "$TRANSFER_SOURCE" "$BATS_TEST_TMPDIR/dest"
  [ "$status" -eq 0 ]
  grep -q 'COPYFILE_DISABLE=1 ARGS=.*-cf .*codex.tar' "$BATS_TEST_TMPDIR/tar-calls"
  tar -tf "$BATS_TEST_TMPDIR/dest/codex.tar" > "$BATS_TEST_TMPDIR/members"
  [ "$(wc -l < "$BATS_TEST_TMPDIR/members" | tr -d '[:space:]')" -eq 5 ]
  run grep -q '\._' "$BATS_TEST_TMPDIR/members"
  [ "$status" -eq 1 ]
  [ "$(LC_ALL=C sort "$BATS_TEST_TMPDIR/members" | tr '\n' ' ')" = "LICENSE NOTICE build-manifest codex codex-code-mode-host " ]
}

@test "transfer-artifact.sh passes --no-xattrs only to a tar that accepts it" {
  make_transfer_source
  make_tar_spy
  PATH="$BATS_TEST_TMPDIR/spy:$PATH" run sh "$PRODUCT_ROOT/build/transfer-artifact.sh" \
    "$TRANSFER_SOURCE" "$BATS_TEST_TMPDIR/dest"
  [ "$status" -eq 0 ]
  if tar --no-xattrs -cf /dev/null /dev/null 2>/dev/null; then
    grep -q -- '--no-xattrs .*-cf .*codex.tar' "$BATS_TEST_TMPDIR/tar-calls"
  else
    run grep -q -- 'ARGS=--no-xattrs .*codex.tar' "$BATS_TEST_TMPDIR/tar-calls"
    [ "$status" -eq 1 ]
  fi
}

@test "rejects an archive with an AppleDouble member" {
  make_transfer_source
  # An AppleDouble-sized file, so a tar that lists the member does not trip over its contents.
  dd if=/dev/zero of="$TRANSFER_SOURCE/._codex" bs=512 count=1 2>/dev/null
  # COPYFILE_DISABLE=1: by default bsdtar folds a literal `._codex` into codex at create time (measured
  #           on macOS 27), so the member would never reach the archive.
  COPYFILE_DISABLE=1 tar -cf "$ARCHIVE" -C "$TRANSFER_SOURCE" codex codex-code-mode-host build-manifest LICENSE NOTICE ._codex
  # platform: 10.9's tar lists a `._codex` member, so verify-artifact.sh's member count refuses it. macOS 27's
  #           `tar -tf` treats `._X` as AppleDouble metadata for the entry that follows it: with `._codex`
  #           last it lists six names, then fails with "Truncated input file" (rc 1); elsewhere it folds
  #           the member silently and lists five. Skip unless the local tar lists it and succeeds.
  tar -tf "$ARCHIVE" > "$BATS_TEST_TMPDIR/listing" 2>/dev/null && grep -q '^\._codex$' "$BATS_TEST_TMPDIR/listing" ||
    skip "this host's tar folds AppleDouble members when listing, so it cannot list the ._codex member"
  (cd "$(dirname "$ARCHIVE")" && shasum -a 256 "$(basename "$ARCHIVE")" > "$(basename "$CHECKSUM")")
  run sh "$PRODUCT_ROOT/build/verify-artifact.sh" "$ARCHIVE" "$CHECKSUM" x86_64-apple-darwin
  [ "$status" -ne 0 ]
  [[ "$output" == *"exactly codex"* ]] || false
}
