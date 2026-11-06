#!/usr/bin/env bats
# platform: macOS-only -- plutil reads the provider declaration, and shipyard's provider helper builds against the host SDK
# spec: build/fetch-recaulk-objc.sh header -- the Recaulk Objective-C provider the codex binary links is
#       either the pinned release, fetched and verified through shipyard's fetch_product_pkg.sh, or a
#       staged prefix named explicitly by CODEX_DEV_RECAULK_PREFIX, which is development-only. Both are
#       validated by shipyard's own declaration check (objc-provider-link-args.sh) and then for the one
#       provider Codex needs. There is no fallback to an installed Recaulk.
# The product runs from a scratch copy whose shipyard is the real one but for a stand-in
# fetch_product_pkg.sh, the network boundary. The provider is a small archive built here and declared
# in the shape Recaulk's build/build-objc.sh declares its own (tests/lib/objc-provider-fixture.sh);
# CODEX_TEST_RECAULK_PREFIX, when set, is a real staged Recaulk prefix that must pass too.
. "$BATS_TEST_DIRNAME/lib/objc-provider-fixture.sh"

setup() {
  export PRODUCT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  : "${SHIPYARD_SCRIPTS:?set SHIPYARD_SCRIPTS to the scripts of shipyard}"
  REAL_SHIPYARD=$SHIPYARD_SCRIPTS
  # platform: the build root stays the caller's: shipyard's helpers build and cache their analyzer
  #           there, and the stand-in fetch below writes nothing into it.
  product="$BATS_TEST_TMPDIR/product"
  shipyard="$BATS_TEST_TMPDIR/shipyard/scripts"
  calls="$BATS_TEST_TMPDIR/fetch-calls"
  mkdir -p "$product" "$shipyard"
  cp -R "$PRODUCT_ROOT/build" "$PRODUCT_ROOT/components" "$PRODUCT_ROOT/packaging" "$PRODUCT_ROOT/UPSTREAM_VERSION" "$product/"
  rm -f "$product/components/recaulk/version"
  # shipyard's helpers find their tools, pins and references beside scripts/, so the scratch
  # shipyard links every other top-level entry of the real one.
  for entry in "$REAL_SHIPYARD"/../*; do
    [ "$(basename "$entry")" = scripts ] || ln -s "$(cd "$entry" 2>/dev/null && pwd || echo "$entry")" "$shipyard/../"
  done
  for script in "$REAL_SHIPYARD"/*; do ln -s "$script" "$shipyard/"; done
  rm "$shipyard/fetch_product_pkg.sh"
  # The stand-in passes any other product (the analyzer's pinned toolchain) to the real script. For
  # recaulk it records its arguments and answers with FETCH_ANSWER (a prefix), or fails as a
  # release with no listed asset does.
  cat > "$shipyard/fetch_product_pkg.sh" <<EOF
#!/bin/sh
case "\$*" in recaulk\ *) ;; *) exec sh "$REAL_SHIPYARD/fetch_product_pkg.sh" "\$@" ;; esac
printf '%s\n' "\$*" >> "$calls"
[ -n "\${FETCH_ANSWER:-}" ] || { echo "fetch_product_pkg: recaulk-\$2.pkg is not listed (once) in SHA256SUMS" >&2; exit 1; }
printf '%s\n' "\$FETCH_ANSWER"
EOF
  chmod +x "$shipyard/fetch_product_pkg.sh"
  export SHIPYARD_SCRIPTS="$shipyard"
  unset CODEX_DEV_RECAULK_PREFIX FETCH_ANSWER
  sdk=$(sh "$REAL_SHIPYARD/fetch_sdk.sh" --arch x86_64)
}

fixture_prefix() { objc_fixture_prefix "$1" "$sdk"; }
mutate() { objc_fixture_mutate "$1" "$2"; }

fetch() { run sh "$product/build/fetch-recaulk-objc.sh"; }
# refused [WHY]: the helper itself refused (not a missing script or a shell error), saying WHY.
refused() {
  [ "$status" -ne 0 ] && [ "$status" -ne 127 ] && [[ "$output" == *"fetch-recaulk-objc: ${1:-}"* ]] && [[ "$output" != *"did not build"* ]] ||
    { echo "not refused for ${1:-any reason}: status $status: $output"; false; }
}

@test "an explicit development prefix is verified and printed with development origin" {
  fixture_prefix "$BATS_TEST_TMPDIR/staged"
  CODEX_DEV_RECAULK_PREFIX="$BATS_TEST_TMPDIR/staged" fetch
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # stdout is exactly the three lines a caller reads; everything else goes to stderr
  stdout=$(CODEX_DEV_RECAULK_PREFIX="$BATS_TEST_TMPDIR/staged" sh "$product/build/fetch-recaulk-objc.sh" 2>/dev/null)
  [ "$stdout" = "$BATS_TEST_TMPDIR/staged
development
development" ] || { echo "stdout: $stdout"; false; }
  [ ! -e "$calls" ]
}

@test "a development prefix stays development with a production pin and a BUILD_ID" {
  fixture_prefix "$BATS_TEST_TMPDIR/staged"
  mkdir -p "$product/components/recaulk"
  echo 20261201.1 > "$product/components/recaulk/version"
  echo 0.165.0-mavericks.7 > "$product/BUILD_ID"
  CODEX_DEV_RECAULK_PREFIX="$BATS_TEST_TMPDIR/staged" fetch
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | tail -2 | sed -n 1p)" = development ]
  [ ! -e "$calls" ]
}

@test "without a production pin or a development prefix nothing is fetched or borrowed from an installed Recaulk" {
  fetch
  refused "no components/recaulk/version"
  [[ "$output" == *"CODEX_DEV_RECAULK_PREFIX"* ]] || false
  [[ "$output" != *"/usr/local/mavergreen"* ]] || false
  [ ! -e "$calls" ]
}

@test "a pinned release is fetched through shipyard's verified product fetch and marked released" {
  fixture_prefix "$BATS_TEST_TMPDIR/released"
  mkdir -p "$product/components/recaulk"
  echo 20261201.1 > "$product/components/recaulk/version"
  FETCH_ANSWER="$BATS_TEST_TMPDIR/released" fetch
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  stdout=$(FETCH_ANSWER="$BATS_TEST_TMPDIR/released" sh "$product/build/fetch-recaulk-objc.sh" 2>/dev/null)
  [ "$stdout" = "$BATS_TEST_TMPDIR/released
released
20261201.1" ] || { echo "stdout: $stdout"; false; }
  grep -qx "recaulk 20261201.1 $(sh "$product/build/resolve-build-root.sh")/recaulk-20261201.1" "$calls"
}

@test "a release whose asset or checksum is missing fails" {
  mkdir -p "$product/components/recaulk"
  echo 20261201.1 > "$product/components/recaulk/version"
  fetch
  refused "could not fetch and verify Recaulk 20261201.1"
  [[ "$output" == *"not listed"* ]] || false
}

@test "a malformed production pin is refused before any fetch" {
  mkdir -p "$product/components/recaulk"
  echo 'latest' > "$product/components/recaulk/version"
  fetch
  refused "components/recaulk/version holds"
  [ ! -e "$calls" ]
}

@test "an archive whose bytes differ from the declared digest is refused" {
  fixture_prefix "$BATS_TEST_TMPDIR/staged"
  printf 'x' >> "$BATS_TEST_TMPDIR/staged/lib/librecaulk-objc.a"
  CODEX_DEV_RECAULK_PREFIX="$BATS_TEST_TMPDIR/staged" fetch
  refused "shipyard refused the provider declaration"
}

@test "a declaration digest that names other bytes is refused" {
  fixture_prefix "$BATS_TEST_TMPDIR/staged"
  mutate "$BATS_TEST_TMPDIR/staged" 's/"archive_sha256" : "[0-9a-f]*"/"archive_sha256" : "0000000000000000000000000000000000000000000000000000000000000000"/'
  CODEX_DEV_RECAULK_PREFIX="$BATS_TEST_TMPDIR/staged" fetch
  refused "shipyard refused the provider declaration"
}

@test "a native-test slice is refused" {
  fixture_prefix "$BATS_TEST_TMPDIR/staged"
  mutate "$BATS_TEST_TMPDIR/staged" 's/"artifact_role" : "shipping"/"artifact_role" : "native-test-only"/'
  CODEX_DEV_RECAULK_PREFIX="$BATS_TEST_TMPDIR/staged" fetch
  refused "shipyard refused the provider declaration"
}

@test "another architecture is refused" {
  fixture_prefix "$BATS_TEST_TMPDIR/staged"
  mutate "$BATS_TEST_TMPDIR/staged" 's/"architecture" : "x86_64"/"architecture" : "arm64"/'
  CODEX_DEV_RECAULK_PREFIX="$BATS_TEST_TMPDIR/staged" fetch
  refused "shipyard refused the provider declaration"
}

@test "another provider ID is refused" {
  fixture_prefix "$BATS_TEST_TMPDIR/staged"
  mutate "$BATS_TEST_TMPDIR/staged" 's/recaulk.nsworkspace.open-urls.v1/recaulk.nsworkspace.open-urls.v2/'
  CODEX_DEV_RECAULK_PREFIX="$BATS_TEST_TMPDIR/staged" fetch
  refused
  [[ "$output" == *"recaulk.nsworkspace.open-urls.v1"* ]] || false
}

@test "a wrong ABI is refused" {
  fixture_prefix "$BATS_TEST_TMPDIR/staged"
  mutate "$BATS_TEST_TMPDIR/staged" 's/"@56@0:8@16@24Q32@40^@48"/"@56@0:8@16@24I32@40^@48"/'
  CODEX_DEV_RECAULK_PREFIX="$BATS_TEST_TMPDIR/staged" fetch
  refused
}

@test "another selector, method kind or class is refused" {
  for expr in 's/"selector" : "openURLs:/"selector" : "openURL:/' \
              's/"method_kind" : "-"/"method_kind" : "+"/' \
              's/"class" : "NSWorkspace"/"class" : "NSApplication"/'; do
    rm -rf "$BATS_TEST_TMPDIR/staged" "$BATS_TEST_TMPDIR/staged.objects"
    fixture_prefix "$BATS_TEST_TMPDIR/staged"
    mutate "$BATS_TEST_TMPDIR/staged" "$expr"
    CODEX_DEV_RECAULK_PREFIX="$BATS_TEST_TMPDIR/staged" fetch
    refused || { echo "accepted after $expr"; false; }
  done
}

@test "a missing activation root is refused" {
  fixture_prefix "$BATS_TEST_TMPDIR/staged"
  mutate "$BATS_TEST_TMPDIR/staged" '/"activation_root"/d'
  CODEX_DEV_RECAULK_PREFIX="$BATS_TEST_TMPDIR/staged" fetch
  refused "shipyard refused the provider declaration"
}

@test "an old Recaulk without the provider declaration is refused, released or staged" {
  mkdir -p "$BATS_TEST_TMPDIR/old/lib"
  : > "$BATS_TEST_TMPDIR/old/lib/librecaulk.a"
  CODEX_DEV_RECAULK_PREFIX="$BATS_TEST_TMPDIR/old" fetch
  refused
  [[ "$output" == *"objc-providers.json"* ]] || false
  mkdir -p "$product/components/recaulk"
  echo 20261012.1 > "$product/components/recaulk/version"
  FETCH_ANSWER="$BATS_TEST_TMPDIR/old" fetch
  refused
  [[ "$output" == *"objc-providers.json"* ]] || false
}

@test "a relative or multi-line development prefix is refused" {
  fixture_prefix "$BATS_TEST_TMPDIR/staged"
  (cd "$BATS_TEST_TMPDIR" && CODEX_DEV_RECAULK_PREFIX=staged run sh "$product/build/fetch-recaulk-objc.sh"; refused "the Recaulk prefix must be an absolute path")
  CODEX_DEV_RECAULK_PREFIX="$BATS_TEST_TMPDIR/staged
/elsewhere" fetch
  refused "the Recaulk prefix holds a line break"
}

@test "a shipyard without the Objective-C provider interfaces is refused" {
  fixture_prefix "$BATS_TEST_TMPDIR/staged"
  for helper in objc-provider-link-args.sh objc-build-evidence.sh objc-compat.sh; do
    rm -rf "$shipyard.$helper"; cp -R "$shipyard" "$shipyard.$helper"; rm "$shipyard.$helper/$helper"
    SHIPYARD_SCRIPTS="$shipyard.$helper" CODEX_DEV_RECAULK_PREFIX="$BATS_TEST_TMPDIR/staged" fetch
    refused || { echo "accepted without $helper"; false; }
    [[ "$output" == *"$helper"* ]] || false
  done
}

@test "packaging refuses a build linked with a development provider, whatever its BUILD-ID" {
  out="$BATS_TEST_TMPDIR/codex-out"
  mkdir -p "$out"
  for f in codex codex-code-mode-host LICENSE NOTICE; do echo "$f" > "$out/$f"; done
  ver=$(sh "$product/build/codex-pin.sh" version)
  printf 'version=%s-mavericks.3\nmode=native\nrecaulk_origin=development\n' "$ver" > "$out/build-manifest"
  run sh "$product/packaging/build-codex-package.sh" "$out" "$ver-mavericks.3" "$BATS_TEST_TMPDIR/pkg"
  [ "$status" -ne 0 ]
  [[ "$output" == *"development"* ]] || false
  [ ! -e "$BATS_TEST_TMPDIR/pkg" ]
  printf 'version=%s-mavericks.3\nmode=native\n' "$ver" > "$out/build-manifest"
  run sh "$product/packaging/build-codex-package.sh" "$out" "$ver-mavericks.3" "$BATS_TEST_TMPDIR/pkg"
  [ "$status" -ne 0 ]
  [[ "$output" == *"recaulk_origin"* ]] || false
  printf 'version=%s-mavericks.3\nmode=native\nrecaulk_origin=released\n' "$ver" > "$out/build-manifest"
  run sh "$product/packaging/build-codex-package.sh" "$out" "$ver-mavericks.3" "$BATS_TEST_TMPDIR/pkg"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "a real staged Recaulk prefix passes" {
  [ -n "${CODEX_TEST_RECAULK_PREFIX:-}" ] || skip "CODEX_TEST_RECAULK_PREFIX names no staged Recaulk (Recaulk's build/build-objc.sh STAGE WORK)"
  CODEX_DEV_RECAULK_PREFIX="$CODEX_TEST_RECAULK_PREFIX" fetch
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | tail -2 | sed -n 1p)" = development ]
}
