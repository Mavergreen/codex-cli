#!/bin/sh
# platform: macOS-only -- drives tests/browser-login-test.sh, whose own platform is macOS
# spec: tests/browser-login-test.sh header -- the smoke a rebuilt codex must pass before a person signs
#       in with it. Here it runs against fake `codex` programs (perl), never a real browser or a real
#       account, to check every way it must fail, and that it never touches a listener it does not
#       own or the real CODEX_HOME.
#   usage: sh tests/browser-login-smoke-test.sh
set -eu
. "$(dirname "$0")/lib/harness.sh"
h_setup
SMOKE="$H_REPO/tests/browser-login-test.sh"
# a free port for this run, the fake's login server and the smoke's port check alike
PORT=$(perl -MIO::Socket::INET -e 'my $s = IO::Socket::INET->new(Listen => 1, LocalAddr => "127.0.0.1", LocalPort => 0) or die; print $s->sockport')
CODEX_BROWSER_LOGIN_PORT=$PORT
CODEX_BROWSER_LOGIN_WAIT=60   # a loaded host can take seconds to start perl; only the timeout case waits less
export CODEX_BROWSER_LOGIN_PORT CODEX_BROWSER_LOGIN_WAIT
unset CODEX_BROWSER_LOGIN_BINARY

# fake NAME BEHAVIOR: an executable $H/NAME/codex; BEHAVIOR is one of
#   serve     announce the login server, answer every request 404, record its pid
#   abort     die of SIGABRT before announcing, as 0.165.0 did
#   silent    stay up, never announce
#   mute      announce, accept connections, never answer
#   auth      announce and serve, and write CODEX_HOME/auth.json
#   realhome  announce and serve, and write $HOME/.codex/auth.json
fake() {
  mkdir -p "$H/$1"
  cat > "$H/$1/codex" <<EOF
#!/usr/bin/perl
use strict; use warnings; use IO::Socket::INET;
my \$b = "$2";
open my \$p, ">", "$H/$1/pid"; print \$p "\$\$\\n"; close \$p;
\$ARGV[0] eq "login" or die "not login";
if (\$b eq "abort") { kill "ABRT", \$\$; sleep 5; exit 0 }
if (\$b eq "silent") { sleep 60; exit 0 }
my \$s = IO::Socket::INET->new(Listen => 5, LocalAddr => "127.0.0.1", LocalPort => \$ENV{CODEX_BROWSER_LOGIN_PORT}, ReuseAddr => 1) or die "listen: \$!";
if (\$b eq "auth") { open my \$a, ">", "\$ENV{CODEX_HOME}/auth.json"; close \$a }
if (\$b eq "realhome") { mkdir "\$ENV{HOME}/.codex"; open my \$a, ">", "\$ENV{HOME}/.codex/auth.json"; close \$a }
\$| = 1; select STDERR; \$| = 1;
print STDERR "Starting local login server on http://localhost:\$ENV{CODEX_BROWSER_LOGIN_PORT}.\\n";
my @held;
while (my \$c = \$s->accept) {
  if (\$b eq "mute") { push @held, \$c; next }
  my \$l = <\$c>;
  print \$c "HTTP/1.1 404 Not Found\\r\\nContent-Length: 0\\r\\nConnection: close\\r\\n\\r\\n"; close \$c;
}
EOF
  chmod 0755 "$H/$1/codex"
}
# smoke NAME: run the smoke against $H/NAME/codex; sets $rc and $out
smoke() { rc=0; out="$(sh "$SMOKE" "$H/$1/codex" 2>&1)" || rc=$?; }
gone() { pid=$(cat "$H/$1/pid" 2>/dev/null || echo); [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; }

rc=0; sh "$SMOKE" >/dev/null 2>&1 || rc=$?
h_assert_eq 77 "$rc" "with no binary named, the smoke is skipped"

fake good serve; smoke good
h_assert_eq 0 "$rc" "a codex whose login server waits passes: $out"
h_assert_contains "$out" "authentication not tested" "a pass says what it does not prove"
h_assert_ok gone good

fake crash abort; smoke crash
h_assert_eq 1 "$rc" "a codex that aborts fails"
h_assert_contains "$out" "exited (status 134" "the abort is reported as the exit, not a timeout"

fake slow silent; CODEX_BROWSER_LOGIN_WAIT=3; smoke slow; CODEX_BROWSER_LOGIN_WAIT=60
h_assert_eq 1 "$rc" "a codex that never starts its login server fails"
h_assert_contains "$out" "no login server within 3s" "says it timed out waiting"
h_assert_ok gone slow

fake hang mute; smoke hang
h_assert_eq 1 "$rc" "a login server that never answers fails"
h_assert_contains "$out" "did not answer" "says the callback did not answer"
h_assert_ok gone hang

fake writer auth; smoke writer
h_assert_eq 1 "$rc" "a smoke that wrote credentials fails"
h_assert_contains "$out" "wrote credentials" "says it wrote credentials"

fake stray realhome; smoke stray
h_assert_eq 1 "$rc" "a codex that touched the real CODEX_HOME fails"
h_assert_contains "$out" "real CODEX_HOME" "says the real CODEX_HOME changed"

# someone else's listener on the login port: refused, and left running
perl -MIO::Socket::INET -e 'my $s = IO::Socket::INET->new(Listen => 1, LocalAddr => "127.0.0.1", LocalPort => $ARGV[0], ReuseAddr => 1) or die; alarm 30; while (my $c = $s->accept) { close $c }' "$PORT" &
other=$!
i=0; while [ $i -lt 300 ] && ! nc -z 127.0.0.1 "$PORT" >/dev/null 2>&1; do sleep 0.1; i=$((i+1)); done
fake busy serve; smoke busy
h_assert_eq 1 "$rc" "an occupied login port fails"
h_assert_contains "$out" "already in use" "says the port is taken"
h_assert_ok kill -0 "$other"
h_assert_eq "" "$(cat "$H/busy/pid" 2>/dev/null || true)" "codex is not started while the port is taken"
kill "$other" 2>/dev/null || :; wait "$other" 2>/dev/null || :
# without nc the port cannot be checked, so the smoke refuses rather than skip the check
mkdir -p "$H/nonc"; for t in sh uname mktemp env grep awk sleep cat rm mkdir stat curl perl kill; do p=$(command -v $t) && ln -s "$p" "$H/nonc/$t"; done
fake nonc-codex serve
rc=0; out="$(PATH="$H/nonc" sh "$SMOKE" "$H/nonc-codex/codex" 2>&1)" || rc=$?
h_assert_eq 1 "$rc" "no nc: the smoke fails"
h_assert_contains "$out" "needs nc" "says it needs nc"
h_done
