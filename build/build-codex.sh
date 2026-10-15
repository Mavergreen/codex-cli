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
# spec: INGREDIENTS.md "License notices" -- Apache-2.0 section 4 needs both files to travel with the binaries
for notice in LICENSE NOTICE; do
  [ -s "$SOURCE/$notice" ] || { echo "build-codex: no $SOURCE/$notice" >&2; exit 1; }
done
sh "$HERE/check-rust-pin.sh" "$SOURCE"
RUST_PIN=$(tr -d '[:space:]' < "$MAVERICKS_ROOT/components/rust/version")

RUST_PREFIX=$(sh "$HERE/fetch-rust.sh")
[ -x "$RUST_PREFIX/bin/cargo" ] && [ -x "$RUST_PREFIX/bin/rustc" ] || {
  echo "build-codex: fetched Rust toolchain is incomplete at $RUST_PREFIX" >&2; exit 1;
}

# platform: both modes build against shipyard's pinned 10.9 SDK. The Mavergreen clang-22 product
#           expects it at SDKs/MacOSX10.9.sdk beside its bin/, and its cfg passes -isysroot there
#           for every target C and C++ compile; this host's xcrun --show-sdk-path prints nothing.
SDK=$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh")
# platform: cargo uses RUSTFLAGS or CARGO_ENCODED_RUSTFLAGS from the caller in place of the
#           target rustflags that cross sets below, so neither reaches either mode.
unset RUSTFLAGS CARGO_ENCODED_RUSTFLAGS
case "$MODE" in
  # platform: natively host and target are both 10.9 x86_64, so SDKROOT may reach build scripts
  #           too. The 2026-10-14 native builds were measured with it set.
  native) export SDKROOT="$SDK" ;;
  # platform: in cross, SDKROOT would also reach the aarch64 build scripts and proc macros, which
  #           cannot link against the 10.9 SDK (as ../mavergreen-rg and ../mavergreen-fd's
  #           build/build.sh say). target.x86_64-apple-darwin rustflags reach only the target's
  #           links, and cargo splits them on whitespace. Not yet measured on an arm64 host.
  cross)
    case "$SDK" in *[[:space:]]*)
      echo "build-codex: the SDK path $SDK contains whitespace, which cargo would split inside its rustflags" >&2
      exit 1 ;;
    esac
    unset SDKROOT
    CARGO_TARGET_X86_64_APPLE_DARWIN_RUSTFLAGS="-C link-arg=-isysroot -C link-arg=$SDK"
    export CARGO_TARGET_X86_64_APPLE_DARWIN_RUSTFLAGS ;;
esac

# platform: 10.9's own clang 3.5 cannot assemble aws-lc's AVX-512 code and has no <stdatomic.h>,
#           so C and C++ dependencies compile with Mavergreen/clang-22 (clang22 on 10.9,
#           clang22-cross on Apple Silicon). The target-specific names keep a cross build's
#           aarch64 build scripts on the host compiler.
case "$MODE" in native) CLANG_PRODUCT=clang22 ;; cross) CLANG_PRODUCT=clang22-cross ;; esac
CLANG_VERSION=$(tr -d '[:space:]' < "$MAVERICKS_ROOT/components/clang-22/version")
CLANG_PREFIX=$(sh "$HERE/fetch-clang-22.sh" "$CLANG_PRODUCT")
mkdir -p "$CLANG_PREFIX/../var/$CLANG_PRODUCT/SDKs"
ln -sfn "$SDK" "$CLANG_PREFIX/SDKs/MacOSX10.9.sdk"
[ -x "$CLANG_PREFIX/bin/clang" ] && [ -x "$CLANG_PREFIX/bin/clang++" ] &&
  [ -d "$CLANG_PREFIX/SDKs/MacOSX10.9.sdk/usr/include" ] || {
  echo "build-codex: $CLANG_PRODUCT at $CLANG_PREFIX has no compilers or no SDK" >&2; exit 1;
}
export CC_x86_64_apple_darwin="$CLANG_PREFIX/bin/clang"
export CXX_x86_64_apple_darwin="$CLANG_PREFIX/bin/clang++"
# platform: 10.9's cc overflows posix_spawn's argv on codex-code-mode-host's ~1355 LTO objects, so
#           the same clang++ links: it hands lld a response file. Its cfg links librecaulk.a, so
#           Mavergreen/rust's rustc (from 1.99.0-mavericks.2) adds no back-fill of its own. The
#           manifest needs no linker field: the linker follows clang_version, which both modes
#           must match.
export CARGO_TARGET_X86_64_APPLE_DARWIN_LINKER="$CLANG_PREFIX/bin/clang++"
# platform: no host pkg-config answers for the 10.9 target. ultimate-hat's pkgsrc one made lzma-sys
#           link /opt/pkg/lib/liblzma.5.dylib (and, through its -L, /opt/pkg's libiconv) into codex,
#           and a modern Mac's Homebrew one would do the same. With every probe failing, lzma-sys
#           and aws-lc-sys build their bundled sources with clang-22, as the other -sys crates do.
export PKG_CONFIG_x86_64_apple_darwin=/usr/bin/false

