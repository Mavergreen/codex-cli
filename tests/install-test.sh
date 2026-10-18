#!/bin/sh
# platform: macOS-only -- drives the package's installer with 10.9's tar, curl, shasum and PlistBuddy
#   usage: sh tests/install-test.sh
#          Installs fake builds from a file:// channel under a path with a space: fresh install, update,
#          pinned older ID, reinstall, refused signature, wrong digest, unreachable channel, pkg too old
#          (interactive and guarded), unset CODEX_HOME, codex-path/rg as upstream handles it, and real signatures
#          when ed25519-verify is installed.
set -eu
. "$(dirname "$0")/lib/harness.sh"
. "$(dirname "$0")/lib/fixtures.sh"
[ -x /usr/libexec/PlistBuddy ] || exit 77
h_setup
I="$H_REPO/tree/libexec/codex-cli/install.sh"
CODEX_HOME="$H/codex home"
export CODEX_HOME
# the runs below are interactive unless a test says otherwise (there may be no tty here)
CODEX_INSTALL_ASSUME_TTY=1
export CODEX_INSTALL_ASSUME_TTY
S="$CODEX_HOME/packages/standalone"
A=0.161.0-mavericks.1
B=0.161.0-mavericks.2
RT=x86_64-apple-darwin

h_fake_verify
h_fake_pkg 20261017.1
h_fake_open

# run the installer; leaves its status in $rc and its output in $out
run() {
  rc=0
  out="$(sh "$I" "$@" 2>&1 </dev/null)" || rc=$?
}
cur() { readlink "$S/current" 2>/dev/null || true; }
releases() { ls "$S/releases" 2>/dev/null | tr '\n' ' '; }

# fresh install of latest
h_channel $A
run
h_assert_eq 0 "$rc" "a fresh install exits 0 ($out)"
h_assert_eq "fake codex $A" "$("$S/current/bin/codex")" "current runs the installed build"
h_assert_ok test -d "$S/releases/$A-$RT"
h_assert_eq "$S/releases/$A-$RT" "$(cur)" "current points at the release"
h_assert_absent "$HOME/.local/bin/codex" "the installer leaves ~/.local/bin/codex to the launcher"
h_assert_absent "$HOME/.local" "the installer makes no ~/.local"
h_assert_eq "" "$(ls -A "$HOME" | grep -v '^\.codex$' || true)" "nothing but .codex or CODEX_HOME written under HOME, no shell profile"
h_assert_contains "$(cat "$H/verify-calls")" "fake-public-key|" "the signature was checked against the pkg key"
h_assert_eq "" "$(ls -A "$S/releases" | grep '^\.staging' || true)" "no staging debris"

# a newer latest moves current; the old release stays
h_channel $B
run
h_assert_eq 0 "$rc" "an update exits 0 ($out)"
h_assert_eq "$S/releases/$B-$RT" "$(cur)" "current moves to the newer build"
h_assert_ok test -d "$S/releases/$A-$RT"
h_assert_eq "fake codex $B" "$("$S/current/bin/codex")" "current runs the newer build"

# --release pins back. The current link moves in one rename even where mv has neither -T nor -h, as
# on 10.9: this mv refuses both, as 10.9's does, and records any other move onto current
mkdir -p "$H/mvbin"
cat > "$H/mvbin/mv" <<EOF
#!/bin/sh
case "\$1" in -Tf|-hf) exit 1 ;; esac
for a in "\$@"; do case "\$a" in */current) printf '%s\n' "\$*" >> '$H/mv-onto-current' ;; esac; done
exec /bin/mv "\$@"
EOF
chmod +x "$H/mvbin/mv"
rc=0; out="$(PATH="$H/mvbin:$PATH" sh "$I" --release $A 2>&1 </dev/null)" || rc=$?
h_assert_eq 0 "$rc" "installing a named older build exits 0 ($out)"
h_assert_eq "$S/releases/$A-$RT" "$(cur)" "current is back on the older build"
h_assert_eq "" "$(cat "$H/mv-onto-current" 2>/dev/null || true)" "current was renamed into place, never removed and then moved"

