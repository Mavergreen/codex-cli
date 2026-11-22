#!/bin/sh
# platform: host-agnostic -- plain sh over the repo's own files
# spec: shipyard scripts/objc-compat.sh header -- --link-map, the map the evidence names, and each --object-dir
#       let the analyzer attest which bytes of __text are relocations, so data in code is not read as a reference.
#   usage: sh tests/objc-sweep-test.sh
set -eu
. "$(dirname "$0")/lib/harness.sh"
h_setup
E=$(cat "$H_REPO/build/objc-build-evidence.sh")
h_assert_contains "$E" 'DEPS="$BUILD_ROOT/codex-$MODE-target/x86_64-apple-darwin/release/deps"' "the objects are the ones build-codex.sh linked"
h_assert_contains "$E" '--provider-prefix "$PREFIX" --link-map "$MAP" --object-dir "$DEPS"' "codex's strict pass gets the map its evidence names and its objects"
G=$(cat "$H_REPO/build/compat-guard.sh")
h_assert_contains "$G" 'LINKMAP="$BUILD_ROOT/objc-$MODE/linkmaps/codex.map"' "the gate gives codex the map its proof names"
h_assert_contains "$G" 'OBJDIRS="$BUILD_ROOT/codex-$MODE-target/x86_64-apple-darwin/release/deps"' "and the objects it was linked from"
h_assert_contains "$G" '"MAVERGREEN_OBJC_LINK_MAP=$LINKMAP"' "as shipyard's guard takes them"
h_done
