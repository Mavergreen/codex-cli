#!/bin/sh
# platform: host-agnostic -- plain sh and git; runs on ultimate-hat and modern macOS
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MAVERICKS_BUILD_DIR=$HERE
export MAVERICKS_BUILD_DIR
. "$HERE/lib.sh"

CODEX_VERSION=$(tr -d '[:space:]' < "$MAVERICKS_ROOT/components/codex/version")
REVISION=$(tr -d '[:space:]' < "$HERE/codex-revision")
BUILD_ROOT=$(mavericks_build_root)
DEST="$BUILD_ROOT/codex-src"

case "$REVISION" in
  ''|*[!0-9a-f]*) echo "fetch-codex: invalid codex-revision" >&2; exit 2 ;;
esac
[ "${#REVISION}" -eq 40 ] || { echo "fetch-codex: codex-revision must be a full commit SHA" >&2; exit 2; }

CODEX_REPOSITORY=${CODEX_REPOSITORY:-https://github.com/openai/codex.git}
sh "$SHIPYARD_SCRIPTS/clone_pinned.sh" \
  "$CODEX_REPOSITORY" "rust-v$CODEX_VERSION" "$REVISION" "$DEST"
[ "$(git -C "$DEST" rev-parse HEAD)" = "$REVISION" ] || {
  echo "fetch-codex: checkout does not match build/codex-revision" >&2; exit 1;
}

# spec: tests/build-inputs.bats "fetch reuses its own prepared checkout without touching it" -- a
#       rebuild must keep the source mtimes Cargo's fingerprints depend on, so a prepared checkout
#       is reused only while it is exactly what this script last left there. The stamp lives under
#       .git/, out of the worktree, and names every input to the preparation and the resulting
#       tree state, ignored files included.
STAMP="$DEST/.git/mavergreen-prepared"
KEEP=
inputs_id() {
  cat "$MAVERICKS_ROOT/patches"/*.patch "$HERE/fetch-codex.sh" "$MAVERICKS_ROOT/components/codex/version" \
    "$HERE/codex-revision" | shasum -a 256 | awk '{ print $1 }'
}
tree_status() { git -C "$DEST" status --porcelain --ignored --untracked-files=all; }
tree_id() { { tree_status; git -C "$DEST" diff HEAD; } | shasum -a 256 | awk '{ print $1 }'; }
if [ -n "$(tree_status)" ]; then
  if [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$(inputs_id) $(tree_id)" ]; then
    printf '%s\n' "$DEST"; exit 0
  fi
  echo "fetch-codex: discarding a stale prepared checkout in $DEST" >&2
  # spec: tests/build-inputs.bats "re-preparing keeps the mtime of a file it prepares the same" --
  #       Cargo rebuilds a crate when one of its sources is newer than its last build, so a file the
  #       new preparation leaves as it was keeps its old mtime. Without this, editing one patch
  #       rebuilds every patched crate and everything above them.
  KEEP="$BUILD_ROOT/codex-src-kept"
  rm -rf "$KEEP"
  mkdir -p "$KEEP"
  { git -C "$DEST" diff --name-only; git -C "$DEST" ls-files --others --exclude-standard; } |
    while IFS= read -r path; do
      mkdir -p "$KEEP/$(dirname "$path")"
      cp -p "$DEST/$path" "$KEEP/$path"
    done
  git -C "$DEST" checkout -q -- .
  git -C "$DEST" clean -q -f -d -x
fi
rm -f "$STAMP"

mavericks_apply_patches "$DEST" "$MAVERICKS_ROOT/patches"

# platform: the rust-v tag sets [workspace.package] version, but its Cargo.lock still records 0.0.0
#           for every workspace member, so `cargo build --locked` refuses the tree as shipped. Only
#           the lock's path packages (no `source`) at 0.0.0 get the workspace version; --locked
#           still rejects any other difference between the lock and the manifests.
LOCK="$DEST/codex-rs/Cargo.lock"
WORKSPACE_VERSION=$(awk '
  /^\[workspace\.package\]$/ { want = 1; next }
  /^\[/ { want = 0 }
  want && /^version = "/ { gsub(/^version = "|"$/, ""); print; exit }
' "$DEST/codex-rs/Cargo.toml")
[ "$WORKSPACE_VERSION" = "$CODEX_VERSION" ] || {
  echo "fetch-codex: codex-rs/Cargo.toml workspace version '$WORKSPACE_VERSION' is not $CODEX_VERSION" >&2
  exit 1
}
REWRITTEN=$(awk -v v="$WORKSPACE_VERSION" -v out="$LOCK.tmp" '
  function flush(   i) {
    for (i = 1; i <= n; i++) {
      if (!sourced && block[i] == "version = \"0.0.0\"") { block[i] = "version = \"" v "\""; count++ }
      print block[i] > out
    }
    n = 0; sourced = 0
  }
  /^\[\[package\]\]$/ { flush() }
  { block[++n] = $0 }
  /^source = "/ { sourced = 1 }
  END { flush(); print count + 0 }
' "$LOCK")
[ "$REWRITTEN" -gt 0 ] || {
  rm -f "$LOCK.tmp"
  echo "fetch-codex: Cargo.lock has no path package at 0.0.0 -- upstream changed its lock; recheck this step" >&2
  exit 1
}
mv "$LOCK.tmp" "$LOCK"

git -C "$DEST" diff --check
if [ -n "${KEEP:-}" ]; then
  (cd "$KEEP" && find . -type f) | while IFS= read -r path; do
    if [ -f "$DEST/$path" ] && cmp -s "$KEEP/$path" "$DEST/$path"; then
      touch -r "$KEEP/$path" "$DEST/$path"
    fi
  done
  rm -rf "$KEEP"
fi
printf '%s %s\n' "$(inputs_id)" "$(tree_id)" > "$STAMP"
printf '%s\n' "$DEST"
