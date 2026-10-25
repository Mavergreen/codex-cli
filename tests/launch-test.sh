#!/bin/sh
# platform: macOS-only -- drives the launcher with 10.9's tar, curl, shasum and PlistBuddy
#   usage: sh tests/launch-test.sh
#          Seeds the standalone install from a file:// channel on first run, runs the installed build
#          afterwards, refuses a foreign build, survives two launches at once, honors CODEX_HOME,
#          claims ~/.local/bin/codex, and never opens the package's updater on a first run.
set -eu
. "$(dirname "$0")/lib/harness.sh"
. "$(dirname "$0")/lib/fixtures.sh"
[ -x /usr/libexec/PlistBuddy ] || exit 77
h_setup
MG="$H/root/usr/local/mavergreen"
T="$MG/codex-cli"
A=0.161.0-mavericks.1
RT=x86_64-apple-darwin
S="$HOME/.codex/packages/standalone"
LINK="$HOME/.local/bin/codex"

mkdir -p "$T" "$MG/bin" "$H/links"
cp -R "$H_REPO/tree/." "$T/"
# a fixed AquaTransport pin, so these tests do not depend on the package's; they are not about it
printf '2026.10.20\n' > "$T/share/codex-cli/aquatransport-min-version"
CODEX_AQUATRANSPORT_VERSION=2026.10.20
export CODEX_AQUATRANSPORT_VERSION
ln -s "$T/bin/codex" "$MG/bin/codex"
ln -s "$MG/bin/codex" "$H/links/codex"
for s in rg ed25519; do mkdir -p "$MG/$s"; : > "$MG/$s/mavergreen.plist"; done
h_fake_verify
# the launcher points the installer at its own tree: the tree's key, and a plist beside it
h_fake_pkg 20261017.1
cp "$CODEX_PKG_ROOT/mavergreen.plist" "$T/mavergreen.plist"
unset CODEX_PKG_ROOT
h_channel $A
GOOD_URL="$CODEX_BUILDS_URL"

launch() { "$H/links/codex" "$@" >"$H/out" 2>"$H/err" && rc=0 || rc=$?; }
fresh() { rm -rf "$HOME/.codex" "$HOME/.local" "$HOME/Library" "$H/other home"; CODEX_BUILDS_URL="$GOOD_URL"; export CODEX_BUILDS_URL; }
dead() { CODEX_BUILDS_URL="$(h_url "$H/no such channel")"; export CODEX_BUILDS_URL; }

# first run on an empty root
launch --help
h_assert_eq 0 "$rc" "first run exits 0 ($(cat "$H/err"))"
h_assert_contains "$(cat "$H/err")" "first run" "first run says so"
h_assert_eq "fake codex $A --help" "$(cat "$H/out")" "first run execs the seeded build with the arguments"
h_assert_eq "$S/releases/$A-$RT" "$(readlink "$S/current")" "current points at the release"

# second run: the channel is gone, the installer is not called
dead
cp "$T/libexec/codex-cli/install.sh" "$H/install.sh.real"
printf '#!/bin/sh\necho called >> "$HOME/installer-marker"\nexit 1\n' > "$T/libexec/codex-cli/install.sh"
launch again
h_assert_eq 0 "$rc" "second run exits 0 ($(cat "$H/err"))"
h_assert_eq "fake codex $A again" "$(cat "$H/out")" "second run execs the installed build"
h_assert_absent "$HOME/installer-marker" "a seeded root never calls the installer"
h_assert_eq "" "$(cat "$H/err")" "second run is silent"
cp "$H/install.sh.real" "$T/libexec/codex-cli/install.sh"

# first run with no channel
fresh; dead
launch
h_assert_eq 1 "$rc" "first run with an unreachable channel exits 1"
h_assert_contains "$(cat "$H/err")" "could not install Codex" "it says why"
h_assert_eq "" "$(cat "$H/out")" "nothing ran"

# a current release that is not our build is never run
fresh
OTHER="$S/releases/9.9.9-x86_64-apple-darwin"
mkdir -p "$OTHER/bin"
printf '#!/bin/sh\necho other codex\n' > "$OTHER/bin/codex"
chmod +x "$OTHER/bin/codex"
printf '{"layoutVersion":1,"version":"9.9.9"}\n' > "$OTHER/codex-package.json"
ln -s "$OTHER" "$S/current"
launch --x
h_assert_eq 0 "$rc" "a foreign current is replaced ($(cat "$H/err"))"
h_assert_eq "fake codex $A --x" "$(cat "$H/out")" "our build runs, never the other one"

