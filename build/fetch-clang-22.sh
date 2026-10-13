#!/bin/sh
# platform: macOS-only -- pkgutil expands the pkg
#   usage: fetch-clang-22.sh clang22|clang22-cross|libcxx22
#          prints the prefix of that product from the Mavergreen/clang-22 release pinned in
#          components/clang-22/version. clang22 runs on x86_64 macOS from 10.9.5, clang22-cross on
#          Apple Silicon; both target 10.9. libcxx22 is the release's libc++ runtime for 10.9. The pkg
#          is verified against its release's SHA256SUMS, then extracted under the build root -- never
#          installed, so no root is needed and the build uses exactly the pinned product.
#          CLANG22_RELEASES_URL overrides the release download base (tests).
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MAVERICKS_BUILD_DIR=$HERE
export MAVERICKS_BUILD_DIR
. "$HERE/lib.sh"

[ "$#" -eq 1 ] || { echo "usage: fetch-clang-22.sh clang22|clang22-cross|libcxx22" >&2; exit 2; }
short=$1
case "$short" in
  clang22) stem=mavericks-clang-22-native; probe=bin/clang++ ;;
  clang22-cross) stem=mavericks-clang-22-cross; probe=bin/clang++ ;;
  libcxx22) stem=libcxx22; probe=lib/libc++.1.dylib ;;
  *) echo "fetch-clang-22: no Mavergreen/clang-22 product '$short'" >&2; exit 2 ;;
esac
BUILD_ROOT=$(mavericks_build_root)
VERSION=$(tr -d '[:space:]' < "$MAVERICKS_ROOT/components/clang-22/version")
[ -n "$VERSION" ] || { echo "fetch-clang-22: empty components/clang-22/version" >&2; exit 1; }
exec sh "$HERE/fetch-release-pkg.sh" fetch-clang-22 \
  "${CLANG22_RELEASES_URL:-https://github.com/Mavergreen/clang-22/releases/download}/$VERSION" \
  "$stem-$VERSION.pkg" "$stem" "$BUILD_ROOT/toolchain/$short-$VERSION" \
  "usr/local/mavergreen/$short" "$probe"