# platform: protoc-bin-vendored's macOS protoc needs libc++ symbols 10.9's /usr/lib/libc++ lacks,
#           and Codex's build script runs it by a fixed path. On 10.9 the cargo process tree runs on
#           the release's libcxx22, extracted under the build root: inserted, flat namespace, and
#           found by leaf name so libc++'s own libc++abi dependency resolves there too. It is
#           build-time only and never reaches the shipped binaries. A cross build's protoc is the
#           aarch64 one on a modern libc++ and needs none of this.
PROTOC_RUNTIME=host
set --
if [ "$MODE" = native ]; then
  LIBCXX_PREFIX=$(sh "$HERE/fetch-clang-22.sh" libcxx22)
  PROTOC_RUNTIME="libcxx22-$CLANG_VERSION"
  set -- env DYLD_LIBRARY_PATH="$LIBCXX_PREFIX/lib" DYLD_FORCE_FLAT_NAMESPACE=1 \
    DYLD_INSERT_LIBRARIES="$LIBCXX_PREFIX/lib/libc++abi.1.dylib:$LIBCXX_PREFIX/lib/libc++.1.dylib"
fi

ARTIFACT="$BUILD_ROOT/codex-$MODE"
TARGET_DIR="$BUILD_ROOT/codex-$MODE-target"
mkdir -p "$ARTIFACT" "$TARGET_DIR"
V8_FILES=$(sh "$HERE/fetch-rusty-v8.sh" "$SOURCE")
# spec: build/fetch-rusty-v8.sh -- it stores the archive under rusty-v8-<Cargo.lock's v8 version>/.
RUSTY_V8_ARCHIVE=$(printf '%s\n' "$V8_FILES" | sed -n 1p)
RUSTY_V8_SRC_BINDING_PATH=$(printf '%s\n' "$V8_FILES" | sed -n 2p)
[ -f "$RUSTY_V8_ARCHIVE" ] && [ -f "$RUSTY_V8_SRC_BINDING_PATH" ] || {
  echo "build-codex: fetch-rusty-v8.sh did not name an archive and a binding" >&2; exit 1;
}
RUSTY_V8_VERSION=$(printf '%s\n' "$RUSTY_V8_ARCHIVE" | sed -n 's,.*/rusty-v8-\([0-9][0-9.]*\)/.*,\1,p')
[ -n "$RUSTY_V8_VERSION" ] || {
  echo "build-codex: no V8 version in $RUSTY_V8_ARCHIVE" >&2; exit 1;
}
export RUSTY_V8_ARCHIVE RUSTY_V8_SRC_BINDING_PATH
export CARGO_TARGET_DIR="$TARGET_DIR"
export CARGO_HOME="$BUILD_ROOT/cargo-home"
export CARGO_NET_GIT_FETCH_WITH_CLI=true
export MACOSX_DEPLOYMENT_TARGET=10.9

(cd "$SOURCE/codex-rs" && PATH="$RUST_PREFIX/bin:$PATH" "$@" \
  "$RUST_PREFIX/bin/cargo" build --locked --release \
  --target x86_64-apple-darwin -p codex-cli -p codex-code-mode-host) || exit 1

for binary in codex codex-code-mode-host; do
  cp "$TARGET_DIR/x86_64-apple-darwin/release/$binary" "$ARTIFACT/$binary"
  chmod 755 "$ARTIFACT/$binary"
done
for notice in LICENSE NOTICE; do
  cp "$SOURCE/$notice" "$ARTIFACT/$notice"
  chmod 644 "$ARTIFACT/$notice"
done
VERSION=$(sh "$HERE/versions.sh" auto)
{
  printf 'version=%s\nmode=%s\ntarget=x86_64-apple-darwin\ndeployment_target=10.9\n' "$VERSION" "$MODE"
  printf 'source_revision=%s\nrust_version=%s\nrusty_v8_version=%s\n' \
    "$(cat "$HERE/codex-revision")" "$RUST_PIN" "$RUSTY_V8_VERSION"
  printf 'clang_version=%s\nprotoc_runtime=%s\nsdk=%s\n' "$CLANG_VERSION" "$PROTOC_RUNTIME" "${SDK##*/}"
} > "$ARTIFACT/build-manifest"
printf '%s\n' "$ARTIFACT"
