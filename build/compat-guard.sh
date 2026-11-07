#!/bin/sh
# platform: macOS-only -- shipyard's guard reads Mach-O with lipo/otool/nm and builds its analyzer against the host SDK
#   usage: compat-guard.sh BINARY
#          The 10.9 compatibility gate for one Codex binary: shipyard's assert_binary_compatible.sh,
#          whose Objective-C half is the strict analyzer (scripts/objc-compat.sh). For BINARY in
#          BUILD_ROOT/codex-MODE, build/objc-build-evidence.sh --check MODE must first show that the
#          build's proof still describes these bytes; codex then gets that build evidence and the
#          provider it linked, and the code-mode host is measured on its bytes alone. Elsewhere,
#          CODEX_OBJC_BUILD_EVIDENCE and CODEX_OBJC_PROVIDER_PREFIX name them (tests/objc-gate-test.sh
#          gives the original 0.165.0 binary shipyard's recorded evidence). CODEX_OBJC_REPORT_DIR keeps
#          the report. Exit as assert_binary_compatible.sh: 0 clean, 1 a check failed (here also: the
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
case "$BIN" in
  "$BUILD_ROOT"/codex-native/*|"$BUILD_ROOT"/codex-cross/*)
    MODE=${BIN#"$BUILD_ROOT"/codex-}; MODE=${MODE%%/*}
    [ -z "$EVIDENCE$PREFIX" ] || { echo "compat-guard: a build's own proof is used for $BIN, not an override" >&2; exit 2; }
    sh "$HERE/objc-build-evidence.sh" --check "$MODE" || {
      echo "compat-guard: no current Objective-C proof for $BIN: run build/objc-build-evidence.sh $MODE" >&2; exit 1; }
    if [ "$(basename "$BIN")" = codex ]; then
      EVIDENCE="$BUILD_ROOT/objc-$MODE/evidence/codex.json"
      PREFIX=$(sh "$HERE/fetch-recaulk-objc.sh" | sed -n 1p)
    fi ;;
esac
set -- env "MAVERICKS_DEVIATIONS_ROOT=$MAVERICKS_ROOT" MAVERICKS_ALLOW_ARCHS=x86_64 "MAVERICKS_OBJC_ROOT=$(dirname "$BIN")"
[ -z "$EVIDENCE" ] || set -- "$@" "MAVERICKS_OBJC_BUILD_EVIDENCE=$EVIDENCE"
[ -z "$PREFIX" ] || set -- "$@" "MAVERICKS_OBJC_PROVIDER_PREFIX=$PREFIX"
# the provider body's source receipt, which Recaulk ships beside its declaration
[ -z "$PREFIX" ] || [ ! -f "$PREFIX/share/recaulk/objc-source.receipt" ] ||
  set -- "$@" "MAVERICKS_OBJC_SOURCE_RECEIPT=$PREFIX/share/recaulk/objc-source.receipt"
[ -z "${CODEX_OBJC_REPORT_DIR:-}" ] || set -- "$@" "MAVERICKS_OBJC_REPORT_DIR=$CODEX_OBJC_REPORT_DIR"
exec "$@" sh "$SHIPYARD_SCRIPTS/assert_binary_compatible.sh" "$BIN"
