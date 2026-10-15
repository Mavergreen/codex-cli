#!/bin/sh
# platform: host-agnostic
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
MAVERICKS_ROOT="$(cd "$HERE/.." && pwd)"
. "$HERE/helpers/assert.sh"

a_eq "https://github.com/openai/codex/releases/tag/rust-v0.161.0" "$(sh "$MAVERICKS_ROOT/build/upstream-release-notes-url.sh" 0.161.0)" "the notes URL is upstream's rust-v tag page"
a_fails "no version is a usage error" sh "$MAVERICKS_ROOT/build/upstream-release-notes-url.sh"
a_done
