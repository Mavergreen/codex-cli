#!/bin/sh
# platform: ultimate-hat for native; modern macOS for cross.
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

ACTUAL_MODE=$(sh "$SHIPYARD_SCRIPTS/mavericks_mode.sh")
[ "$MODE" = "$ACTUAL_MODE" ] || {
  echo "build-codex: requested $MODE build on a $ACTUAL_MODE host" >&2; exit 1;
}
[ "$(uname -s)" = Darwin ] || {
  echo "build-codex: Apple builds require macOS" >&2; exit 1;
}
[ "$MODE" != cross ] || [ "$(uname -m)" = arm64 ] || {
  echo "build-codex: cross builds require an arm64 modern macOS host" >&2; exit 1;
}

BUILD_ROOT=$(mavericks_build_root)
SOURCE=$(sh "$HERE/fetch-codex.sh")
RUST_REVISION=$(tr -d '[:space:]' < "$MAVERICKS_ROOT/mavericks-rust.pin")
RUST_SOURCE="$BUILD_ROOT/mavergreen-rust-src"
sh "$SHIPYARD_SCRIPTS/clone_pinned.sh" \
  https://github.com/Mavergreen/rust.git main "$RUST_REVISION" "$RUST_SOURCE"
[ "$(git -C "$RUST_SOURCE" rev-parse HEAD)" = "$RUST_REVISION" ] || {
  echo "build-codex: Rust checkout does not match mavericks-rust.pin" >&2; exit 1;
}
[ -z "$(git -C "$RUST_SOURCE" status --porcelain)" ] || {
  echo "build-codex: pinned Rust checkout is dirty" >&2; exit 1;
}

export MAVERICKS_WORK="$BUILD_ROOT/rust-work"
case "$MODE" in
  native)
    RUST_VARIANT=native; export RUST_VARIANT
    sh "$RUST_SOURCE/build/build-native.sh"
    RUST_PREFIX="$MAVERICKS_WORK/work-native/stage/usr/local/mavergreen/rust"
    ;;
  cross)
    RUST_VARIANT=cross; export RUST_VARIANT
    sh "$RUST_SOURCE/build/build-cross.sh"
    RUST_PREFIX="$MAVERICKS_WORK/work-cross/stage/usr/local/mavergreen/rust-cross"
    ;;
esac
[ -x "$RUST_PREFIX/bin/cargo" ] && [ -x "$RUST_PREFIX/bin/rustc" ] || {
  echo "build-codex: pinned Rust toolchain was not staged at $RUST_PREFIX" >&2; exit 1;
}

SDK=""
if [ "$MODE" = cross ]; then
  SDK=$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh")
  export SDKROOT="$SDK"
elif [ -z "${SDKROOT:-}" ] && command -v xcrun >/dev/null 2>&1; then
  SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
  export SDKROOT
fi

ARTIFACT="$BUILD_ROOT/codex-$MODE"
TARGET_DIR="$BUILD_ROOT/codex-$MODE-target"
mkdir -p "$ARTIFACT" "$TARGET_DIR"
export CARGO_TARGET_DIR="$TARGET_DIR"
export CARGO_HOME="$BUILD_ROOT/cargo-home"
export CARGO_NET_GIT_FETCH_WITH_CLI=true
export MACOSX_DEPLOYMENT_TARGET=10.9

(cd "$SOURCE/codex-rs" && PATH="$RUST_PREFIX/bin:$PATH" \
  "$RUST_PREFIX/bin/cargo" build --locked --release \
  --target x86_64-apple-darwin -p codex-cli)

cp "$TARGET_DIR/x86_64-apple-darwin/release/codex" "$ARTIFACT/codex"
chmod 755 "$ARTIFACT/codex"
VERSION=$(sh "$HERE/versions.sh" auto)
{
  printf 'version=%s\nmode=%s\ntarget=x86_64-apple-darwin\ndeployment_target=10.9\n' "$VERSION" "$MODE"
  printf 'source_revision=%s\nrust_revision=%s\n' \
    "$(cat "$HERE/codex-revision")" "$RUST_REVISION"
  if [ -n "$SDK" ]; then printf 'sdk=%s\n' "$SDK"; fi
} > "$ARTIFACT/build-manifest"
printf '%s\n' "$ARTIFACT"
