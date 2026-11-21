#!/bin/sh
# platform: host-agnostic -- plain sh
#   usage: objc-reviewed-dir.sh [ARCH]
#          Prints the directory of reviewed Objective-C evidence for binaries built on a host of ARCH
#          (`uname -m`, default this host's): objc/<the build host's rust triple>/, holding
#          codex-reviewed-evidence.json and codex-code-mode-host-reviewed-evidence.json.
#          The rows are Drydock's schema 2: functions by path, files by hash. The exact v0 symbols and
#          crate disambiguators, which cargo derives from the rustc that builds them (`rustc -vV`, host
#          triple included), are filled in from each build's binary, so both hosts' rows are the same
#          today; the per-host directories stay so a host-specific row has a place.
#          build/rust-toolchain.sh picks the toolchain the same way.
#          Exit 1 for a host no Mavergreen rust runs on.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
case "${1:-$(uname -m)}" in
  x86_64) triple=x86_64-apple-darwin ;;
  arm64) triple=aarch64-apple-darwin ;;
  *) echo "objc-reviewed-dir: no Mavergreen rust builds on '${1:-$(uname -m)}', so it has no reviewed rows" >&2; exit 1 ;;
esac
printf '%s\n' "$ROOT/objc/$triple"
