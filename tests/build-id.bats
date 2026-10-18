#!/usr/bin/env bats
# platform: host-agnostic -- fixtures and plain sh; runs on ultimate-hat and modern macOS

# build-id.sh decides a build's identity and whether to publish it. It runs in a scratch copy of the
# product, against a channel listing (CODEX_BUILDS_ASSET_LIST) and build JSONs (CODEX_BUILDS_JSON_DIR)
# kept in files, so no test touches the network.
setup() {
  export PRODUCT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  product="$BATS_TEST_TMPDIR/product"
  mkdir -p "$product"
  cp -R "$PRODUCT_ROOT/build" "$PRODUCT_ROOT/components" "$PRODUCT_ROOT/patches" "$product/"
  mkdir -p "$product/packaging"
  cp "$PRODUCT_ROOT/packaging/build-codex-package.sh" "$product/packaging/"
  version=$(tr -d '[:space:]' < "$product/components/codex/version")
  export CODEX_BUILDS_ASSET_LIST="$BATS_TEST_TMPDIR/assets"
  export CODEX_BUILDS_JSON_DIR="$BATS_TEST_TMPDIR/json"
  mkdir -p "$CODEX_BUILDS_JSON_DIR"
  : > "$CODEX_BUILDS_ASSET_LIST"
}

