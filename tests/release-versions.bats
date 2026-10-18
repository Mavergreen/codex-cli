#!/usr/bin/env bats
# platform: host-agnostic -- fixtures and plain sh; runs on ultimate-hat and modern macOS

# The release workflow's version axes (<upstream>-mavericks.N) and its upstream-pin guard. Version
# resolution runs shipyard's version.sh through build/version.sh with a scratch UPSTREAM_VERSION and
# the shipped tags in MAVERICKS_TAGS; the pin guard runs against a scratch product and a local
# repository standing in for openai/codex.
setup() {
  export PRODUCT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export SHIPYARD_SCRIPTS="${SHIPYARD_SCRIPTS:-/home/schmonz/Documents/trees/mavergreen-shipyard/scripts}"
  export MAVERICKS_UPSTREAM_FILE="$BATS_TEST_TMPDIR/UPSTREAM_VERSION"
  export MAVERICKS_TAGS=""
  product="$BATS_TEST_TMPDIR/product"
  mkdir -p "$product/build"
  cp "$PRODUCT_ROOT"/build/*.sh "$product/build/"
}

# resolve MODE UPSTREAM TAGS: version.sh's three lines for a scratch UPSTREAM_VERSION and shipped tags
resolve() {
  printf '%s\n' "$2" > "$MAVERICKS_UPSTREAM_FILE"
  MAVERICKS_TAGS="$3" sh "$PRODUCT_ROOT/build/version.sh" "$1"
}

@test "a new upstream version releases as -mavericks.1" {
  run resolve auto 0.162.0 "0.161.0-mavericks.1
0.161.0-mavericks.2"
  [ "$status" -eq 0 ]
  [ "$output" = "FULL=0.162.0-mavericks.1
TAG=0.162.0-mavericks.1
RELEASE=yes" ]
}

@test "the shipped upstream version is not released again by a plain push" {
  run resolve auto 0.161.0 "0.161.0-mavericks.1"
  [ "$status" -eq 0 ]
  [ "$output" = "FULL=0.161.0-mavericks.1
TAG=0.161.0-mavericks.1
RELEASE=no" ]
}

@test "a packaging-only release of the same upstream takes the next .N past the highest shipped" {
  run resolve local 0.161.0 "0.161.0-mavericks.1
0.161.0-mavericks.3
0.160.0-mavericks.9"
  [ "$status" -eq 0 ]
  [ "$output" = "FULL=0.161.0-mavericks.4
TAG=0.161.0-mavericks.4
RELEASE=yes" ]
}

@test "UPSTREAM_VERSION is the package's own date" {
  grep -Eq '^[0-9]{8}$' "$PRODUCT_ROOT/UPSTREAM_VERSION"
}

@test "a mode other than auto or local is refused" {
  run resolve nightly 0.161.0 ""
  [ "$status" -ne 0 ]
}

# pin_check VERSION REVISION [ARGS]: check-upstream-pin.sh on a scratch product pinning them
pin_check() {
  mkdir -p "$product/components/codex"
  printf '%s\n' "$1" > "$product/components/codex/version"
  printf '%s\n' "$2" > "$product/build/codex-revision"
  shift 2
  sh "$product/build/check-upstream-pin.sh" "$@"
}

@test "a Codex prerelease tag is refused before it can be packaged" {
  run pin_check 0.162.0-alpha.1 979011409de0a60b52f179721948e65531d26144
  [ "$status" -eq 1 ]
  [[ "$output" == *"components/codex/version '0.162.0-alpha.1' is not a stable x.y.z"* ]] || false
}

@test "malformed upstream versions and revisions are refused" {
  run pin_check v0.161.0 979011409de0a60b52f179721948e65531d26144
  [ "$status" -eq 1 ]
  run pin_check 0.161 979011409de0a60b52f179721948e65531d26144
  [ "$status" -eq 1 ]
  run pin_check 0.161.0 97901140
  [ "$status" -eq 1 ]
  [[ "$output" == *"full 40-digit commit SHA"* ]] || false
  run pin_check 0.161.0 97901140ZZ9e23c70
  [ "$status" -eq 1 ]
}

@test "the committed pin passes the offline checks" {
  run sh "$PRODUCT_ROOT/build/check-upstream-pin.sh"
  [ "$status" -eq 0 ]
}

# upstream: a local repository with a lightweight tag rust-v0.161.0 and an annotated one rust-v0.162.0
make_upstream() {
  upstream="$BATS_TEST_TMPDIR/upstream"
  git init -q "$upstream"
  git -C "$upstream" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m one
  rev_one=$(git -C "$upstream" rev-parse HEAD)
  git -C "$upstream" tag rust-v0.161.0
  git -C "$upstream" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m two
  rev_two=$(git -C "$upstream" rev-parse HEAD)
  git -C "$upstream" -c user.name=t -c user.email=t@example.com tag -a -m two rust-v0.162.0
  export CODEX_REPOSITORY="$upstream"
}

@test "--remote accepts a revision that is the tag's commit, lightweight or annotated" {
  make_upstream
  run pin_check 0.161.0 "$rev_one" --remote
  [ "$status" -eq 0 ]
  run pin_check 0.162.0 "$rev_two" --remote
  [ "$status" -eq 0 ]
}

@test "a components/codex/version bump alone fails early, naming build/codex-revision and the commit to use" {
  make_upstream
  run pin_check 0.162.0 "$rev_one" --remote
  [ "$status" -eq 1 ]
  [[ "$output" == *"components/codex/version is 0.162.0 but build/codex-revision is $rev_one; rust-v0.162.0 is commit $rev_two"* ]] || false
  [[ "$output" == *"Update build/codex-revision to $rev_two"* ]] || false
}

@test "--remote refuses a version whose rust-v tag does not exist" {
  make_upstream
  run pin_check 0.163.0 "$rev_one" --remote
  [ "$status" -eq 1 ]
  [[ "$output" == *"has no tag rust-v0.163.0"* ]] || false
}
