#!/bin/sh
# platform: host-agnostic
#   usage: rust-toolchain.sh <mode> <arch>     prints which Mavergreen/rust product builds here
#          <mode> is mavericks_mode.sh's answer, <arch> is `uname -m`. rust runs on any x86_64 macOS
#          from 10.9.5 and targets 10.9; rust-cross runs on Apple Silicon only.
set -eu
case "${1:-}:${2:-}" in
  native:x86_64|cross:x86_64) echo rust ;;
  cross:arm64) echo rust-cross ;;
  *) echo "rust-toolchain: no Mavergreen/rust toolchain runs on mode '${1:-}', arch '${2:-}'" >&2; exit 1 ;;
esac
