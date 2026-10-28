#!/bin/sh
# platform: host-agnostic -- plain sh and shipyard's fetch; needs the network, as the pin's source does
#   Holds components/codex/features to the feature table of the Codex commit components/codex/version
#   pins, fetched from GitHub. A Codex update fails here until each feature it makes reachable has a
#   verdict, and each feature it drops has lost its line.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
MAVERICKS_BUILD_DIR=$ROOT/build
export MAVERICKS_BUILD_DIR
. "$ROOT/build/lib.sh"
. "$SHIPYARD_SCRIPTS/mavericks_fetch.sh"

work=$(mktemp -d "${TMPDIR:-/tmp}/upstream-features-test.XXXXXX")
trap 'rm -rf "$work"' EXIT
revision=$(sh "$ROOT/build/codex-pin.sh" revision)
shipyard_curl "https://raw.githubusercontent.com/openai/codex/$revision/codex-rs/features/src/lib.rs" "$work/lib.rs"
sh "$ROOT/build/check-upstream-features.sh" "$work/lib.rs"