# two launches together, with the overlap forced: the first installer is held inside its lock (its
# staged codex --version waits at a gate) until the second installer has started and had time to queue
fresh
cp "$T/libexec/codex-cli/install.sh" "$H/install.sh.real"
mv "$T/libexec/codex-cli/install.sh" "$T/libexec/codex-cli/install-real.sh"
cat > "$T/libexec/codex-cli/install.sh" <<'WRAP'
#!/bin/sh
echo started >> "$H/installer-starts"
exec /bin/sh "$(dirname "$0")/install-real.sh" "$@"
WRAP
rm -f "$H/installer-starts" "$H/gate" "$H/gate.in"
: > "$H/gate"
CODEX_TEST_GATE="$H/gate"
export CODEX_TEST_GATE
"$H/links/codex" one >"$H/out1" 2>"$H/err1" & p1=$!
i=0
while [ ! -e "$H/gate.in" ] && [ "$i" -lt 300 ]; do sleep 0.1; i=$((i+1)); done
h_assert_ok test -e "$H/gate.in"
"$H/links/codex" two >"$H/out2" 2>"$H/err2" & p2=$!
i=0
while [ "$(wc -l < "$H/installer-starts" 2>/dev/null | tr -d ' ')" != 2 ] && [ "$i" -lt 300 ]; do sleep 0.1; i=$((i+1)); done
sleep 2
h_assert_eq 2 "$(wc -l < "$H/installer-starts" | tr -d ' ')" "both installers started"
h_assert_absent "$S/current" "the first install is still held inside its lock"
kill -0 $p2 || { echo "FAIL: the second launch ended while the first held the lock" >&2; H_FAILS=$((H_FAILS+1)); }
rm -f "$H/gate"
rc1=0; rc2=0
wait $p1 || rc1=$?
wait $p2 || rc2=$?
unset CODEX_TEST_GATE
h_assert_eq 0 "$rc1" "the first of two launches exits 0 ($(cat "$H/err1"))"
h_assert_eq 0 "$rc2" "the second of two launches exits 0 ($(cat "$H/err2"))"
h_assert_eq "fake codex $A one" "$(cat "$H/out1")" "the first prints the build"
h_assert_eq "fake codex $A two" "$(cat "$H/out2")" "the second prints the same build"
h_assert_eq "" "$(ls -A "$S/releases" | grep '^\.staging' || true)" "no staging entries remain"
h_assert_eq "$A-$RT" "$(ls "$S/releases")" "exactly one release"
rm -f "$T/libexec/codex-cli/install-real.sh"
cp "$H/install.sh.real" "$T/libexec/codex-cli/install.sh"

# a foreign current, with our release for the channel's latest already on disk: current still moves
fresh
launch
h_assert_eq 0 "$rc" "seed ($(cat "$H/err"))"
OTHER="$S/releases/9.9.9-x86_64-apple-darwin"
mkdir -p "$OTHER/bin"
printf '#!/bin/sh\necho other codex\n' > "$OTHER/bin/codex"
chmod +x "$OTHER/bin/codex"
printf '{"layoutVersion":1,"version":"9.9.9"}\n' > "$OTHER/codex-package.json"
rm "$S/current"
ln -s "$OTHER" "$S/current"
launch --y
h_assert_eq 0 "$rc" "reseed with our release already on disk ($(cat "$H/err"))"
h_assert_eq "fake codex $A --y" "$(cat "$H/out")" "our build runs"
h_assert_eq "$S/releases/$A-$RT" "$(readlink "$S/current")" "current moved off the foreign release"

# CODEX_HOME with a space
fresh
CODEX_HOME="$H/other home"
export CODEX_HOME
launch go
h_assert_eq 0 "$rc" "CODEX_HOME run exits 0 ($(cat "$H/err"))"
h_assert_ok test -x "$H/other home/packages/standalone/current/bin/codex"
h_assert_absent "$HOME/.codex" "nothing under ~/.codex"
CODEX_HOME=relative/dir
launch
h_assert_eq 1 "$rc" "a relative CODEX_HOME is refused"
h_assert_contains "$(cat "$H/err")" "CODEX_HOME must be an absolute path" "and says so"
unset CODEX_HOME

# the ~/.local/bin/codex link
fresh
launch
h_assert_eq "$MG/bin/codex" "$(readlink "$LINK")" "an absent link is claimed"
launch
h_assert_eq "$MG/bin/codex" "$(readlink "$LINK")" "and stays"
rm "$LINK"
ln -s "$HOME/.codex/packages/standalone/current/bin/codex" "$LINK"
launch
h_assert_eq "$MG/bin/codex" "$(readlink "$LINK")" "upstream's own link is replaced"
rm "$LINK"
ln -s "$H/elsewhere" "$LINK"
launch
h_assert_eq "$H/elsewhere" "$(readlink "$LINK")" "another link is left alone"
h_assert_contains "$(cat "$H/err")" "is not this launcher's and is left alone" "the note appears on the first run"
launch
h_assert_eq "" "$(cat "$H/err")" "and not again"
rm "$LINK"
printf 'plain\n' > "$LINK"
rm -rf "$HOME/Library"
launch
h_assert_eq "plain" "$(cat "$LINK")" "a regular file is left alone"
h_assert_contains "$(cat "$H/err")" "left alone" "and noted"

# a first run whose build needs a newer pkg installs nothing and never opens the package's updater,
# even with somebody at a tty
fresh
h_fake_open
h_channel 0.161.0-mavericks.2 20991231.1
GOOD_URL="$CODEX_BUILDS_URL"
rm -f "$H/open-calls"
CODEX_INSTALL_ASSUME_TTY=1 launch
h_assert_eq 1 "$rc" "a first run that needs a newer pkg exits 1"
h_assert_contains "$(cat "$H/err")" "could not install Codex" "it says Codex was not installed"
h_assert_contains "$(cat "$H/err")" "needs a newer codex-cli package" "and why"
h_assert_contains "$(cat "$H/err")" "with its updater (/Library/Application Support/Mavergreen/codex-cli-updater.app) or from https://github.com/Mavergreen/codex-cli/releases/latest" "and how to get a newer package"
h_assert_absent "$H/open-calls" "the first run never opens the package's updater"
h_assert_absent "$S/current" "nothing was installed"
h_done
