#!/bin/sh
# platform: host-agnostic -- builds for Apple targets: ultimate-hat for native; x86_64 Linux or an arm64 modern Mac for cross
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
codex_build_env "$MODE" "$SOURCE" "$TARGET_DIR" "$BUILD_ROOT/objc-$MODE"

ARTIFACT="$BUILD_ROOT/codex-$MODE"
mkdir -p "$ARTIFACT"
# spec: the family build-twice check -- cargo unpacks a crate with the time it unpacked it, and age
#       embeds its locale files' times through rust-embed, so every unpacked crate file is stamped
#       with the commit time before the build reads it
codex_cargo fetch --locked || exit 1
EPOCH=$(sh "$SHIPYARD_SCRIPTS/source-date-epoch.sh") || exit 1
STAMP=$(TZ=UTC date -d "@$EPOCH" +%Y%m%d%H%M.%S 2>/dev/null || TZ=UTC date -r "$EPOCH" +%Y%m%d%H%M.%S) || exit 1
find "$CARGO_HOME/registry/src" -exec env TZ=UTC touch -t "$STAMP" {} + || exit 1
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
  VERSION=$(sh "$HERE/codex-pin.sh" version)-mavericks.0
  echo "build-codex: no BUILD_ID: a dev build, $VERSION, never publishable" >&2
fi
# spec: build/fetch-recaulk-objc.sh header -- a development provider makes a dev build, whatever
#       BUILD_ID says; packaging also refuses its recaulk_origin.
if [ "$RECAULK_ORIGIN" = development ]; then
  VERSION=$(sh "$HERE/codex-pin.sh" version)-mavericks.0
  echo "build-codex: linked with a development Recaulk provider: a dev build, $VERSION, never publishable" >&2
fi
[ -n "$VERSION" ] || { echo "build-codex: no version: BUILD_ID or VERSION is empty" >&2; exit 1; }
# spec: Drydock content-keyed reviews -- the prepared tree the compiler read, by drydock-objc's own digest,
#       and the crate sources cargo compiled (the registry's one unpacked index, as NAME-VERSION/), which
#       build/objc-build-evidence.sh gives the analyzer to hash reviewed citations against.
# spec: INGREDIENTS.md "Deviations" -- the unpinned reader of the provider declaration, recorded
DECL_READER=$(sh "$HERE/decl-plist.sh" --tool) || exit 1
TREE_SHA256=$(sh "$SHIPYARD_SCRIPTS/objc-build-evidence.sh" --tree-digest-only --source-root "$SOURCE") || {
  echo "build-codex: no digest of the prepared tree $SOURCE" >&2; exit 1; }
set -- "$CARGO_HOME"/registry/src/*/
[ "$#" -eq 1 ] && [ -d "$1" ] || { echo "build-codex: not exactly one crate index under $CARGO_HOME/registry/src" >&2; exit 1; }
CRATE_SOURCES=${1%/}
{
  printf 'version=%s\nmode=%s\ntarget=x86_64-apple-darwin\ndeployment_target=10.9\n' "$VERSION" "$MODE"
  printf 'source_revision=%s\nrust_version=%s\nrusty_v8_version=%s\nrusty_v8_removed=%s\n' \
    "$(sh "$HERE/codex-pin.sh" revision)" "$RUST_PIN" "$RUSTY_V8_VERSION" "$RUSTY_V8_REMOVED"
  printf 'clang_version=%s\nprotoc_runtime=%s\nsdk=%s\n' "$CLANG_VERSION" "$PROTOC_RUNTIME" "${SDK##*/}"
  printf 'decl_reader=%s\n' "$DECL_READER"
  printf 'recaulk_origin=%s\nrecaulk_version=%s\nrecaulk_archive_sha256=%s\nrecaulk_declaration_sha256=%s\n' \
    "$RECAULK_ORIGIN" "$RECAULK_VERSION" "$RECAULK_ARCHIVE_SHA256" "$RECAULK_DECLARATION_SHA256"
  printf 'source_tree_sha256=%s\ncrate_sources=%s\ncargo_lock_sha256=%s\n' \
    "$TREE_SHA256" "$CRATE_SOURCES" "$(shasum -a 256 < "$SOURCE/codex-rs/Cargo.lock" | cut -c1-64)"
} > "$ARTIFACT/build-manifest"
printf '%s\n' "$ARTIFACT"
