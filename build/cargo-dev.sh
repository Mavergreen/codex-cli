#!/bin/sh
# platform: macOS-only -- runs cargo in the prepared Codex source with the release build's environment
# usage: cargo-dev.sh CARGO-ARGS...   (for example: cargo-dev.sh test -p codex-install-context)
# Debug artifacts go to codex-dev-target, apart from build-codex.sh's release targets. It neither
# fetches nor patches: run fetch-codex.sh first, and note that a changed patch series re-prepares the source.
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MAVERICKS_BUILD_DIR=$HERE
export MAVERICKS_BUILD_DIR
. "$HERE/lib.sh"
. "$HERE/codex-build-env.sh"

MODE=$(sh "$SHIPYARD_SCRIPTS/mavericks_mode.sh")
codex_check_host "$MODE"
BUILD_ROOT=$(mavericks_build_root)
SOURCE="$BUILD_ROOT/codex-src"
[ -d "$SOURCE/codex-rs" ] || { echo "cargo-dev: no $SOURCE; run build/fetch-codex.sh first" >&2; exit 1; }
codex_build_env "$MODE" "$SOURCE" "$BUILD_ROOT/codex-dev-target"
codex_cargo "$@"
