#!/bin/sh
# platform: macOS-only -- drives the launcher, which targets Mac OS X 10.9's sh and tools
#   usage: sh tests/requires-test.sh
#          The launcher dies naming the missing ingredient and where to get it.
set -eu
. "$(dirname "$0")/lib/harness.sh"
h_setup

MG="$H/root/usr/local/mavergreen"
T="$MG/codex-cli"
mkdir -p "$T"
cp -R "$H_REPO/tree/." "$T/"
# the package's pin is unreleased until AquaTransport has the fix; these tests are not about it
printf '2026.10.20\n' > "$T/share/codex-cli/aquatransport-min-version"
CODEX_AQUATRANSPORT_VERSION=2026.10.20
export CODEX_AQUATRANSPORT_VERSION
mkdir -p "$MG/bin" "$H/links"
ln -s "$T/bin/codex" "$MG/bin/codex"
ln -s "$MG/bin/codex" "$H/links/codex"

h_assert_eq "rg https://github.com/Mavergreen/rg/releases/latest
ed25519 https://github.com/Mavergreen/ed25519/releases/latest" "$(cat "$T/share/codex-cli/requires")" "requires manifest"
h_assert_eq "$(cat "$H_REPO/updater/ed25519_key.pub")" "$(cat "$T/share/codex-cli/ed25519_key.pub")" "the package carries the updater's public key"

run_codex() { rc=0; err="$("$H/links/codex" 2>&1 >/dev/null)" || rc=$?; }

for s in rg ed25519; do mkdir -p "$MG/$s"; : > "$MG/$s/mavergreen.plist"; done
# everything present: the launcher gets past the check (it then fails to seed, which is not our concern here)
CODEX_BUILDS_URL="file:///nonexistent"
export CODEX_BUILDS_URL
run_codex
case "$err" in *"is not installed"*) h_assert_eq "" "$err" "all present has no requires complaint" ;; esac

for s in rg:rg ed25519:ed25519; do
  short="${s%%:*}"; repo="${s#*:}"
  mv "$MG/$short/mavergreen.plist" "$MG/$short/gone"
  run_codex
  h_assert_eq 1 "$rc" "$short missing exits 1"
  h_assert_eq "codex: $short is not installed; get it from https://github.com/Mavergreen/$repo/releases/latest" "$err" "$short missing message"
  mv "$MG/$short/gone" "$MG/$short/mavergreen.plist"
done

mv "$T/share/codex-cli/requires" "$T/share/codex-cli/requires.gone"
run_codex
h_assert_eq 1 "$rc" "a missing requires file exits 1"
h_assert_contains "$err" "missing $T/share/codex-cli/requires" "missing requires message"
: > "$T/share/codex-cli/requires"
run_codex
h_assert_eq 1 "$rc" "an empty requires file exits 1"
h_assert_contains "$err" "$T/share/codex-cli/requires lists nothing" "empty requires message"
h_done
