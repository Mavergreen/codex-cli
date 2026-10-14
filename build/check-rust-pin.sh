#!/bin/sh
# platform: host-agnostic
#   usage: check-rust-pin.sh SOURCE-DIR   exits 0 when the pinned Mavergreen/rust can build Codex
#          It reads the channel from SOURCE-DIR/codex-rs/rust-toolchain.toml (1.95.0) and the pin
#          from components/rust/version (1.99.0-mavericks.2). The pin's upstream version, before
#          its first '-', must be at least the channel: Rust is backward compatible, so a newer
#          toolchain builds the older channel's code. On success it names both on stderr.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MAVERICKS_BUILD_DIR=$HERE
export MAVERICKS_BUILD_DIR
. "$HERE/lib.sh"

[ "$#" -eq 1 ] || { echo "usage: check-rust-pin.sh SOURCE-DIR" >&2; exit 2; }
TOOLCHAIN="$1/codex-rs/rust-toolchain.toml"
PIN_FILE="$MAVERICKS_ROOT/components/rust/version"
[ -r "$TOOLCHAIN" ] || { echo "check-rust-pin: cannot read $TOOLCHAIN" >&2; exit 1; }
CODEX_CHANNEL=$(sed -n 's/^channel = "\(.*\)"$/\1/p' "$TOOLCHAIN")
RUST_PIN=$(tr -d '[:space:]' < "$PIN_FILE")
RUST_UPSTREAM=${RUST_PIN%%-*}

# spec: shipyard lib.sh ver_cmp() -- it reads a non-numeric field as 0, so a channel such as
#       "stable" would compare as older than any pin and pass. numeric(), from the same lib.sh,
#       refuses anything but a dotted number first.
numeric "$CODEX_CHANNEL" || {
  echo "check-rust-pin: the channel in $TOOLCHAIN is '$CODEX_CHANNEL', not a dotted version number" >&2
  exit 1
}
numeric "$RUST_UPSTREAM" || {
  echo "check-rust-pin: components/rust/version is '$RUST_PIN', whose upstream part '$RUST_UPSTREAM' is not a dotted version number" >&2
  exit 1
}
[ "$(ver_cmp "$RUST_UPSTREAM" "$CODEX_CHANNEL")" -ge 0 ] || {
  echo "check-rust-pin: $TOOLCHAIN wants Rust >= $CODEX_CHANNEL, components/rust/version is $RUST_PIN" >&2
  exit 1
}
echo "check-rust-pin: Rust $RUST_UPSTREAM (components/rust/version $RUST_PIN) builds channel $CODEX_CHANNEL" >&2
