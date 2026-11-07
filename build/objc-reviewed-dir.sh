#!/bin/sh
# platform: host-agnostic -- plain sh
#   usage: objc-reviewed-dir.sh [ARCH]
#          Prints the directory of reviewed Objective-C evidence for binaries built on a host of ARCH
#          (`uname -m`, default this host's): objc/<the build host's rust triple>/, holding
#          codex-reviewed-evidence.json and codex-code-mode-host-reviewed-evidence.json.
#          The rows name exact v0 symbols and crate disambiguators, and cargo derives every
#          disambiguator from the rustc that builds it, `rustc -vV` and so its host triple included:
#          the same source built on 10.9 (rust, x86_64) and on Apple Silicon (rust-cross, aarch64, as
#          CI builds) has different symbols. build/rust-toolchain.sh picks the toolchain the same way.
#          Exit 1 for a host no Mavergreen rust runs on.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
case "${1:-$(uname -m)}" in
  x86_64) triple=x86_64-apple-darwin ;;
  arm64) triple=aarch64-apple-darwin ;;
  *) echo "objc-reviewed-dir: no Mavergreen rust builds on '${1:-$(uname -m)}', so it has no reviewed rows" >&2; exit 1 ;;
esac
printf '%s\n' "$ROOT/objc/$triple"
