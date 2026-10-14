#!/bin/sh
# platform: modern macOS -- require matching native and cross build inputs before packaging.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PRODUCT_ROOT=$(CDPATH= cd -- "$HERE/.." && pwd)
BUILD_ROOT=$(sh "$HERE/resolve-build-root.sh")
NATIVE="$BUILD_ROOT/codex-native/build-manifest"
CROSS="$BUILD_ROOT/codex-cross/build-manifest"

for manifest in "$NATIVE" "$CROSS"; do
  [ -f "$manifest" ] || { echo "check-build-manifests: missing $manifest" >&2; exit 1; }
done

field() { sed -n "s/^$1=//p" "$2"; }
EXPECTED_SOURCE=$(tr -d '[:space:]' < "$HERE/codex-revision")
EXPECTED_RUST=$(tr -d '[:space:]' < "$PRODUCT_ROOT/components/rust/version")
EXPECTED_CLANG=$(tr -d '[:space:]' < "$PRODUCT_ROOT/components/clang-22/version")

RUSTY_V8_NATIVE=$(field rusty_v8_version "$NATIVE")
SDK_NATIVE=$(field sdk "$NATIVE")

check_manifest() {
  manifest=$1
  wanted_mode=$2
  [ "$(field mode "$manifest")" = "$wanted_mode" ] || {
    echo "check-build-manifests: wrong mode in $manifest" >&2; exit 1;
  }
  [ "$(field target "$manifest")" = x86_64-apple-darwin ] || {
    echo "check-build-manifests: wrong target in $manifest" >&2; exit 1;
  }
  [ "$(field deployment_target "$manifest")" = 10.9 ] || {
    echo "check-build-manifests: wrong deployment target in $manifest" >&2; exit 1;
  }
  [ "$(field source_revision "$manifest")" = "$EXPECTED_SOURCE" ] || {
    echo "check-build-manifests: Codex source revision mismatch in $manifest" >&2; exit 1;
  }
  [ "$(field rust_version "$manifest")" = "$EXPECTED_RUST" ] || {
    echo "check-build-manifests: Rust toolchain version mismatch in $manifest" >&2; exit 1;
  }
  [ "$(field clang_version "$manifest")" = "$EXPECTED_CLANG" ] || {
    echo "check-build-manifests: clang-22 version mismatch in $manifest" >&2; exit 1;
  }
  case "$(field rusty_v8_version "$manifest")" in
    ''|*[!0-9.]*|.*) echo "check-build-manifests: malformed rusty_v8_version in $manifest" >&2; exit 1 ;;
  esac
  [ "$(field rusty_v8_version "$manifest")" = "$RUSTY_V8_NATIVE" ] || {
    echo "check-build-manifests: V8 version differs from native in $manifest" >&2; exit 1;
  }
  # platform: the SDK is named, not pathed: each host caches shipyard's pinned SDK in its own
  #           place. How it reaches the target (SDKROOT natively, target rustflags in cross, for
  #           the reason build-codex.sh gives) follows from mode, so it needs no field of its own.
  case "$(field sdk "$manifest")" in
    MacOSX*.sdk) ;;
    *) echo "check-build-manifests: missing or malformed sdk in $manifest" >&2; exit 1 ;;
  esac
  [ "$(field sdk "$manifest")" = "$SDK_NATIVE" ] || {
    echo "check-build-manifests: SDK differs from native in $manifest" >&2; exit 1;
  }
}

check_manifest "$NATIVE" native
check_manifest "$CROSS" cross
# platform: protoc_runtime is the only field allowed to differ. It names the libc++ that the
#           build-time protoc ran on -- the release's libcxx22 on 10.9, the host's own on a modern
#           Mac -- and no part of it is linked into either binary.
[ "$(field protoc_runtime "$NATIVE")" = "libcxx22-$EXPECTED_CLANG" ] || {
  echo "check-build-manifests: native protoc_runtime is not libcxx22-$EXPECTED_CLANG" >&2; exit 1;
}
[ "$(field protoc_runtime "$CROSS")" = host ] || {
  echo "check-build-manifests: cross protoc_runtime is not host" >&2; exit 1;
}
echo "check-build-manifests: native and cross inputs match"
