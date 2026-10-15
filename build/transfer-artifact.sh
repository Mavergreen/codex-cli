#!/bin/sh
# platform: host-agnostic -- archives locally, then copies or scp's the finished files.
set -eu

if [ "$#" -ne 2 ]; then
  echo "usage: transfer-artifact.sh ARTIFACT-DIRECTORY DESTINATION" >&2
  exit 2
fi
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PRODUCT_ROOT=$(CDPATH= cd -- "$HERE/.." && pwd)
SOURCE=$(CDPATH= cd -P -- "$1" && pwd)
DESTINATION=$2
case "$SOURCE/" in
  "$PRODUCT_ROOT/"*) echo "transfer-artifact: source must be outside the product tree" >&2; exit 1 ;;
esac
[ -x "$SOURCE/codex" ] || { echo "transfer-artifact: missing executable $SOURCE/codex" >&2; exit 1; }
[ -x "$SOURCE/codex-code-mode-host" ] || { echo "transfer-artifact: missing executable $SOURCE/codex-code-mode-host" >&2; exit 1; }
[ -f "$SOURCE/build-manifest" ] || { echo "transfer-artifact: missing $SOURCE/build-manifest" >&2; exit 1; }
for notice in LICENSE NOTICE; do
  [ -s "$SOURCE/$notice" ] || { echo "transfer-artifact: missing $SOURCE/$notice" >&2; exit 1; }
done

BUILD_ROOT=$(sh "$HERE/resolve-build-root.sh")
STAGING="$BUILD_ROOT/transfer-artifact.$$"
mkdir "$STAGING"
trap 'rm -rf "$STAGING"' EXIT HUP INT TERM
tar -cf "$STAGING/codex.tar" -C "$SOURCE" codex codex-code-mode-host build-manifest LICENSE NOTICE
(cd "$STAGING" && shasum -a 256 codex.tar > codex.tar.sha256)

case "$DESTINATION" in
  *:*) scp "$STAGING/codex.tar" "$STAGING/codex.tar.sha256" "$DESTINATION/" ;;
  *) mkdir -p "$DESTINATION"
     cp "$STAGING/codex.tar" "$STAGING/codex.tar.sha256" "$DESTINATION/" ;;
esac
printf '%s\n' "$DESTINATION/codex.tar" "$DESTINATION/codex.tar.sha256"