# the same ID twice
run --release $A
h_assert_eq 0 "$rc" "installing the current build again exits 0"
h_assert_eq "$S/releases/$A-$RT" "$(cur)" "current is unchanged"
h_assert_contains "$out" "already installed" "the output names it as already installed"

# a signature that does not verify
before="$(releases)"
printf 'bad\n' > "$H/channel/latest.json.sig"
printf 'bad\n' > "$H/channel/codex-build-$B.json.sig"
run
h_assert_eq 1 "$rc" "an unverified signature exits 1"
h_assert_contains "$out" "does not verify" "the refusal says why"
h_assert_contains "$out" "try again in a minute" "the refusal allows for a fetch during a publish"
h_assert_eq "$before" "$(releases)" "nothing new under releases"
h_assert_eq "$S/releases/$A-$RT" "$(cur)" "current is unchanged by a refused signature"
run --release $B
h_assert_eq 1 "$rc" "a named build with a bad signature exits 1"
h_resign "$H/channel/latest.json"
h_resign "$H/channel/codex-build-$B.json"

# metadata changed after it was signed: the signature is for other bytes
cp "$H/channel/latest.json" "$H/latest.json.orig"
printf ' ' >> "$H/channel/latest.json"
run
h_assert_eq 1 "$rc" "metadata that differs from what was signed exits 1"
h_assert_contains "$out" "does not verify" "a changed JSON is refused by the signature"
h_assert_eq "$S/releases/$A-$RT" "$(cur)" "current is unchanged by a tampered JSON"
cp "$H/latest.json.orig" "$H/channel/latest.json"

# missing or unusable verification inputs refuse too, and install nothing
before="$(releases)"
mv "$CODEX_PKG_ROOT/share/codex-cli/ed25519_key.pub" "$H/key.away"
run
h_assert_eq 1 "$rc" "a missing public key exits 1"
mv "$H/key.away" "$CODEX_PKG_ROOT/share/codex-cli/ed25519_key.pub"
good_verify="$CODEX_ED25519_VERIFY"
CODEX_ED25519_VERIFY="$H/bin/no such verifier"
export CODEX_ED25519_VERIFY
run
h_assert_eq 1 "$rc" "a missing verifier exits 1"
cp "$good_verify" "$H/bin/plain file"
chmod 0644 "$H/bin/plain file"
CODEX_ED25519_VERIFY="$H/bin/plain file"
run
h_assert_eq 1 "$rc" "a non-executable verifier exits 1"
CODEX_ED25519_VERIFY="$good_verify"
export CODEX_ED25519_VERIFY
h_assert_eq "$before" "$(releases)" "nothing was installed without a verifiable signature"
h_assert_eq "$S/releases/$A-$RT" "$(cur)" "current is unchanged without verification inputs"

# a missing signature file refuses too
mv "$H/channel/latest.json.sig" "$H/channel/latest.json.sig.away"
run
h_assert_eq 1 "$rc" "a missing signature exits 1"
h_assert_eq "$S/releases/$A-$RT" "$(cur)" "current is unchanged without a signature"
mv "$H/channel/latest.json.sig.away" "$H/channel/latest.json.sig"

# a tarball whose sha256 differs from the JSON's
C=0.161.0-mavericks.3
h_channel $C
zeros=0000000000000000000000000000000000000000000000000000000000000000
sed "s/sha256:[0-9a-f]*/sha256:$zeros/" "$H/channel/codex-build-$C.json" > "$H/x.json"
h_assert_ok test -n "$(grep "sha256:$zeros" "$H/x.json")"
cp "$H/x.json" "$H/channel/codex-build-$C.json"
cp "$H/x.json" "$H/channel/latest.json"
h_resign "$H/channel/codex-build-$C.json"
h_resign "$H/channel/latest.json"
run
h_assert_eq 1 "$rc" "a wrong digest exits 1"
h_assert_eq "$S/releases/$A-$RT" "$(cur)" "current is unchanged by a wrong digest"
h_assert_eq "" "$(ls -A "$S/releases" | grep '^\.staging' || true)" "no staging debris after a wrong digest"
h_assert_absent "$S/releases/$C-$RT" "the corrupt build is not installed"

