#!/bin/sh
# platform: macOS-only -- drives the launcher, which targets Mac OS X 10.9's sh and tools
#   usage: sh tests/aquatransport-test.sh
#          The launcher dies unless a Wowfunhappy.AquaTransport release at least as new as the pin is
#          installed, before it seeds or runs anything. The tree carries the same pin as the component.
set -eu
. "$(dirname "$0")/lib/harness.sh"
h_setup

MG="$H/root/usr/local/mavergreen"
T="$MG/codex-cli"
PIN="$T/share/codex-cli/aquatransport-min-version"
URL=https://mavericksforever.com/downloads/AquaTransport.dmg
mkdir -p "$T" "$MG/bin" "$H/links"
cp -R "$H_REPO/tree/." "$T/"
ln -s "$T/bin/codex" "$MG/bin/codex"
ln -s "$MG/bin/codex" "$H/links/codex"
for s in rg ed25519; do mkdir -p "$MG/$s"; : > "$MG/$s/mavergreen.plist"; done
# nothing is seeded: a launcher that gets past the check fails on the unreachable channel
CODEX_BUILDS_URL="file:///nonexistent"
export CODEX_BUILDS_URL

h_assert_eq "$(cat "$H_REPO/components/aquatransport/min-version")" "$(cat "$PIN")" "the package carries the component's AquaTransport pin"

run_codex() { rc=0; err="$("$H/links/codex" 2>&1 >/dev/null)" || rc=$?; }
# try PIN INSTALLED: run the launcher with that pin and receipt version (INSTALLED empty means no receipt)
try() { printf '%s\n' "$1" > "$PIN"; CODEX_AQUATRANSPORT_VERSION="$2"; export CODEX_AQUATRANSPORT_VERSION; run_codex; }
passes() { case "$err" in *AquaTransport*) h_assert_eq "" "$err" "$1" ;; esac; }

try 2026.10.20 ""
h_assert_eq 1 "$rc" "no receipt exits 1"
h_assert_eq "codex: AquaTransport is not installed; Codex needs it for TLS on this Mac. Get it from $URL" "$err" "no receipt message"

try 2026.10.20 2026.09.21
h_assert_eq 1 "$rc" "an older receipt exits 1"
h_assert_eq "codex: AquaTransport 2026.09.21 is too old; Codex needs 2026.10.20 or newer. Get it from $URL" "$err" "older receipt message"

try 2026.10.20 2026.10.19; h_assert_eq 1 "$rc" "one day older exits 1"
try 2026.10.20 2025.12.31; h_assert_eq 1 "$rc" "an older year exits 1"
try 2026.10.20 2026.09.30; h_assert_eq 1 "$rc" "a later day in an earlier month is older"
try 2026.10.20 2026.10.20; passes "an equal receipt passes"
try 2026.10.20 2026.10.21; passes "a newer day passes"
try 2026.10.20 2026.11.01; passes "a newer month passes"
try 2026.10.20 2027.01.01; passes "a newer year passes"
try 2026.10.08 2026.10.09; passes "zero-padded fields compare numerically, not as octal"

try unreleased 2030.01.01
h_assert_eq 1 "$rc" "an unreleased pin exits 1 even with a newer receipt"
h_assert_eq "codex: this codex-cli package needs an AquaTransport release that does not exist yet" "$err" "unreleased message"
try unreleased ""
h_assert_eq "codex: this codex-cli package needs an AquaTransport release that does not exist yet" "$err" "unreleased wins over a missing receipt"

for bad in 2026.9.21 20260921 2026-09-21 v2026.09.21 2026.09.21.1 2026.09 abc; do
  try 2026.10.20 "$bad"
  h_assert_eq 1 "$rc" "receipt '$bad' exits 1"
  h_assert_eq "codex: AquaTransport version '$bad' is not YYYY.MM.DD" "$err" "malformed receipt '$bad' is named"
  try "$bad" 2026.10.20
  h_assert_eq 1 "$rc" "pin '$bad' exits 1"
  h_assert_eq "codex: the AquaTransport minimum '$bad' in $PIN is not YYYY.MM.DD or unreleased" "$err" "malformed pin '$bad' is named"
done
try "" 2026.10.20
h_assert_eq "codex: the AquaTransport minimum '' in $PIN is not YYYY.MM.DD or unreleased" "$err" "an empty pin is malformed"

rm "$PIN"
CODEX_AQUATRANSPORT_VERSION=2026.10.20; export CODEX_AQUATRANSPORT_VERSION
run_codex
h_assert_eq "codex: missing $PIN" "$err" "a missing pin file is named"

# without the override the receipt comes from pkgutil, one call, no network
printf '2026.10.20\n' > "$PIN"
unset CODEX_AQUATRANSPORT_VERSION
cat > "$H/bin/pkgutil" <<'FAKE'
#!/bin/sh
echo "$*" >> "$H/pkgutil-calls"
[ "$1 $2" = "--pkg-info Wowfunhappy.AquaTransport" ] || exit 1
[ -z "${FAKE_RECEIPT-}" ] && exit 1
printf 'package-id: Wowfunhappy.AquaTransport\nversion: %s\nvolume: /\nlocation: /\ninstall-time: 1\n' "$FAKE_RECEIPT"
FAKE
chmod +x "$H/bin/pkgutil"
PATH="$H/bin:$H_ORIG_PATH"; export PATH
FAKE_RECEIPT=2026.10.20; export FAKE_RECEIPT
run_codex
passes "the pkgutil receipt passes"
h_assert_eq "--pkg-info Wowfunhappy.AquaTransport" "$(cat "$H/pkgutil-calls")" "one pkgutil call, for the AquaTransport receipt"
FAKE_RECEIPT=2026.09.21
run_codex
h_assert_eq "codex: AquaTransport 2026.09.21 is too old; Codex needs 2026.10.20 or newer. Get it from $URL" "$err" "pkgutil's old receipt is refused"
FAKE_RECEIPT=
run_codex
h_assert_eq "codex: AquaTransport is not installed; Codex needs it for TLS on this Mac. Get it from $URL" "$err" "pkgutil with no receipt is refused"
h_done
