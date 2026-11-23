#!/bin/sh
# platform: macOS-only -- drives the launcher with 10.9's tar, curl and shasum
#   usage: sh tests/standalone-launch-test.sh
#          The standalone archive's tree, unpacked anywhere with no /usr/local/mavergreen: the launcher
#          seeds Codex with the ed25519-verify it carries, links ~/.local/bin/codex to itself, and hands
#          Codex the installer and the rg beside it. `codex update`'s installer run finds the archive's
#          tree from CODEX_MAVERGREEN_INSTALLER alone, and a build that needs a newer archive opens no
#          updater.
set -eu
. "$(dirname "$0")/lib/harness.sh"
. "$(dirname "$0")/lib/fixtures.sh"
h_setup
CV=$(sh "$H_REPO/build/codex-pin.sh" version)
A=$CV-mavericks.1
B=$CV-mavericks.2
S="$HOME/.codex/packages/standalone"
LINK="$HOME/.local/bin/codex"
D="$H/apps/my codex/codex-cli-20261123.1"
X="$D/libexec/codex-cli/bundled"

mkdir -p "$D"
cp -R "$H_REPO/tree/." "$D/"
rm -rf "$D/libexec/mavergreen"
printf '20261123.1\n' > "$D/share/codex-cli/version"
printf '2026.10.20\n' > "$D/share/codex-cli/aquatransport-min-version"
CODEX_AQUATRANSPORT_VERSION=2026.10.20
export CODEX_AQUATRANSPORT_VERSION
h_fake_verify
unset CODEX_ED25519_VERIFY
mkdir -p "$X/ed25519/bin" "$X/rg/bin"
cp "$H/bin/fake-verify" "$X/ed25519/bin/ed25519-verify"
printf '#!/bin/sh\necho "bundled rg $*"\n' > "$X/rg/bin/rg"
chmod 0755 "$X/rg/bin/rg"
h_fake_open
h_channel $A

run() { "$@" >"$H/out" 2>"$H/err" && rc=0 || rc=$?; }

run "$D/bin/codex" --help
h_assert_eq 0 "$rc" "first run exits 0 ($(cat "$H/err"))"
h_assert_eq "fake codex $A --help" "$(cat "$H/out")" "first run execs the seeded build"
h_assert_present "$H/verify-calls" "the seed verified the channel with the archive's ed25519-verify"
h_assert_eq "$D/bin/codex" "$(readlink "$LINK")" "~/.local/bin/codex links to the archive's launcher"

run "$LINK" again
h_assert_eq 0 "$rc" "the link runs ($(cat "$H/err"))"
h_assert_eq "fake codex $A again" "$(cat "$H/out")" "the link execs the installed build"

R="$(cd -P "$S/current" && pwd)"
mv "$R/bin/codex" "$R/bin/codex.real"
printf '#!/bin/sh\nprintf "%%s\\n" "$CODEX_MAVERGREEN_INSTALLER" "$CODEX_MAVERGREEN_RG"\n' > "$R/bin/codex"
chmod 0755 "$R/bin/codex"
run "$D/bin/codex"
h_assert_eq "$D/libexec/codex-cli/install.sh
$X/rg/bin/rg" "$(cat "$H/out")" "Codex is handed the archive's installer and rg"
mv "$R/bin/codex.real" "$R/bin/codex"

run env CODEX_MAVERGREEN_RG="$X/rg/bin/rg" "$S/current/codex-path/rg" --files
h_assert_eq "bundled rg --files" "$(cat "$H/out")" "the build's rg runs the rg Codex is handed"

# as `codex update` runs it: only the installer's path says where the archive is
h_channel $B
run env CODEX_MAVERGREEN_INSTALLER="$D/libexec/codex-cli/install.sh" CODEX_NON_INTERACTIVE=1 \
  /bin/sh "$D/libexec/codex-cli/install.sh"
h_assert_eq 0 "$rc" "the update installs from the archive's tree ($(cat "$H/err"))"
h_assert_eq "$S/releases/$B-x86_64-apple-darwin" "$(readlink "$S/current")" "the update moved current"

C=$CV-mavericks.3
h_channel $C 20261124.1
run env CODEX_MAVERGREEN_INSTALLER="$D/libexec/codex-cli/install.sh" CODEX_INSTALL_ASSUME_TTY=1 \
  /bin/sh "$D/libexec/codex-cli/install.sh"
h_assert_eq 3 "$rc" "a build that needs a newer archive installs nothing"
h_assert_contains "$(cat "$H/err")" "installed: 20261123.1" "the archive's version is the installed one"
h_assert_contains "$(cat "$H/err")" "download the newer standalone archive from https://github.com/Mavergreen/codex-cli/releases/latest" "it says where the newer archive is"
h_assert_absent "$H/open-calls" "the standalone archive has no updater to open"

h_done