# an unreachable channel
CODEX_BUILDS_URL=file:///nonexistent
export CODEX_BUILDS_URL
run
h_assert_eq 1 "$rc" "an unreachable channel exits 1"
h_assert_eq "$S/releases/$A-$RT" "$(cur)" "current is unchanged by an unreachable channel"
CODEX_BUILDS_URL="$(h_url "$H/channel")"
export CODEX_BUILDS_URL

# a build that needs a newer pkg
D=0.161.0-mavericks.4
h_channel $D 20261101.1
run
h_assert_eq 3 "$rc" "an old pkg exits 3 ($out)"
h_assert_contains "$out" "needs a newer codex-cli package" "the output says the pkg must be updated"
h_assert_contains "$out" "opening its updater" "the interactive run says it opens the updater"
h_assert_eq "1" "$(wc -l < "$H/open-calls" | tr -d ' ')" "the updater was opened once"
h_assert_eq "--args --user" "$(cat "$H/open-calls")" "the updater open command ran"
h_assert_eq "$S/releases/$A-$RT" "$(cur)" "current is unchanged when the pkg is too old"
h_assert_absent "$S/releases/$D-$RT" "nothing was installed when the pkg is too old"
# `codex update` runs the installer with CODEX_NON_INTERACTIVE=1 while somebody watches: that only
# suppresses prompts, so the updater still opens
rm -f "$H/open-calls"
rc=0; out="$(CODEX_NON_INTERACTIVE=1 sh "$I" 2>&1 </dev/null)" || rc=$?
h_assert_eq 3 "$rc" "CODEX_NON_INTERACTIVE=1 with a tty exits 3 ($out)"
h_assert_contains "$out" "opening its updater" "CODEX_NON_INTERACTIVE=1 with a tty says it opens the updater"
h_assert_eq "--args --user" "$(cat "$H/open-calls" 2>/dev/null)" "CODEX_NON_INTERACTIVE=1 with a tty opens the updater"
# the same, in a guarded run (CODEX_INSTALL_NO_UPDATER=1, as the launcher's first run): logged, exit 3, nothing opened
rm -f "$H/open-calls"
rc=0; out="$(CODEX_NON_INTERACTIVE=1 CODEX_INSTALL_NO_UPDATER=1 sh "$I" 2>&1 </dev/null)" || rc=$?
h_assert_eq 3 "$rc" "a guarded run with an old pkg exits 3 ($out)"
h_assert_contains "$out" "needs a newer codex-cli package" "a guarded run logs it"
h_assert_contains "$out" "or from https://github.com/Mavergreen/codex-cli/releases/latest" "a guarded run says where the newer package is"
h_assert_absent "$H/open-calls" "a guarded run opens nothing"
# the date compares before N, and both compare numerically
h_fake_pkg 20261101.2
run
h_assert_eq 0 "$rc" "a pkg at 20261101.2 satisfies 20261101.1 ($out)"
h_assert_eq "$S/releases/$D-$RT" "$(cur)" "the build installs once the pkg is new enough"
E=0.161.0-mavericks.5
h_channel $E 20261101.10
h_fake_pkg 20261101.9
run
h_assert_eq 3 "$rc" "N compares numerically: .9 is older than .10"
h_fake_pkg 20261101.10
run
h_assert_eq 0 "$rc" "N compares numerically: .10 satisfies .10 ($out)"
h_fake_pkg 20270101.1
h_channel $E 20261101.10
run --release $E
h_assert_eq 0 "$rc" "a later date satisfies an earlier one"
# an unreadable pkg version is older than any non-empty min-pkg
F=0.161.0-mavericks.6
h_channel $F 20200101.1
rm "$CODEX_PKG_ROOT/mavergreen.plist"
run
h_assert_eq 3 "$rc" "a missing plist is older than any min-pkg ($out)"
h_assert_contains "$out" "needs a newer codex-cli package" "the missing plist is reported as needing an update"
# an empty min-pkg needs no pkg at all
h_channel $F
run
h_assert_eq 0 "$rc" "an empty min-pkg installs without a plist ($out)"

