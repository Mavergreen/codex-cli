#!/bin/sh
# platform: host-agnostic
#   usage: check-rust-pin.sh CHANNEL PIN     exits 0 when the pinned Mavergreen/rust can build Codex
#          CHANNEL is Codex's rust-toolchain.toml channel (1.95.0); PIN is components/rust/version
#          (1.99.0-mavericks.2). The pin's upstream version, before its first '-', must be at least
#          the channel: Rust is backward compatible, so a newer toolchain builds the older channel's
#          code.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MAVERICKS_BUILD_DIR=$HERE
export MAVERICKS_BUILD_DIR
. "$HERE/lib.sh"

[ "$#" -eq 2 ] || { echo "usage: check-rust-pin.sh CHANNEL PIN" >&2; exit 2; }
CODEX_CHANNEL=$1
RUST_PIN=$2
RUST_UPSTREAM=${RUST_PIN%%-*}
[ -n "$CODEX_CHANNEL" ] || {
  echo "build-codex: no Rust channel in Codex's rust-toolchain.toml" >&2; exit 1;
}
[ -n "$RUST_UPSTREAM" ] || {
  echo "build-codex: no Rust version in components/rust/version" >&2; exit 1;
}
[ "$(ver_cmp "$RUST_UPSTREAM" "$CODEX_CHANNEL")" -ge 0 ] || {
  echo "build-codex: Codex wants Rust >= $CODEX_CHANNEL, components/rust/version is $RUST_PIN" >&2; exit 1;
}
