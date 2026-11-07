#!/bin/sh
# platform: host-agnostic -- plain sh over the repo's own files
# spec: build/objc-reviewed-dir.sh header -- reviewed Objective-C evidence binds exact v0 symbols and
#       crate disambiguators, which cargo derives from the build host's rustc (its `-vV`, host triple
#       included), so each build host has its own reviewed rows and the proof takes the build host's.
#   usage: sh tests/objc-reviewed-host-test.sh
set -eu
. "$(dirname "$0")/lib/harness.sh"
h_setup
D="$H_REPO/build/objc-reviewed-dir.sh"
h_assert_eq "$H_REPO/objc/x86_64-apple-darwin" "$(sh "$D" x86_64)" "an x86_64 host (10.9 native, or an Intel Mac's cross) takes the x86_64-apple-darwin rows"
h_assert_eq "$H_REPO/objc/aarch64-apple-darwin" "$(sh "$D" arm64)" "Apple Silicon (rust-cross, as CI) takes the aarch64-apple-darwin rows"
rc=0; sh "$D" i386 >/dev/null 2>&1 || rc=$?
h_assert_eq 1 "$rc" "no Mavergreen rust runs on any other host, so it has no rows"
h_assert_eq "$(sh "$D" "$(uname -m)")" "$(sh "$D")" "with no argument, the host it runs on"
for f in codex-reviewed-evidence.json codex-code-mode-host-reviewed-evidence.json; do
  h_assert_ok test -f "$H_REPO/objc/x86_64-apple-darwin/$f"
  h_assert_absent "$H_REPO/objc/$f" "no host-less $f is left to be taken by mistake"
done
h_assert_contains "$(cat "$H_REPO/build/objc-build-evidence.sh")" 'objc-reviewed-dir.sh' "the proof takes its rows from the build host's directory"
h_done
