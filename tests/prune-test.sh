#!/bin/sh
# platform: macOS-only -- drives the package's installer with 10.9's tar, curl, shasum and PlistBuddy
#   usage: sh tests/prune-test.sh
#          After it moves current, the installer keeps the new release and the one current left, and
#          removes older releases; it never removes one the app-server daemon's current resolves into
#          or anything that is not a release; a daemon-only install prunes nothing.
set -eu
. "$(dirname "$0")/lib/harness.sh"
. "$(dirname "$0")/lib/fixtures.sh"
[ -x /usr/libexec/PlistBuddy ] || exit 77
h_setup
I="$H_REPO/tree/libexec/codex-cli/install.sh"
CODEX_HOME="$H/codex home"
export CODEX_HOME
CODEX_INSTALL_ASSUME_TTY=1
export CODEX_INSTALL_ASSUME_TTY
S="$CODEX_HOME/packages/standalone"
CV=$(sh "$H_REPO/build/codex-pin.sh" version)
A=$CV-mavericks.1
B=$CV-mavericks.2
C=$CV-mavericks.3
D=$CV-mavericks.4
RT=x86_64-apple-darwin

h_fake_verify
h_fake_pkg 20261017.1
h_fake_open

run() {
  rc=0
  out="$(sh "$I" "$@" 2>&1 </dev/null)" || rc=$?
}
releases() { ls "$S/releases" 2>/dev/null | tr '\n' ' '; }

h_channel $A; run
h_channel $B; run
h_assert_eq "$A-$RT $B-$RT " "$(releases)" "two releases are both kept"

# a third update removes the oldest; a directory that is not a release stays
mkdir -p "$S/releases/notes"
h_channel $C; run
h_assert_eq 0 "$rc" "the update exits 0 ($out)"
h_assert_eq "$B-$RT $C-$RT notes " "$(releases)" "the oldest release is removed, the one current left is kept"
rm -rf "$S/releases/notes"

# pinning back keeps the release it leaves
run --release $B
h_assert_eq "$B-$RT $C-$RT " "$(releases)" "a pin back keeps both"

# a release the app-server daemon's current resolves into stays
DR="$CODEX_HOME/packages/app-server-daemon"
mkdir -p "$DR"
ln -s "$S/releases/$B-$RT" "$DR/current"
h_channel $D; run
run --release $C
h_assert_eq "$B-$RT $C-$RT $D-$RT " "$(releases)" "the daemon's release stays though neither current nor previous"
rm -f "$DR/current"

# a daemon-only install prunes nothing in its own root
CODEX_INSTALL_DAEMON_ONLY=1 run --release $D
h_assert_eq "$B-$RT $C-$RT $D-$RT " "$(releases)" "the standalone root is untouched by a daemon-only install"

h_done
