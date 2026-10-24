#!/usr/bin/env bats
# platform: host-agnostic -- fixtures and plain sh; runs on ultimate-hat and modern macOS

# The pins the two release streams version from: UPSTREAM_VERSION, the package's own date, and the
# Codex pin guard, which runs against a scratch product and a local repository standing in for
# openai/codex.
setup() {
  export PRODUCT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  product="$BATS_TEST_TMPDIR/product"
  mkdir -p "$product/build"
  cp "$PRODUCT_ROOT"/build/*.sh "$product/build/"
}

@test "UPSTREAM_VERSION is the package's own date" {
  grep -Eq '^[0-9]{8}$' "$PRODUCT_ROOT/UPSTREAM_VERSION"
}

# pin_check TAG REVISION [ARGS]: check-upstream-pin.sh on a scratch product pinning them
pin_check() {
  mkdir -p "$product/components/codex"
  printf 'REPO=https://github.com/openai/codex.git\nREF=%s\nDIGEST=%s\n' "$1" "$2" \
    > "$product/components/codex/version"
  shift 2
  sh "$product/build/check-upstream-pin.sh" "$@"
}

@test "the Codex pin is the family's REPO, REF and DIGEST in one file" {
  [ "$(sh "$PRODUCT_ROOT/build/codex-pin.sh" repository)" = https://github.com/openai/codex.git ]
  [[ "$(sh "$PRODUCT_ROOT/build/codex-pin.sh" tag)" == rust-v*.*.* ]] || false
  [ "$(sh "$PRODUCT_ROOT/build/codex-pin.sh" tag)" = "rust-v$(sh "$PRODUCT_ROOT/build/codex-pin.sh" version)" ]
  sh "$PRODUCT_ROOT/build/codex-pin.sh" revision | grep -Eqx '[0-9a-f]{40}'
  [ ! -e "$PRODUCT_ROOT/build/codex-revision" ]
}

@test "the Codex pin's fields, and a usage error for any other" {
  run pin_check rust-v0.161.0 979011409de0a60b52f179721948e65531d26144
  [ "$status" -eq 0 ]
  [ "$(sh "$product/build/codex-pin.sh" version)" = 0.161.0 ]
  [ "$(sh "$product/build/codex-pin.sh" tag)" = rust-v0.161.0 ]
  [ "$(sh "$product/build/codex-pin.sh" revision)" = 979011409de0a60b52f179721948e65531d26144 ]
  run sh "$product/build/codex-pin.sh" commit
  [ "$status" -eq 2 ]
}

@test "a Codex pin missing a field, or carrying one twice, is refused" {
  mkdir -p "$product/components/codex"
  printf 'REPO=https://github.com/openai/codex.git\nREF=rust-v0.161.0\n' > "$product/components/codex/version"
  run sh "$product/build/codex-pin.sh" version
  [ "$status" -eq 1 ]
  [[ "$output" == *"exactly one DIGEST= line"* ]] || false
  printf 'REPO=x\nREF=rust-v0.161.0\nREF=rust-v0.162.0\nDIGEST=979011409de0a60b52f179721948e65531d26144\n' \
    > "$product/components/codex/version"
  run sh "$product/build/codex-pin.sh" version
  [ "$status" -eq 1 ]
  [[ "$output" == *"exactly one REF= line"* ]] || false
}

@test "a Codex prerelease tag is refused before it can be packaged" {
  run pin_check rust-v0.162.0-alpha.1 979011409de0a60b52f179721948e65531d26144
  [ "$status" -eq 1 ]
  [[ "$output" == *"REF 'rust-v0.162.0-alpha.1' is not a stable rust-v<x.y.z>"* ]] || false
}

@test "malformed tags and revisions are refused" {
  run pin_check 0.161.0 979011409de0a60b52f179721948e65531d26144
  [ "$status" -eq 1 ]
  run pin_check rust-v0.161 979011409de0a60b52f179721948e65531d26144
  [ "$status" -eq 1 ]
  run pin_check rust-v0.161.0 97901140
  [ "$status" -eq 1 ]
  [[ "$output" == *"full 40-digit commit SHA"* ]] || false
  run pin_check rust-v0.161.0 97901140ZZ9e23c70
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
  run pin_check rust-v0.161.0 "$rev_one" --remote
  [ "$status" -eq 0 ]
  run pin_check rust-v0.162.0 "$rev_two" --remote
  [ "$status" -eq 0 ]
}

@test "--remote refuses a DIGEST that is not the tag's commit, naming the commit" {
  make_upstream
  run pin_check rust-v0.162.0 "$rev_one" --remote
  [ "$status" -eq 1 ]
  [[ "$output" == *"components/codex/version pins rust-v0.162.0 at $rev_one, but rust-v0.162.0 is commit $rev_two"* ]] || false
}

@test "--remote refuses a tag that does not exist" {
  make_upstream
  run pin_check rust-v0.163.0 "$rev_one" --remote
  [ "$status" -eq 1 ]
  [[ "$output" == *"has no tag rust-v0.163.0"* ]] || false
}
