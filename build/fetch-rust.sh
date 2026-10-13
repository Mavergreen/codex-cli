#!/bin/sh
# platform: macOS-only -- pkgutil expands the toolchain pkg
#   usage: fetch-rust.sh     prints the prefix of the pinned Mavergreen/rust toolchain for this host
#          On an x86_64 Mac (10.9 or modern) that is rust; on Apple Silicon, rust-cross, which runs
#          there and targets 10.9 (build/rust-toolchain.sh decides). The pkg named by
#          components/rust/version is verified against its release's SHA256SUMS, then extracted under
#          the build root -- never installed, so no root is needed and the build uses exactly the
#          pinned toolchain. RUST_RELEASES_URL overrides the release download base (tests).
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MAVERICKS_BUILD_DIR=$HERE
export MAVERICKS_BUILD_DIR
. "$HERE/lib.sh"

BUILD_ROOT=$(mavericks_build_root)
RUST_VERSION=$(tr -d '[:space:]' < "$MAVERICKS_ROOT/components/rust/version")
[ -n "$RUST_VERSION" ] || { echo "fetch-rust: empty components/rust/version" >&2; exit 1; }
short=$(sh "$HERE/rust-toolchain.sh" "$(sh "$SHIPYARD_SCRIPTS/mavericks_mode.sh")" "$(uname -m)")
tc=$(sh "$HERE/fetch-release-pkg.sh" fetch-rust \
  "${RUST_RELEASES_URL:-https://github.com/Mavergreen/rust/releases/download}/$RUST_VERSION" \
  "$short-$RUST_VERSION.pkg" "$short" "$BUILD_ROOT/toolchain/$short-$RUST_VERSION" \
  "usr/local/mavergreen/$short" bin/cargo bin/rustc)
[ -x "$tc/bin/cargo" ] && [ -x "$tc/bin/rustc" ] || {
  echo "fetch-rust: $short-$RUST_VERSION.pkg holds no executable cargo and rustc" >&2; exit 1;
}
printf '%s\n' "$tc"
