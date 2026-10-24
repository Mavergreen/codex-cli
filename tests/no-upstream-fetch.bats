#!/usr/bin/env bats
# platform: host-agnostic -- runs build/fetch-codex.sh (git and shipyard's scripts) and grep; runs on ultimate-hat and modern macOS

setup() {
  export MAVERGREEN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export MAVERICKS_ROOT="$MAVERGREEN_ROOT"
  export SHIPYARD_SCRIPTS="${SHIPYARD_SCRIPTS:-/home/schmonz/Documents/trees/mavergreen-shipyard/scripts}"
  export MAVERICKS_TAGS=""
  export MAVERICKS_BUILD_ROOT="$BATS_TEST_TMPDIR/local-build"
}

# source_to_scan: sets SRC to the prepared Codex source to scan.
# CODEX_PREPARED_SRC names a tree build/fetch-codex.sh already prepared (CI's cross build sets it);
# with it set the guard scans that tree and fails, never skips, when it is not the pinned source.
# Otherwise the guard prepares its own tree from the gitignored codex/ inspection checkout, and skips
# where that is missing, exactly where tests/build-inputs.bats's fetch tests skip.
source_to_scan() {
  revision=$(sh "$MAVERGREEN_ROOT/build/codex-pin.sh" revision)
  if [ -n "${CODEX_PREPARED_SRC:-}" ]; then
    [ -d "$CODEX_PREPARED_SRC/codex-rs" ] || {
      echo "CODEX_PREPARED_SRC=$CODEX_PREPARED_SRC holds no codex-rs/" >&2
      return 1
    }
    head=$(git -C "$CODEX_PREPARED_SRC" rev-parse HEAD) || return 1
    [ "$head" = "$revision" ] || {
      echo "CODEX_PREPARED_SRC=$CODEX_PREPARED_SRC is at $head, not the pinned $revision" >&2
      return 1
    }
    SRC=$CODEX_PREPARED_SRC
    return 0
  fi
  git -C "$MAVERGREEN_ROOT/codex" cat-file -e "$revision^{commit}" 2>/dev/null ||
    skip "codex/ is not a git checkout holding the pinned revision $revision, and CODEX_PREPARED_SRC is unset"
  CODEX_REPOSITORY="file://$MAVERGREEN_ROOT/codex" sh "$MAVERGREEN_ROOT/build/fetch-codex.sh" >/dev/null || return 1
  SRC=$MAVERICKS_BUILD_ROOT/codex-src
}

# The desktop-app installer is out of scope: it never runs on a Mac that can build this port.
@test "no shipped source fetches or runs an OpenAI Codex build" {
  source_to_scan
  run grep -rn \
    --exclude='*_tests.rs' \
    --exclude='*.md' \
    --exclude-dir=tests \
    --exclude-dir=desktop_app \
    -e 'chatgpt.com/codex/install' \
    -e 'api.github.com/repos/openai/codex/releases' \
    -e 'releases.openai.com' \
    -e 'formulae.brew.sh' \
    "$SRC/codex-rs"
  [ "$status" -eq 1 ] || { printf 'upstream fetches remain:\n%s\n' "$output"; return 1; }
}

@test "a CODEX_PREPARED_SRC that is not the pinned source fails the guard rather than skipping it" {
  CODEX_PREPARED_SRC="$BATS_TEST_TMPDIR/absent" run source_to_scan
  [ "$status" -ne 0 ]
  [[ "$output" == *"holds no codex-rs/"* ]] || false
  mkdir -p "$BATS_TEST_TMPDIR/not a checkout/codex-rs"
  CODEX_PREPARED_SRC="$BATS_TEST_TMPDIR/not a checkout" run source_to_scan
  [ "$status" -ne 0 ]
  [[ "$output" != *"skip"* ]] || false
}
