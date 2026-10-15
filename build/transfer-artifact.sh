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
# platform: macOS 27 stamps every file with a com.apple.provenance xattr that `xattr -cr` cannot
#           remove, and its bsdtar writes `._` AppleDouble members and pax xattr headers for it.
#           10.9's bsdtar 2.8.3 then lists the `._` members and exits 1 ("Ignoring malformed pax
#           extended attribute"), so verify-artifact.sh refuses the archive. COPYFILE_DISABLE=1 stops
#           the AppleDouble members and 10.9's tar honors it; macOS 27 also needs --no-xattrs, which
#           10.9's tar rejects, so probe for it.
COPYFILE_DISABLE=1
export COPYFILE_DISABLE
if tar --no-xattrs -cf /dev/null /dev/null 2>/dev/null; then
  set -- --no-xattrs
else
  set --
fi
tar "$@" -cf "$STAGING/codex.tar" -C "$SOURCE" codex codex-code-mode-host build-manifest LICENSE NOTICE
(cd "$STAGING" && shasum -a 256 codex.tar > codex.tar.sha256)

case "$DESTINATION" in
  *:*) scp "$STAGING/codex.tar" "$STAGING/codex.tar.sha256" "$DESTINATION/" ;;
  *) mkdir -p "$DESTINATION"
     cp "$STAGING/codex.tar" "$STAGING/codex.tar.sha256" "$DESTINATION/" ;;
esac
printf '%s\n' "$DESTINATION/codex.tar" "$DESTINATION/codex.tar.sha256"
