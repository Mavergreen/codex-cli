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
h_done
