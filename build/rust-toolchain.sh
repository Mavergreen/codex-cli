#!/bin/sh
# platform: host-agnostic
#   usage: rust-toolchain.sh <mode> <arch>     prints which Mavergreen/rust product builds here
#          <mode> is mavericks_mode.sh's answer (mavericks on 10.9, modern elsewhere), <arch> is
#          `uname -m`. rust runs on any x86_64 macOS from 10.9.5 and targets 10.9; rust-cross runs on
#          Apple Silicon only.
set -eu
case "${1:-}:${2:-}" in
  mavericks:x86_64|modern:x86_64) echo rust ;;
  modern:arm64) echo rust-cross ;;
  *) echo "rust-toolchain: no Mavergreen/rust toolchain runs on mode '${1:-}', arch '${2:-}'" >&2; exit 1 ;;
esac
