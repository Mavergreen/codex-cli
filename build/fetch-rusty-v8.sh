#!/bin/sh
# platform: host-agnostic -- runs on ultimate-hat and modern macOS
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MAVERICKS_BUILD_DIR=$HERE
export MAVERICKS_BUILD_DIR
. "$HERE/lib.sh"
. "$SHIPYARD_SCRIPTS/mavericks_fetch.sh"

[ "$#" -eq 1 ] || { echo "usage: fetch-rusty-v8.sh SOURCE-DIR" >&2; exit 2; }
SOURCE_DIR=$1
LOCK="$SOURCE_DIR/codex-rs/Cargo.lock"
[ -r "$LOCK" ] || { echo "fetch-rusty-v8: cannot read $LOCK" >&2; exit 2; }

PROFILE=ptrcomp_sandbox_release
TARGET=x86_64-apple-darwin
BUILD_ROOT=$(mavericks_build_root)

VERSIONS=$(awk '
  /^name = "v8"$/ { want = 1; next }
  want && /^version = "/ { gsub(/^version = "|"$/, ""); print; want = 0 }
  /^\[\[package\]\]/ { want = 0 }
' "$LOCK")
case "$VERSIONS" in
  ''|*[!0-9.]*) echo "fetch-rusty-v8: $LOCK must hold exactly one v8 package" >&2; exit 2 ;;
esac
echo "fetch-rusty-v8: v8 $VERSIONS" >&2

BASE="${RUSTY_V8_BASE_URL:-https://github.com/openai/codex/releases/download}/rusty-v8-v$VERSIONS"
DEST="$BUILD_ROOT/rusty-v8-$VERSIONS"
ARCHIVE="librusty_v8_${PROFILE}_${TARGET}.a.gz"
BINDING="src_binding_${PROFILE}_${TARGET}.rs"
SUMS="rusty_v8_${PROFILE}_${TARGET}.sha256"

mkdir -p "$BUILD_ROOT"
SUMS_FILE=$(mktemp "$BUILD_ROOT/.rusty-v8.XXXXXX")
trap 'rm -f "$SUMS_FILE"' EXIT
curl -fsSL -o "$SUMS_FILE" "$BASE/$SUMS"

fetch_asset() {
  name=$1
  sha=$(awk -v n="$name" '$2 == n { print $1 }' "$SUMS_FILE")
  case "$sha" in
    ''|*[!0-9a-f]*) echo "fetch-rusty-v8: $SUMS does not list $name" >&2; exit 1 ;;
  esac
  [ "${#sha}" -eq 64 ] || { echo "fetch-rusty-v8: $SUMS does not list $name" >&2; exit 1; }
  cached=no
  [ ! -f "$DEST/$name" ] || cached=yes
  mav_fetch_verified "$BASE/$name" "$sha" "$DEST" "$name" && return 0
  [ "$cached" = yes ] || exit 1
  mav_fetch_verified "$BASE/$name" "$sha" "$DEST" "$name" || exit 1
}

fetch_asset "$ARCHIVE"
fetch_asset "$BINDING"
printf '%s\n%s\n' "$DEST/$ARCHIVE" "$DEST/$BINDING"
