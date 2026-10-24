#!/bin/sh
# platform: host-agnostic -- plain sh, gh and shasum; CI runs it on the Linux and macOS runners
#   usage: fetch-required-pkg.sh NAME DIR
#          Downloads the .pkg of Mavergreen/NAME's release pinned in components/NAME/version into
#          DIR/NAME, verifies it against that release's SHA256SUMS, and prints its path. The 10.9
#          smokes install it beside codex-cli's pkg; pinned, a new NAME release changes nothing here
#          until Renovate's PR moves the pin.
set -eu
[ "$#" -eq 2 ] || { echo "usage: fetch-required-pkg.sh NAME DIR" >&2; exit 2; }
NAME=$1
DEST=$2/$1
PIN=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/components/$NAME/version
[ -f "$PIN" ] || { echo "fetch-required-pkg: no components/$NAME/version" >&2; exit 1; }
TAG=$(tr -d '[:space:]' < "$PIN")
printf '%s\n' "$TAG" | grep -Eqx '[0-9][0-9.]*-mavericks\.[0-9]+' ||
  { echo "fetch-required-pkg: components/$NAME/version '$TAG' is not a Mavergreen release tag" >&2; exit 1; }

gh release download "$TAG" -R "Mavergreen/$NAME" --pattern '*.pkg' --pattern SHA256SUMS --dir "$DEST" >&2
set -- "$DEST"/*.pkg
[ "$#" -eq 1 ] && [ -f "$1" ] ||
  { echo "fetch-required-pkg: expected one .pkg in Mavergreen/$NAME $TAG, got: $*" >&2; exit 1; }
PKG=$(basename "$1")
SUM=$(awk -v f="$PKG" '$2 == f || $2 == "*" f' "$DEST/SHA256SUMS")
[ -n "$SUM" ] || { echo "fetch-required-pkg: $PKG is not in Mavergreen/$NAME $TAG's SHA256SUMS" >&2; exit 1; }
# platform: an explicit test, since 10.9's sh (bash 3.2) lets set -e pass a failed ( ... ) >&2
( cd "$DEST" && printf '%s\n' "$SUM" | shasum -a 256 -c - ) >&2 ||
  { echo "fetch-required-pkg: $PKG does not match Mavergreen/$NAME $TAG's SHA256SUMS" >&2; exit 1; }
printf '%s\n' "$DEST/$PKG"
