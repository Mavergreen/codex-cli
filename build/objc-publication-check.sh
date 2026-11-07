#!/bin/sh
# platform: macOS-only -- reads the proof build/objc-build-evidence.sh wrote; reads tarballs with 10.9's bsdtar
#   usage: objc-publication-check.sh native|cross [TARBALL...]
#          May this build be packaged, or these packages of it be signed? Yes only when all hold:
#            - build/objc-build-evidence.sh --check MODE: the proof still describes these bytes (the
#              binaries, the manifest, the link map, the evidence, the reports and the recorded strict
#              runs), so nothing analyzed has changed since;
#            - both strict runs that proof recorded (reports/NAME.status) exited 0: a blocking send or
#              cannot-measure in either binary blocks publication;
#            - the manifest says the build linked a released Recaulk provider (a development one never
#              ships, whatever BUILD_ID says);
#            - each TARBALL (packaging/build-codex-package.sh's) holds exactly the proven codex,
#              codex-code-mode-host and build-manifest.
#          Run it immediately before packaging, and with the tarballs immediately before signing.
#          It reads recorded results: the fresh analysis is the CTest guards' (build/compat-guard.sh),
#          which the workflow runs first. Nothing here classifies an API.
#          Exit 0 publishable, 1 refused, 2 usage.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MAVERICKS_BUILD_DIR=$HERE
export MAVERICKS_BUILD_DIR
. "$HERE/lib.sh"
usage() { echo "usage: objc-publication-check.sh native|cross [TARBALL...]" >&2; exit 2; }
[ $# -ge 1 ] || usage
MODE=$1; shift
case "$MODE" in native|cross) ;; *) usage ;; esac
BUILD_ROOT=$(mavericks_build_root)
ART="$BUILD_ROOT/codex-$MODE"
OBJC="$BUILD_ROOT/objc-$MODE"
refuse() { echo "objc-publication-check: $*" >&2; exit 1; }
sha() { shasum -a 256 "$1" | cut -c1-64; }

sh "$HERE/objc-build-evidence.sh" --check "$MODE" ||
  refuse "no current Objective-C proof for $ART: run build/objc-build-evidence.sh $MODE, then the CTest guards"
for name in codex codex-code-mode-host; do
  st="$OBJC/reports/$name.status"
  # spec: build/objc-build-evidence.sh -- the status file is in identity, so --check vouched for its bytes
  grep -q " $st\$" "$OBJC/identity" || refuse "$name: no strict run recorded in the $MODE proof"
  rc=$(cat "$st")
  [ "$rc" = 0 ] || refuse "$name: strict run exited $rc (reports/$name.objc-compat.json)"
done
case "$(sed -n 's/^recaulk_origin=//p' "$ART/build-manifest")" in
  released) ;;
  development) refuse "$ART was linked with a development Recaulk provider: never published" ;;
  *) refuse "$ART/build-manifest has no recaulk_origin=released" ;;
esac

# proven PATH: the SHA-256 the proof recorded for PATH
proven() { sed -n "s|^\([0-9a-f]\{64\}\) $1\$|\1|p" "$OBJC/identity"; }
for tb in "$@"; do
  [ -f "$tb" ] || refuse "no tarball $tb"
  x=$(mktemp -d "${TMPDIR:-/tmp}/objc-publication-check.XXXXXX")
  tar -xzf "$tb" -C "$x" bin/codex bin/codex-code-mode-host build-manifest 2>/dev/null || { rm -rf "$x"; refuse "$tb is not a Codex package"; }
  for m in bin/codex:codex bin/codex-code-mode-host:codex-code-mode-host build-manifest:build-manifest; do
    member=${m%%:*}; art=${m#*:}
    [ "$(sha "$x/$member")" = "$(proven "$ART/$art")" ] || { rm -rf "$x"; refuse "$tb: $member is not the proven $ART/$art"; }
  done
  rm -rf "$x"
done
echo "objc-publication-check: the $MODE build$( [ $# -eq 0 ] || echo " and its $# package(s)") may be packaged and signed" >&2
