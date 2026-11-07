#!/bin/sh
# platform: macOS-only -- runtime smoke of a real Codex binary, not a launcher fixture.
# Usage: sh tests/browser-login-test.sh /absolute/path/to/bin/codex
#        (or CODEX_BROWSER_LOGIN_BINARY=...; with neither it is skipped, exit 77)
# Opens the real browser sign-in page; does not authenticate. Catches the post-10.9 NSWorkspace
# launch selector abort, which symbol checks cannot detect.
#   - CODEX_HOME is a new temporary directory: no credential is read, and any credential file
#     written there fails the smoke (nothing in it is read or printed). The real CODEX_HOME
#     (CODEX_HOME, else ~/.codex) must have the same auth.json and config.toml afterwards.
#   - The login port (CODEX_BROWSER_LOGIN_PORT, 1455 as Codex uses) must be free before codex
#     starts: a listener there is someone else's, and is never touched.
#   - codex must announce its login server within CODEX_BROWSER_LOGIN_WAIT seconds (20), and the
#     server must answer an unknown path 404 within 5 seconds. A crash is reported as its exit.
#   - The codex it started, and only that, is stopped on every exit.
# PASS means browser launch returned and the callback server waits; it says nothing of sign-in,
# token exchange or a turn, which a person checks with a private CODEX_HOME.
set -eu
[ "$(uname -s)" = Darwin ] || exit 77
CODEX=${1:-${CODEX_BROWSER_LOGIN_BINARY:-}}
[ -n "$CODEX" ] || { echo 'SKIP: set CODEX_BROWSER_LOGIN_BINARY to opt into opening the real browser'; exit 77; }
case "$CODEX" in /*) ;; *) echo 'use an absolute path to the real Codex binary' >&2; exit 1 ;; esac
[ -x "$CODEX" ] || { echo "not executable: $CODEX" >&2; exit 1; }
PORT=${CODEX_BROWSER_LOGIN_PORT:-1455}
WAIT=${CODEX_BROWSER_LOGIN_WAIT:-20}
REAL_HOME=${CODEX_HOME:-$HOME/.codex}
fail() { echo "FAIL: $*" >&2; exit 1; }
# fingerprint: the real CODEX_HOME's credential and config files, by metadata only (never content)
fingerprint() {
  for f in auth.json config.toml; do
    if [ -e "$REAL_HOME/$f" ]; then stat -f "$f %i %z %m" "$REAL_HOME/$f"; else echo "$f absent"; fi
  done
}
T=$(mktemp -d "${TMPDIR:-/tmp}/codex-browser-login.XXXXXX")
pid=
cleanup() {
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || :
    i=0; while [ $i -lt 30 ] && kill -0 "$pid" 2>/dev/null; do sleep 0.1; i=$((i+1)); done
    kill -9 "$pid" 2>/dev/null || :
  fi
  [ -z "$pid" ] || wait "$pid" 2>/dev/null || :
  rm -rf "$T"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

! nc -z 127.0.0.1 "$PORT" >/dev/null 2>&1 || fail "the login port $PORT is already in use by another process; it is left alone"
before=$(fingerprint)
# Disable crash dumps; the failing release aborts before printing the browser URL.
ulimit -c 0
mkdir -p "$T/home"
# in a subshell, so the shell does not report the job's own death on stderr
( exec env CODEX_HOME="$T/home" "$CODEX" login >"$T/out" 2>"$T/err" ) &
pid=$!
ANNOUNCE='Starting local login server on http://localhost:'
i=0
while [ "$i" -lt $((WAIT * 10)) ]; do
  grep -q "$ANNOUNCE" "$T/err" && break
  kill -0 "$pid" 2>/dev/null || break
  sleep 0.1
  i=$((i+1))
done
if ! grep -q "$ANNOUNCE" "$T/err"; then
  kill -0 "$pid" 2>/dev/null && fail "no login server within ${WAIT}s"
  st=0; wait "$pid" 2>/dev/null || st=$?; pid=
  cat "$T/err" >&2
  fail "login exited (status $st) before its login server started: browser launch did not return"
fi
port=$(awk -F: -v a="$ANNOUNCE" 'index($0, a) { sub(/[^0-9].*/, "", $NF); print $NF; exit }' "$T/err")
# A real HTTP response proves the callback loop is running after browser launch returns.
# An unknown path must not finish login or write credentials.
status=$(curl -s -o "$T/response" -w '%{http_code}' --max-time 5 "http://127.0.0.1:$port/mavergreen-login-smoke") || :
[ "$status" = 404 ] || fail "the login callback server on port $port did not answer 404 within 5s (HTTP ${status:-none})"
kill -0 "$pid" 2>/dev/null || fail "login exited after its callback server answered"
for f in auth.json .credentials.json; do
  [ ! -e "$T/home/$f" ] || fail "the smoke wrote credentials ($f) to its temporary CODEX_HOME"
done
[ "$(fingerprint)" = "$before" ] || fail "the real CODEX_HOME ($REAL_HOME) changed during the smoke"
printf '%s\n' 'PASS: browser launch returned and the login callback server is waiting (authentication not tested)'