# codex-path/rg is a script that runs the rg package's rg: as upstream, the installer makes it
# executable and requires it, and it never needs the rg package to install
repack() {
  # repack ID: re-tars $H/repack (the channel's build ID, extracted by unpack, then changed) and re-signs
  (cd "$H/repack" && COPYFILE_DISABLE=1 tar -czf "$H/channel/codex-package-x86_64-apple-darwin-$1.tar.gz" codex-package.json bin codex-resources codex-path LICENSE NOTICE build-manifest)
  _r_sha="$(shasum -a 256 "$H/channel/codex-package-x86_64-apple-darwin-$1.tar.gz" | awk '{print $1}')"
  sed "s/sha256:[0-9a-f]*/sha256:$_r_sha/" "$H/channel/codex-build-$1.json" > "$H/x.json"
  cp "$H/x.json" "$H/channel/codex-build-$1.json"
  cp "$H/x.json" "$H/channel/latest.json"
  h_resign "$H/channel/codex-build-$1.json"
  h_resign "$H/channel/latest.json"
}
unpack() {
  rm -rf "$H/repack"
  mkdir "$H/repack"
  tar -xzf "$H/channel/codex-package-x86_64-apple-darwin-$1.tar.gz" -C "$H/repack"
}
G=0.161.0-mavericks.7
h_channel $G
unpack $G
chmod 0644 "$H/repack/codex-path/rg"
repack $G
run
h_assert_eq 0 "$rc" "a build whose rg script is not executable installs ($out)"
h_assert_eq "$S/releases/$G-$RT" "$(cur)" "current moves to that build"
h_assert_eq "" "$(find "$S/releases/$G-$RT/codex-path" -type l)" "codex-path/rg is installed as a file, not a link"
h_assert_eq 755 "$(stat -f %Lp "$S/releases/$G-$RT/codex-path/rg")" "the installer makes codex-path/rg executable"
h_assert_ok cmp "$H/repack/codex-path/rg" "$S/releases/$G-$RT/codex-path/rg"
G2=0.161.0-mavericks.8
h_channel $G2
unpack $G2
rm "$H/repack/codex-path/rg"
repack $G2
before_cur="$(cur)"
run
h_assert_eq 1 "$rc" "a build without codex-path/rg is refused ($out)"
h_assert_eq "$before_cur" "$(cur)" "current is unchanged by a build without codex-path/rg"

# a build whose codex reports another x.y.z is refused
V=0.161.0-mavericks.9
h_channel $V
unpack $V
printf '#!/bin/sh\necho "codex-cli 0.160.0"\n' > "$H/repack/bin/codex"
repack $V
run
h_assert_eq 1 "$rc" "a build reporting another Codex version exits 1"
h_assert_contains "$out" "did not report expected version" "the refusal says why"
h_assert_eq "$before_cur" "$(cur)" "current is unchanged by a build with the wrong version"

# an overflowing, short or odd min-pkg refuses
for bad in 99999999999999999999.1 2026101.1 20261017.12345 20261017 abcdefgh.1 ; do
  h_channel 0.161.0-mavericks.10 "$bad"
  run
  h_assert_eq 1 "$rc" "min-pkg $bad exits 1 ($out)"
  h_assert_eq "$before_cur" "$(cur)" "min-pkg $bad leaves current alone"
done

# a guarded run, or one with no tty, opens nothing; interactive-looking runs open the updater
h_channel 0.161.0-mavericks.11 99999999.1
h_fake_pkg 20261017.1
rm -f "$H/open-calls"
if ( : </dev/tty ) 2>/dev/null; then
  echo "note: no-tty case skipped, this run has a usable /dev/tty"
else
  rc=0; out="$(CODEX_INSTALL_ASSUME_TTY= sh "$I" 2>&1 </dev/null)" || rc=$?
  h_assert_eq 3 "$rc" "a run with no tty exits 3 ($out)"
  h_assert_absent "$H/open-calls" "a run with no tty opens nothing"
fi
rc=0
out="$(CODEX_INSTALL_IF_LATEST=1 CODEX_UPDATE_FROM_RELEASE="$(cat "$S/auto-update-version")" sh "$I" 2>&1 </dev/null)" || rc=$?
h_assert_eq 3 "$rc" "a daemon-marked run with an old pkg exits 3 ($out)"
h_assert_absent "$H/open-calls" "a daemon-marked run opens nothing"
h_fake_pkg 20261017.1

