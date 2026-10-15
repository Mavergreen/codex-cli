#!/bin/sh
# platform: host-agnostic
#   usage: version.sh [auto|local]
#          Prints FULL=, TAG= and RELEASE= as shipyard's version.sh derives them from UPSTREAM_VERSION and
#          the shipped -mavericks.N tags. It ignores VERSION: the release workflow resolves the real
#          version (including `local`) and writes it to VERSION, and build-codex.sh reads that file first.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
MAVERICKS_ROOT="$(cd "$SELF/.." && pwd)"; export MAVERICKS_ROOT
. "$SELF/msc.sh"
exec sh "$SHIPYARD/version.sh" "$@"