state_of() {
  (cd "$product" && cat components/codex/version build/codex-revision components/rust/version \
    components/clang-22/version patches/*.patch packaging/build-codex-package.sh | shasum -a 256 | awk '{print $1}')
}

# ship CODEX_VERSION N STATE: the channel gains that build, as the asset list and its JSON
ship() {
  id="$1-mavericks.$2"
  printf 'codex-build-%s.json\ncodex-build-%s.json.sig\n' "$id" "$id" >> "$CODEX_BUILDS_ASSET_LIST"
  printf '{"tag_name":"rust-v%s","mavergreen_build":"%s","mavergreen_codex_version":"%s","mavergreen_min_pkg":"","mavergreen_state":"%s","assets":[]}\n' \
    "$id" "$id" "$1" "$3" > "$CODEX_BUILDS_JSON_DIR/codex-build-$id.json"
}

run_id() {
  run sh "$product/build/build-id.sh" "$@"
}

@test "an empty channel yields -mavericks.1 and publishes" {
  run_id auto
  [ "$status" -eq 0 ]
  [ "$output" = "ID=$version-mavericks.1
STATE=$(state_of)
PUBLISH=yes" ]
}

@test "a build of the same state is not published again" {
  ship "$version" 1 "$(state_of)"
  run_id auto
  [ "$status" -eq 0 ]
  [ "$output" = "ID=$version-mavericks.1
STATE=$(state_of)
PUBLISH=no" ]
}

@test "a build of a different state gets the next N" {
  ship "$version" 1 "$(printf 'x%.0s' 1 2 3 | shasum -a 256 | awk '{print $1}')"
  run_id auto
  [ "$status" -eq 0 ]
  [ "$output" = "ID=$version-mavericks.2
STATE=$(state_of)
PUBLISH=yes" ]
}

@test "the newest build is the highest N, compared numerically" {
  ship "$version" 2 "0000000000000000000000000000000000000000000000000000000000000000"
  ship "$version" 10 "$(state_of)"
  run_id auto
  [ "$status" -eq 0 ]
  [ "$output" = "ID=$version-mavericks.10
STATE=$(state_of)
PUBLISH=no" ]
}

@test "rebuild takes the next N even for the same state" {
  ship "$version" 1 "$(state_of)"
  ship "$version" 2 "$(state_of)"
  run_id rebuild
  [ "$status" -eq 0 ]
  [ "$output" = "ID=$version-mavericks.3
STATE=$(state_of)
PUBLISH=yes" ]
}

@test "rebuild over an empty channel yields -mavericks.1" {
  run_id rebuild
  [ "$status" -eq 0 ]
  [ "$output" = "ID=$version-mavericks.1
STATE=$(state_of)
PUBLISH=yes" ]
}

@test "builds of other Codex versions are ignored" {
  ship "0.160.0" 7 "$(state_of)"
  ship "9$version" 4 "$(state_of)"
  run_id auto
  [ "$status" -eq 0 ]
  [ "$output" = "ID=$version-mavericks.1
STATE=$(state_of)
PUBLISH=yes" ]
}

@test "STATE is the digest of the four pins, every patch in C glob order, then the tarball's layout script" {
  expected=$(cd "$PRODUCT_ROOT" && cat components/codex/version build/codex-revision components/rust/version \
    components/clang-22/version patches/*.patch packaging/build-codex-package.sh | shasum -a 256 | awk '{print $1}')
  run_id auto
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | sed -n 's/^STATE=//p')" = "$expected" ]
}

@test "changing only a patch changes STATE and publishes the next N" {
  ship "$version" 1 "$(state_of)"
  run_id auto
  [ "$(printf '%s\n' "$output" | sed -n 's/^PUBLISH=//p')" = "no" ]
  printf '\n# edited\n' >> "$product/patches/0004-user-verification-unsupported.patch"
  run_id auto
  [ "$status" -eq 0 ]
  [ "$output" = "ID=$version-mavericks.2
STATE=$(state_of)
PUBLISH=yes" ]
}

@test "changing only the tarball's layout script changes STATE and publishes the next N" {
  ship "$version" 1 "$(state_of)"
  printf '\n# edited\n' >> "$product/packaging/build-codex-package.sh"
  run_id auto
  [ "$status" -eq 0 ]
  [ "$output" = "ID=$version-mavericks.2
STATE=$(state_of)
PUBLISH=yes" ]
}

@test "an unknown mode is refused" {
  run_id publish
  [ "$status" -eq 2 ]
}

@test "a gh that fails stops the run with no ID" {
  unset CODEX_BUILDS_ASSET_LIST
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\nexit 1\n' > "$BATS_TEST_TMPDIR/bin/gh"
  chmod +x "$BATS_TEST_TMPDIR/bin/gh"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_id auto
  [ "$status" -ne 0 ]
  [[ "$output" != *"ID="* ]] || false
}

@test "a newest build JSON without mavergreen_state stops the run" {
  ship "$version" 1 "$(state_of)"
  printf '{"tag_name":"rust-v%s-mavericks.1"}\n' "$version" > "$CODEX_BUILDS_JSON_DIR/codex-build-$version-mavericks.1.json"
  run_id auto
  [ "$status" -ne 0 ]
  [[ "$output" != *"ID="* ]] || false
}

@test "a missing pin file stops the run and is named" {
  for pin in build/codex-revision components/rust/version components/clang-22/version packaging/build-codex-package.sh; do
    mv "$product/$pin" "$product/$pin.away"
    run_id auto
    [ "$status" -ne 0 ]
    [[ "$output" == *"$pin"* ]] || false
    [[ "$output" != *"ID="* ]] || false
    mv "$product/$pin.away" "$product/$pin"
  done
}

@test "no patches stops the run" {
  rm "$product"/patches/*.patch
  run_id auto
  [ "$status" -ne 0 ]
  [[ "$output" == *"patches"* ]] || false
}

@test "near-collision and unrelated assets are ignored" {
  printf '%s\n' "codex-build-0.161.01-mavericks.5.json" "codex-build-10.161.0-mavericks.5.json" \
    latest.json latest.json.sig "codex-package-x86_64-apple-darwin-$version-mavericks.5.tar.gz" > "$CODEX_BUILDS_ASSET_LIST"
  run_id auto
  [ "$status" -eq 0 ]
  [ "$output" = "ID=$version-mavericks.1
STATE=$(state_of)
PUBLISH=yes" ]
}

# fake_gh BODY: a gh on PATH whose script is BODY, with the test's file overrides removed
fake_gh() {
  unset CODEX_BUILDS_ASSET_LIST CODEX_BUILDS_JSON_DIR
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\n%s\n' "$1" > "$BATS_TEST_TMPDIR/bin/gh"
  chmod +x "$BATS_TEST_TMPDIR/bin/gh"
}

@test "a channel whose release does not exist yet is empty: -mavericks.1, published" {
  fake_gh 'echo "release not found" >&2; exit 1'
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_id auto
  [ "$status" -eq 0 ]
  [ "$output" = "ID=$version-mavericks.1
STATE=$(state_of)
PUBLISH=yes" ]
}

@test "any other failure to look up the release stops the run with no ID, and says why" {
  fake_gh 'echo "HTTP 502: Bad Gateway (https://api.github.com/graphql)" >&2; exit 1'
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_id auto
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot tell whether the codex-builds release"*"HTTP 502"* ]] || false
  [[ "$output" != *"ID="* ]] || false
}

@test "an existing release is listed through gh, and its newest build's state is compared" {
  fake_gh 'case "$*" in
  "release view codex-builds -R Mavergreen/codex-cli") echo "title: Codex builds" ;;
  *"releases/tags/codex-builds"*) echo 42 ;;
  *"releases/42/assets"*) echo "7 codex-build-'"$version"'-mavericks.2.json" ;;
  "api -H Accept: application/octet-stream repos/Mavergreen/codex-cli/releases/assets/7") echo "{\"mavergreen_state\":\"'"$(state_of)"'\"}" ;;
  *) exit 1 ;;
esac'
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_id auto
  [ "$status" -eq 0 ]
  [ "$output" = "ID=$version-mavericks.2
STATE=$(state_of)
PUBLISH=no" ]
}

@test "the newest build's JSON is fetched by its asset id from the paginated listing, never by name" {
  # the listing names three builds; only mavericks.10's asset id may be fetched, and gh's
  # name lookup (release download), which reads an asset list that may be capped, never runs
  fake_gh 'printf "%s\n" "$*" >> "$BATS_TEST_TMPDIR/gh-calls"
case "$*" in
  "release view codex-builds -R Mavergreen/codex-cli") echo "title: Codex builds" ;;
  *"releases/tags/codex-builds"*) echo 42 ;;
  "api --paginate repos/Mavergreen/codex-cli/releases/42/assets?per_page=100 -q .[] | \"\(.id) \(.name)\""*)
    printf "%s\n" "101 codex-build-'"$version"'-mavericks.9.json" "102 codex-build-'"$version"'-mavericks.10.json" \
      "103 codex-build-'"$version"'-mavericks.10.json.sig" "104 codex-build-'"$version"'-mavericks.2.json" ;;
  "api -H Accept: application/octet-stream repos/Mavergreen/codex-cli/releases/assets/102") echo "{\"mavergreen_state\":\"'"$(state_of)"'\"}" ;;
  *) exit 1 ;;
esac'
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_id auto
  [ "$status" -eq 0 ]
  [ "$output" = "ID=$version-mavericks.10
STATE=$(state_of)
PUBLISH=no" ]
  ! grep -q "release download" "$BATS_TEST_TMPDIR/gh-calls" || false
  grep -qx "api -H Accept: application/octet-stream repos/Mavergreen/codex-cli/releases/assets/102" "$BATS_TEST_TMPDIR/gh-calls"
}

@test "a failed fetch of the newest build's JSON stops the run with no ID" {
  fake_gh 'case "$*" in
  "release view codex-builds -R Mavergreen/codex-cli") echo "title: Codex builds" ;;
  *"releases/tags/codex-builds"*) echo 42 ;;
  *"releases/42/assets"*) echo "7 codex-build-'"$version"'-mavericks.2.json" ;;
  *) echo "HTTP 502" >&2; exit 1 ;;
esac'
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_id auto
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot download codex-build-$version-mavericks.2.json (asset 7)"* ]] || false
  [[ "$output" != *"ID="* ]] || false
}