# a missing plist is reported as such, not as PlistBuddy's complaint
h_channel 0.161.0-mavericks.12 20200101.1
rm "$CODEX_PKG_ROOT/mavergreen.plist"
run
h_assert_eq 3 "$rc" "a missing plist exits 3"
h_assert_contains "$out" "missing or unreadable" "the missing plist is named"
h_assert_eq "" "$(printf '%s' "$out" | grep "Will Create" || true)" "PlistBuddy's complaint is not shown as the version"
h_assert_absent "$CODEX_PKG_ROOT/mavergreen.plist" "a missing plist is not created"
h_assert_eq "" "$(printf '%s' "$out" | grep 'Resolved version\|Updating Codex' || true)" "no progress lines before exit 3"
h_fake_pkg 20261017.1

# the daemon's guarded modes: its own root, guards on release names, nothing opened
STD_HOME="$CODEX_HOME"
CODEX_HOME="$H/daemon home"
export CODEX_HOME
D="$CODEX_HOME/packages/app-server-daemon"
dcur() { readlink "$D/current" 2>/dev/null || true; }
h_channel $A
run_daemon() {
  rc=0
  out="$(CODEX_NON_INTERACTIVE=1 CODEX_INSTALL_DAEMON_ONLY=1 "$@" sh "$I" 2>&1 </dev/null)" || rc=$?
}
run_daemon env
h_assert_eq 0 "$rc" "a daemon-only install exits 0 ($out)"
h_assert_eq "$D/releases/$A-$RT" "$(dcur)" "daemon-only installs into packages/app-server-daemon"
h_assert_eq "$A-$RT" "$(cat "$D/auto-update-version")" "the auto-update-version record names the release"
h_assert_absent "$CODEX_HOME/packages/standalone" "daemon-only leaves packages/standalone alone"

# IF_LATEST naming another release than the selected one changes nothing
h_channel $B
run_daemon env CODEX_INSTALL_IF_LATEST=1 CODEX_UPDATE_FROM_RELEASE="$B-$RT"
h_assert_eq 0 "$rc" "a guarded update from another release exits 0 ($out)"
h_assert_eq "$D/releases/$A-$RT" "$(dcur)" "a guarded update from another release leaves current alone"
h_assert_absent "$D/releases/$B-$RT" "a guarded update from another release installs nothing"
# a record that no longer follows the channel stops a scheduled update
printf '%s' "something-else" > "$D/auto-update-version"
run_daemon env CODEX_INSTALL_IF_LATEST=1 CODEX_UPDATE_FROM_RELEASE="$A-$RT"
h_assert_eq 0 "$rc" "a release off the channel exits 0 ($out)"
h_assert_eq "$D/releases/$A-$RT" "$(dcur)" "a release off the channel is not updated"
printf '%s' "$A-$RT" > "$D/auto-update-version"
# IF_CURRENT with a changed selection fails
run_daemon env CODEX_INSTALL_IF_CURRENT=1 CODEX_UPDATE_FROM_RELEASE="$B-$RT"
h_assert_eq 1 "$rc" "IF_CURRENT with a changed selection exits 1"
h_assert_contains "$out" "Daemon selection changed" "IF_CURRENT says the selection changed"
# the matching release (our <ID>-x86_64-apple-darwin name) updates and moves the record
run_daemon env CODEX_INSTALL_IF_LATEST=1 CODEX_UPDATE_FROM_RELEASE="$A-$RT"
h_assert_eq 0 "$rc" "a guarded update from the selected release exits 0 ($out)"
h_assert_eq "$D/releases/$B-$RT" "$(dcur)" "the guarded update moves current"
h_assert_eq "$B-$RT" "$(cat "$D/auto-update-version")" "the record follows"

