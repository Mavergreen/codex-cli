#!/bin/sh
# platform: host-agnostic -- runs the package's pre-uninstall hook with plain sh
#   usage: sh tests/pre-uninstall-test.sh
#          The hook shipyard's `mavergreen uninstall` runs is executable, exits 0, and names
#          what each user's home keeps, how to remove it, and that the rest of ~/.codex stays.
set -eu
. "$(dirname "$0")/lib/harness.sh"
h_setup
HOOK="$H_REPO/tree/libexec/mavergreen/pre-uninstall"

h_assert_ok test -x "$HOOK"
rc=0
out="$(MAVERGREEN_ROOT=/usr/local/mavergreen MAVERGREEN_PRODUCT=codex-cli "$HOOK" </dev/null 2>&1)" || rc=$?
h_assert_eq 0 "$rc" "the hook exits 0, so the uninstall goes on ($out)"
h_assert_contains "$out" "~/.codex/packages/standalone" "it names the Codex builds"
h_assert_contains "$out" "~/.codex/packages/app-server-daemon" "it names the daemon's builds"
h_assert_contains "$out" "~/Library/Application Support/dev.mavergreen.codex-cli" "it names the launcher's records"
h_assert_contains "$out" "~/.local/bin/codex" "it names the link"
h_assert_contains "$out" '[ "$(readlink ~/.local/bin/codex)" = /usr/local/mavergreen/bin/codex ] && rm -f ~/.local/bin/codex' \
  "it removes the link only when it is the launcher's"
h_assert_contains "$out" "sign-in, settings and sessions" "it says the rest of ~/.codex stays"

h_done
