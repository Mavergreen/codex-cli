#!/bin/sh
# platform: host-agnostic
#   usage: SHIPYARD_SCRIPTS=... objc-references.sh
#          Prints the Objective-C reference set shipyard's analyzer measures against. A newer shipyard says
#          where it is (scripts/objc-reference-dir.sh); v1.0.727 and older keep it beside scripts/ as
#          reference/objc. Exit 1 when neither answers.
set -eu
: "${SHIPYARD_SCRIPTS:?set SHIPYARD_SCRIPTS}"
if [ -f "$SHIPYARD_SCRIPTS/objc-reference-dir.sh" ]; then
  exec sh "$SHIPYARD_SCRIPTS/objc-reference-dir.sh"
fi
CDPATH= cd -- "$SHIPYARD_SCRIPTS/../reference/objc" 2>/dev/null && pwd || {
  echo "objc-references: shipyard at $SHIPYARD_SCRIPTS has no objc-reference-dir.sh and no reference/objc" >&2; exit 1; }
