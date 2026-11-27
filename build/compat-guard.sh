#!/bin/sh
# platform: host-agnostic -- shipyard's guard reads Mach-O with $LIPO/$OTOOL/$NM (llvm tools on Linux) and runs Drydock's drydock-objc analyzer from the pinned release
#   usage: compat-guard.sh BINARY
#          The 10.9 compatibility gate for one Codex binary: shipyard's assert_binary_compatible.sh,
#          whose Objective-C half is the strict analyzer (scripts/objc-compat.sh). For BINARY in
#          BUILD_ROOT/codex-MODE, build/objc-build-evidence.sh --check MODE must first show that the
#          build's proof still describes these bytes; codex then gets that build evidence and the
#          provider it linked, and the code-mode host its own build evidence. Elsewhere,
#          CODEX_OBJC_BUILD_EVIDENCE and CODEX_OBJC_PROVIDER_PREFIX name them (tests/objc-gate-test.sh
#          gives the original 0.165.0 binary Codex's own copy, tests/fixtures/codex-0.165.0-build-evidence.json). A build's
#          own proof is schema 2, so the analyzer also gets the prepared tree, the crate sources its
#          build-manifest names and shipyard's pinned SDK, to hash the files reviewed rows cite; elsewhere
#          CODEX_OBJC_SOURCE_ROOT, CODEX_OBJC_CRATE_SOURCES and CODEX_OBJC_SDK_ROOT name them, when set. codex also gets
#          the link map its proof names and the objects it was linked from, so the analyzer can attest which
#          bytes are relocations; elsewhere CODEX_OBJC_LINK_MAP and CODEX_OBJC_OBJECT_DIRS (DIR[:DIR...]) name them.
#          CODEX_OBJC_REPORT_DIR keeps the report. Exit as assert_binary_compatible.sh: 0 clean, 1 a check failed (here also: the
#          proof is stale), 2 misuse, 4 cannot measure.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MAVERICKS_BUILD_DIR=$HERE
export MAVERICKS_BUILD_DIR
. "$HERE/lib.sh"
[ $# -eq 1 ] && [ -f "$1" ] || { echo "usage: compat-guard.sh BINARY" >&2; exit 2; }
BIN=$(CDPATH= cd -- "$(dirname -- "$1")" && pwd -P)/$(basename -- "$1")
BUILD_ROOT=$(CDPATH= cd -- "$(mavericks_build_root)" && pwd -P)
EVIDENCE=${CODEX_OBJC_BUILD_EVIDENCE:-}
PREFIX=${CODEX_OBJC_PROVIDER_PREFIX:-}
SRCROOT=${CODEX_OBJC_SOURCE_ROOT:-}
CRATES=${CODEX_OBJC_CRATE_SOURCES:-}
OBJC_SDK=${CODEX_OBJC_SDK_ROOT:-}
LINKMAP=${CODEX_OBJC_LINK_MAP:-}
OBJDIRS=${CODEX_OBJC_OBJECT_DIRS:-}
case "$BIN" in
  "$BUILD_ROOT"/codex-native/*|"$BUILD_ROOT"/codex-cross/*)
    MODE=${BIN#"$BUILD_ROOT"/codex-}; MODE=${MODE%%/*}
    [ -z "$EVIDENCE$PREFIX$SRCROOT$CRATES$OBJC_SDK$LINKMAP$OBJDIRS" ] || { echo "compat-guard: a build's own proof is used for $BIN, not an override" >&2; exit 2; }
    sh "$HERE/objc-build-evidence.sh" --check "$MODE" || {
      echo "compat-guard: no current Objective-C proof for $BIN: run build/objc-build-evidence.sh $MODE" >&2; exit 1; }
    if [ "$(basename "$BIN")" = codex ]; then
      EVIDENCE="$BUILD_ROOT/objc-$MODE/evidence/codex.json"
      PREFIX=$(sh "$HERE/fetch-recaulk-objc.sh" | sed -n 1p)
      # spec: build/objc-build-evidence.sh -- the map its proof names, and the objects codex was linked from
      LINKMAP="$BUILD_ROOT/objc-$MODE/linkmaps/codex.map"
      OBJDIRS="$BUILD_ROOT/codex-$MODE-target/x86_64-apple-darwin/release/deps"
    else
      EVIDENCE="$BUILD_ROOT/objc-$MODE/evidence/$(basename "$BIN").json"
    fi
    # spec: build/objc-build-evidence.sh header -- the roots its proof was measured with
    SRCROOT="$BUILD_ROOT/codex-src"
    CRATES=$(sed -n 's/^crate_sources=//p' "$BUILD_ROOT/codex-$MODE/build-manifest")
    OBJC_SDK=$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" --arch x86_64) || { echo "compat-guard: no pinned 10.9 SDK from shipyard" >&2; exit 4; } ;;
esac
# spec: shipyard scripts/assert_binary_compatible.sh header -- the strict analyzer is opt-in there; Codex opts in.
set -- env MAVERGREEN_OBJC_STRICT=1 "MAVERICKS_DEVIATIONS_ROOT=$MAVERICKS_ROOT" MAVERICKS_ALLOW_ARCHS=x86_64 "MAVERGREEN_OBJC_ROOT=$(dirname "$BIN")"
[ -z "$EVIDENCE" ] || set -- "$@" "MAVERGREEN_OBJC_BUILD_EVIDENCE=$EVIDENCE"
[ -z "$PREFIX" ] || set -- "$@" "MAVERGREEN_OBJC_PROVIDER_PREFIX=$PREFIX"
[ -z "$SRCROOT" ] || set -- "$@" "MAVERGREEN_OBJC_SOURCE_ROOT=$SRCROOT"
[ -z "$CRATES" ] || set -- "$@" "MAVERGREEN_OBJC_CRATE_SOURCES=$CRATES"
[ -z "$OBJC_SDK" ] || set -- "$@" "MAVERGREEN_OBJC_SDK_ROOT=$OBJC_SDK"
[ -z "$LINKMAP" ] || set -- "$@" "MAVERGREEN_OBJC_LINK_MAP=$LINKMAP"
[ -z "$OBJDIRS" ] || set -- "$@" "MAVERGREEN_OBJC_OBJECT_DIRS=$OBJDIRS"
# the provider body's source receipt, which Recaulk ships beside its declaration
[ -z "$PREFIX" ] || [ ! -f "$PREFIX/share/recaulk/objc-source.receipt" ] ||
  set -- "$@" "MAVERGREEN_OBJC_SOURCE_RECEIPT=$PREFIX/share/recaulk/objc-source.receipt"
[ -z "${CODEX_OBJC_REPORT_DIR:-}" ] || set -- "$@" "MAVERGREEN_OBJC_REPORT_DIR=$CODEX_OBJC_REPORT_DIR"
exec "$@" sh "$SHIPYARD_SCRIPTS/assert_binary_compatible.sh" "$BIN"
