#!/bin/sh
# platform: macOS-only -- the tests drive tools of Mac OS X 10.9 (bsdtar, plutil)
#   usage: . "$(dirname "$0")/lib/harness.sh"; h_setup; ... h_assert_* ...  h_setup installs the EXIT trap; h_teardown removes $H and fails the test if any assert failed.
#          A test's last line is h_done: a test that exits 0 without reaching it died partway, and fails.
#          asserts must not run inside $(...) or a pipeline: their failure count would be lost.

H_FAILS=0
H_REPO="$(cd "$(dirname "$0")/.." && pwd)"
H_ORIG_HOME="${HOME-}"
H_ORIG_PATH="$PATH"

h_setup() {
  H_DONE=0
  trap h_teardown EXIT
  # every variable the launcher, the installer and the fixtures read, so none leaks in from the developer's shell
  unset CODEX_HOME CODEX_BUILDS_URL CODEX_PKG_ROOT CODEX_ED25519_VERIFY CODEX_PKG_UPDATER_OPEN \
    CODEX_INSTALL_ASSUME_TTY CODEX_INSTALL_NO_UPDATER CODEX_AQUATRANSPORT_VERSION CODEX_RELEASE \
    CODEX_UPDATE_FROM_RELEASE CODEX_NON_INTERACTIVE CODEX_INSTALL_IF_LATEST CODEX_INSTALL_IF_CURRENT \
    CODEX_INSTALL_DAEMON_ONLY CODEX_INSTALL_DEFER_SELECTION CODEX_TEST_GATE
  H="$(mktemp -d "${TMPDIR:-/tmp}/codex test.XXXXXX")"
  H="$(cd "$H" && pwd -P)"
  export H
  mkdir -p "$H/home" "$H/bin"
  HOME="$H/home"
  export HOME
}

h_done() { H_DONE=1; }

h_teardown() {
  _h_rc="${1:-$?}"
  [ -n "${H-}" ] && rm -rf "$H"
  HOME="$H_ORIG_HOME"
  PATH="$H_ORIG_PATH"
  export HOME PATH
  [ "$_h_rc" -eq 0 ] || exit "$_h_rc"
  # platform: bash 3.2, 10.9's /bin/sh, hands the EXIT trap a status of 0 when an unset variable under
  #           set -u kills the script, so only the missing h_done shows that the test died
  if [ "${H_DONE:-0}" -ne 1 ]; then
    echo "FAIL: the test exited before h_done, so it died partway (an unset variable, under set -u?)" >&2
    exit 1
  fi
  [ "${H_FAILS:-0}" -eq 0 ] || exit 1
}

h_assert_eq() {
  if [ "$1" != "$2" ]; then
    echo "FAIL: $3" >&2
    echo "  expected: $1" >&2
    echo "  actual:   $2" >&2
    H_FAILS=$((H_FAILS+1))
  fi
}

h_assert_contains() {
  case "$1" in
    *"$2"*) ;;
    *) echo "FAIL: $3" >&2; echo "  missing: $2" >&2; echo "  in: $1" >&2; H_FAILS=$((H_FAILS+1)) ;;
  esac
}

h_assert_ok() {
  "$@" || { echo "FAIL: expected success: $*" >&2; H_FAILS=$((H_FAILS+1)); }
}

h_assert_fails() {
  if "$@"; then echo "FAIL: expected failure: $*" >&2; H_FAILS=$((H_FAILS+1)); fi
}

h_assert_absent() {
  if [ -e "$1" ] || [ -L "$1" ]; then echo "FAIL: $2" >&2; echo "  present: $1" >&2; H_FAILS=$((H_FAILS+1)); fi
}