# a guarded run that hits the pkg requirement exits 3 and opens nothing, whichever marker guards it
# (CODEX_INSTALL_ASSUME_TTY=1 is set throughout: the markers alone must guard)
h_channel 0.161.0-mavericks.20 99999999.1
rm -f "$H/open-calls"
# (the IF_ guards need a selected release, so they run with DAEMON_ONLY as the daemon does; the others alone;
#  the last is the daemon's own environment, CODEX_NON_INTERACTIVE included)
for g in CODEX_INSTALL_NO_UPDATER=1 "CODEX_NON_INTERACTIVE=1 CODEX_INSTALL_NO_UPDATER=1" CODEX_INSTALL_DAEMON_ONLY=1 \
  "CODEX_INSTALL_IF_LATEST=1 CODEX_INSTALL_DAEMON_ONLY=1" "CODEX_INSTALL_IF_CURRENT=1 CODEX_INSTALL_DAEMON_ONLY=1" \
  "CODEX_NON_INTERACTIVE=1 CODEX_INSTALL_DAEMON_ONLY=1"; do
  rm -f "$H/open-calls"
  rc=0
  # shellcheck disable=SC2086 # $g holds one or two assignments
  out="$(env $g CODEX_UPDATE_FROM_RELEASE="$B-$RT" sh "$I" 2>&1 </dev/null)" || rc=$?
  h_assert_eq 3 "$rc" "$g with an old pkg exits 3 ($out)"
  h_assert_contains "$out" "needs a newer codex-cli package" "$g logs the pkg requirement"
  h_assert_absent "$H/open-calls" "$g never opens the updater"
done
rc=0
out="$(env CODEX_NON_INTERACTIVE=1 CODEX_UPDATE_FROM_RELEASE="$B-$RT" sh "$I" 2>&1 </dev/null)" || rc=$?
h_assert_eq 3 "$rc" "an unmarked run with a tty exits 3"
h_assert_contains "$out" "opening its updater" "an unmarked run with a tty opens the updater"
h_assert_ok test -f "$H/open-calls"
rm -f "$H/open-calls"

# the loop refuses an installer that lacks these names
for name in CODEX_INSTALL_IF_LATEST CODEX_INSTALL_IF_CURRENT CODEX_INSTALL_DAEMON_ONLY CODEX_INSTALL_DEFER_SELECTION CODEX_UPDATE_FROM_RELEASE auto-update-version packages/app-server-daemon; do
  h_assert_ok grep -q "$name" "$I"
done
CODEX_HOME="$STD_HOME"
h_fake_pkg 20261017.1

# CODEX_HOME unset: installs under ~/.codex
unset CODEX_HOME
h_channel $A
run
h_assert_eq 0 "$rc" "an install without CODEX_HOME exits 0 ($out)"
h_assert_eq "fake codex $A" "$("$HOME/.codex/packages/standalone/current/bin/codex")" "it installs under ~/.codex/packages/standalone"

# real signatures, when the verifier is installed
RV=/usr/local/mavergreen/ed25519/bin/ed25519-verify
if [ -x "$RV" ]; then
  CODEX_HOME="$H/real home"
  export CODEX_HOME
  RS="$CODEX_HOME/packages/standalone"
  unset CODEX_ED25519_VERIFY
  KG=/usr/local/mavergreen/ed25519/bin/ed25519-keygen
  SG=/usr/local/mavergreen/ed25519/bin/ed25519-sign
  h_channel $A
  "$KG" -f "$H/throwaway key" >/dev/null
  cp "$H/throwaway key.pub" "$CODEX_PKG_ROOT/share/codex-cli/ed25519_key.pub"
  "$SG" -f "$H/throwaway key" "$H/channel/latest.json" > "$H/channel/latest.json.sig"
  run
  h_assert_eq 0 "$rc" "a genuine signature verifies ($out)"
  h_assert_eq "fake codex $A" "$("$RS/current/bin/codex")" "the genuinely signed build installs"
  printf 'x' >> "$H/channel/latest.json"
  rm -rf "$RS"
  run
  h_assert_eq 1 "$rc" "one changed byte refuses"
  h_assert_contains "$out" "does not verify" "a changed byte is reported"
  h_assert_absent "$RS/current" "nothing is installed after a refused signature"
else
  echo "note: real-crypto case skipped, no ed25519-verify installed"
fi

h_done
