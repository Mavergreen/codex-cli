#!/usr/bin/env bats
# platform: macOS-only -- the Linux stand-in for plistutil converts with this Mac's plutil
# spec: build/decl-plist.sh header -- a provider declaration (JSON) becomes an xml1 plist that
#       `stevedore plist get` reads: plutil on a Mac, libplist's plistutil on Linux.

setup() {
  export PRODUCT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  json="$BATS_TEST_TMPDIR/decl.json"
  printf '{"schema":1,"build":{"archive_path":"lib/x.a"},"providers":[{"provider_id":"p.v1"}]}\n' > "$json"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/plistutil" <<'PU'
#!/bin/sh
echo "$*" >> "$BATS_TEST_TMPDIR/plistutil.calls"
[ "$1" = --version ] && { echo "plistutil 2.3.0"; exit 0; }
# -i IN -o OUT -f xml
exec plutil -convert xml1 -o "$4" "$2"
PU
  chmod +x "$BATS_TEST_TMPDIR/bin/plistutil"
  export BATS_TEST_TMPDIR
}

linux() { CODEX_DECL_HOST=Linux PATH="$BATS_TEST_TMPDIR/bin:$PATH" "$@"; }

@test "on Linux the declaration is converted by plistutil" {
  run linux sh "$PRODUCT_ROOT/build/decl-plist.sh" "$json" "$BATS_TEST_TMPDIR/decl.plist"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(cat "$BATS_TEST_TMPDIR/plistutil.calls")" = "-i $json -o $BATS_TEST_TMPDIR/decl.plist -f xml" ]
  grep -q '<string>lib/x.a</string>' "$BATS_TEST_TMPDIR/decl.plist"
}

@test "on a Mac the declaration is converted by plutil" {
  run sh "$PRODUCT_ROOT/build/decl-plist.sh" "$json" "$BATS_TEST_TMPDIR/decl.plist"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -q '<string>p.v1</string>' "$BATS_TEST_TMPDIR/decl.plist"
}

@test "--tool names the converter and its version, for the build manifest" {
  run linux sh "$PRODUCT_ROOT/build/decl-plist.sh" --tool
  [ "$output" = "plistutil 2.3.0" ]
  run sh "$PRODUCT_ROOT/build/decl-plist.sh" --tool
  [ "$output" = plutil ]
}

@test "on Linux without plistutil it says which package to install" {
  CODEX_DECL_HOST=Linux PATH=/usr/bin:/bin run sh "$PRODUCT_ROOT/build/decl-plist.sh" "$json" "$BATS_TEST_TMPDIR/decl.plist"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no plistutil: install libplist-utils"* ]] || false
}

@test "a declaration that is not JSON is refused and leaves no output" {
  echo 'not json' > "$json"
  run linux sh "$PRODUCT_ROOT/build/decl-plist.sh" "$json" "$BATS_TEST_TMPDIR/decl.plist"
  [ "$status" -eq 1 ]
  [ ! -e "$BATS_TEST_TMPDIR/decl.plist" ]
}
