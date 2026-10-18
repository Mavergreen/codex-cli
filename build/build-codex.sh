#!/bin/sh
# platform: macOS-only -- builds for Apple targets: ultimate-hat for native, an arm64 modern Mac for cross
set -eu

if [ "$#" -ne 1 ]; then
  echo "usage: build-codex.sh native|cross" >&2
  exit 2
fi
MODE=$1
case "$MODE" in native|cross) ;; *) echo "build-codex: mode must be native or cross" >&2; exit 2 ;; esac
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MAVERICKS_BUILD_DIR=$HERE
export MAVERICKS_BUILD_DIR
. "$HERE/lib.sh"
. "$HERE/codex-build-env.sh"
codex_check_host "$MODE"

BUILD_ROOT=$(mavericks_build_root)
SOURCE=$(sh "$HERE/fetch-codex.sh")
# spec: INGREDIENTS.md "License notices" -- Apache-2.0 section 4 needs both files to travel with the binaries
for notice in LICENSE NOTICE; do
  [ -s "$SOURCE/$notice" ] || { echo "build-codex: no $SOURCE/$notice" >&2; exit 1; }
done
TARGET_DIR="$BUILD_ROOT/codex-$MODE-target"
codex_build_env "$MODE" "$SOURCE" "$TARGET_DIR"

ARTIFACT="$BUILD_ROOT/codex-$MODE"
mkdir -p "$ARTIFACT"
codex_cargo build --locked --release \
  --target x86_64-apple-darwin -p codex-cli -p codex-code-mode-host || exit 1

for binary in codex codex-code-mode-host; do
  cp "$TARGET_DIR/x86_64-apple-darwin/release/$binary" "$ARTIFACT/$binary"
  chmod 755 "$ARTIFACT/$binary"
done
for notice in LICENSE NOTICE; do
  cp "$SOURCE/$notice" "$ARTIFACT/$notice"
  chmod 644 "$ARTIFACT/$notice"
done
# spec: build-id.sh -- BUILD_ID (gitignored) holds the identity it chose; the manifest must say the same.
#       VERSION is the older release workflow's file and stays a fallback. With neither this is a dev
#       build, <codex version>-mavericks.0, which build-id.sh never emits and so is never published.
if [ -s "$MAVERICKS_ROOT/BUILD_ID" ]; then
  VERSION=$(tr -d '[:space:]' < "$MAVERICKS_ROOT/BUILD_ID")
elif [ -s "$MAVERICKS_ROOT/VERSION" ]; then
  VERSION=$(tr -d '[:space:]' < "$MAVERICKS_ROOT/VERSION")
else
  VERSION=$(tr -d '[:space:]' < "$MAVERICKS_ROOT/components/codex/version")-mavericks.0
  echo "build-codex: no BUILD_ID: a dev build, $VERSION, never publishable" >&2
fi
[ -n "$VERSION" ] || { echo "build-codex: no version: BUILD_ID or VERSION is empty" >&2; exit 1; }
{
  printf 'version=%s\nmode=%s\ntarget=x86_64-apple-darwin\ndeployment_target=10.9\n' "$VERSION" "$MODE"
  printf 'source_revision=%s\nrust_version=%s\nrusty_v8_version=%s\n' \
    "$(cat "$HERE/codex-revision")" "$RUST_PIN" "$RUSTY_V8_VERSION"
  printf 'clang_version=%s\nprotoc_runtime=%s\nsdk=%s\n' "$CLANG_VERSION" "$PROTOC_RUNTIME" "${SDK##*/}"
} > "$ARTIFACT/build-manifest"
printf '%s\n' "$ARTIFACT"
