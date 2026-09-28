#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MAVERICKS_BUILD_DIR=$HERE
export MAVERICKS_BUILD_DIR
. "$HERE/lib.sh"

UPSTREAM_VERSION=$(tr -d '[:space:]' < "$MAVERICKS_ROOT/UPSTREAM_VERSION")
REVISION=$(tr -d '[:space:]' < "$HERE/codex-revision")
BUILD_ROOT=$(mavericks_build_root)
DEST="$BUILD_ROOT/codex-src"

case "$REVISION" in
  ''|*[!0-9a-f]*) echo "fetch-codex: invalid codex-revision" >&2; exit 2 ;;
esac
[ "${#REVISION}" -eq 40 ] || { echo "fetch-codex: codex-revision must be a full commit SHA" >&2; exit 2; }

CODEX_REPOSITORY=${CODEX_REPOSITORY:-https://github.com/openai/codex.git}
sh "$SHIPYARD_SCRIPTS/clone_pinned.sh" \
  "$CODEX_REPOSITORY" "rust-v$UPSTREAM_VERSION" "$REVISION" "$DEST"
[ "$(git -C "$DEST" rev-parse HEAD)" = "$REVISION" ] || {
  echo "fetch-codex: checkout does not match build/codex-revision" >&2; exit 1;
}
[ -z "$(git -C "$DEST" status --porcelain)" ] || {
  echo "fetch-codex: pinned source checkout is dirty before patch application" >&2; exit 1;
}

mavericks_apply_patches "$DEST" "$MAVERICKS_ROOT/patches"

git -C "$DEST" diff --check
printf '%s\n' "$DEST"
