#!/bin/sh
# platform: macOS-only -- fetch-clang-22.sh expands the pinned clang-22 pkg
#   usage: llvm-bin.sh
#          Prints the bin directory of this host's pinned clang-22 (clang22 on an x86_64 Mac,
#          clang22-cross on Apple Silicon): CODEX_TEST_LLVM_BIN when set, else an installed one,
#          else the pinned release, fetched. Exits 77 off macOS.
set -eu
if [ -n "${CODEX_TEST_LLVM_BIN:-}" ]; then printf '%s\n' "$CODEX_TEST_LLVM_BIN"; exit 0; fi
[ "$(uname -s)" = Darwin ] || exit 77
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
product=clang22
[ "$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" = 1 ] && product=clang22-cross
if [ -x "/usr/local/mavergreen/$product/bin/llvm-ar" ]; then
  printf '%s\n' "/usr/local/mavergreen/$product/bin"; exit 0
fi
prefix=$(sh "$HERE/../../build/fetch-clang-22.sh" "$product")
printf '%s/bin\n' "$prefix"
