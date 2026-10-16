#!/bin/sh
# platform: macOS-only -- pkgutil expands the product archive, lsbom lists the component's payload, and
#   PlistBuddy reads the manifest and the updater; the install steps run against a temporary target root
#   usage: package-test.sh PKG CODEX-OUT
#          PKG must be named codex-cli-<version>.pkg; CODEX-OUT is the Codex build's artifact directory
#          (codex-native or codex-cross), which is what the packaged binaries must equal. The same test
#          checks either mode. Its codex-cli component must carry exactly bin/codex and
#          bin/codex-code-mode-host (executable, byte-identical to the build), the build manifest, upstream's
#          LICENSE and NOTICE, the repo's README, the mavergreen.plist manifest and the updater app (Sparkle framework aside) with its LaunchAgent,
#          and no voice payload. It then runs the pkg's own preinstall and postinstall against a
#          temporary target root (never "/", so nothing system-wide is touched) to prove the link farm
#          exports codex alone and resolves to the directory holding codex-code-mode-host, that an
#          upgrade drops a stale payload file, and that uninstall leaves nothing behind. Finally the
#          updater's bundle ID, feed and comparison version must agree with shipyard's registry and
#          the package version.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
. "$HERE/helpers/assert.sh"
PKG="${1:-}"; OUT="${2:-}"
[ -n "$PKG" ] && [ -n "$OUT" ] || { echo "package-test: usage: package-test.sh PKG CODEX-OUT" >&2; exit 77; }
MAVERICKS_BUILD_DIR="$REPO/build"; export MAVERICKS_BUILD_DIR
. "$REPO/build/lib.sh"
PB=/usr/libexec/PlistBuddy

V="$(basename "$PKG")"; V="${V#codex-cli-}"; V="${V%.pkg}"
case "$(basename "$PKG")" in codex-cli-[0-9]*.pkg) _n=ok ;; *) _n=bad ;; esac
a_eq ok "$_n" "the pkg is named codex-cli-<version>.pkg"
a_file_exists "the pkg exists" "$PKG"
a_file_exists "the built codex exists" "$OUT/codex"
a_file_exists "the built codex-code-mode-host exists" "$OUT/codex-code-mode-host"

t_tmp T
pkgutil --expand "$PKG" "$T/x"
C="$T/x/codex-cli-component.pkg"
a_file_exists "the product archive carries the codex-cli component" "$C/Bom"
lsbom -s -f "$C/Bom" | sed 's|^\./||' > "$T/bom"
a_eq 1 "$(grep -c 'codex-cli-updater\.app/Contents/Frameworks/Sparkle\.framework/Versions/A/Sparkle$' "$T/bom")" "the Sparkle binary is in the payload"
lsbom "$C/Bom" | sed 's|^\./||' > "$T/modes"
a_eq "" "$(awk -F'\t' '{ m = $2; o = substr(m, length(m)) + 0 }
  m ~ /^10/ && int(o / 4) % 2 == 0 { print $1 " " m }
  m ~ /^4/ && o % 2 == 0 { print $1 " " m }' "$T/modes")" "every payload file is world-readable and every directory world-searchable"
a_eq "100755" "$(awk -F'\t' '$1 == "usr/local/mavergreen/codex-cli/bin/codex" { print $2 }' "$T/modes")" "codex is executable"
a_eq "100755" "$(awk -F'\t' '$1 == "usr/local/mavergreen/codex-cli/bin/codex-code-mode-host" { print $2 }' "$T/modes")" "codex-code-mode-host is executable"
a_eq "" "$(grep -i 'voice' "$T/bom" || true)" "the payload has no voice runtime (no codex-voice-host, no codex-resources/voice)"
grep -v '/Sparkle\.framework/' "$T/bom" | LC_ALL=C sort > "$T/payload"
a_eq "Library/Application Support/Mavergreen/codex-cli-updater.app/Contents/Info.plist
Library/Application Support/Mavergreen/codex-cli-updater.app/Contents/MacOS/codex-cli-updater
Library/LaunchAgents/dev.mavergreen.codex-cli-updatecheck.plist
usr/local/mavergreen/codex-cli/bin/codex
usr/local/mavergreen/codex-cli/bin/codex-code-mode-host
usr/local/mavergreen/codex-cli/mavergreen.plist
usr/local/mavergreen/codex-cli/share/doc/codex-cli/LICENSE
usr/local/mavergreen/codex-cli/share/doc/codex-cli/NOTICE
usr/local/mavergreen/codex-cli/share/doc/codex-cli/README.md
usr/local/mavergreen/codex-cli/share/doc/codex-cli/build-manifest" "$(cat "$T/payload")" "the payload is codex and its host, the manifests, the README, the updater and its LaunchAgent"

# A target root, filled the way Installer fills one: preinstall, then each component's payload, then postinstall.
B="$T/x/mavergreen-base.pkg"
a_file_exists "the product archive carries the mavergreen base component" "$B/Payload"
install_into() {
  sh "$C/Scripts/preinstall" pkg dest "$1"
  for _c in "$B" "$C"; do ( cd "$1" && gzip -dc < "$_c/Payload" | cpio -id 2>/dev/null ); done
  sh "$B/Scripts/postinstall" pkg dest "$1"
  sh "$C/Scripts/postinstall" pkg dest "$1"
}
ROOT="$T/root"; mkdir "$ROOT"
install_into "$ROOT" >/dev/null 2>&1 || { echo "package-test: the pkg's install scripts failed on $ROOT" >&2; exit 1; }
P="$ROOT/usr/local/mavergreen/codex-cli"
FARM="$ROOT/usr/local/mavergreen/bin"

cmp "$P/bin/codex" "$OUT/codex" && _s=same || _s=differs
a_eq same "$_s" "the packaged codex is byte-identical to the built one"
cmp "$P/bin/codex-code-mode-host" "$OUT/codex-code-mode-host" && _s=same || _s=differs
a_eq same "$_s" "the packaged codex-code-mode-host is byte-identical to the built one"
for f in LICENSE NOTICE build-manifest; do
  a_file_exists "$f is installed" "$P/share/doc/codex-cli/$f"
  cmp "$P/share/doc/codex-cli/$f" "$OUT/$f" && _s=same || _s=differs
  a_eq same "$_s" "the installed $f is byte-identical to the artifact's"
done
a_file_exists "README.md is installed" "$P/share/doc/codex-cli/README.md"
cmp "$P/share/doc/codex-cli/README.md" "$REPO/README.md" && _s=same || _s=differs
a_eq same "$_s" "the installed README.md is byte-identical to the repo's"
a_eq "$V" "$(sed -n 's/^version=//p' "$P/share/doc/codex-cli/build-manifest")" "the installed build-manifest's version is the package version"
a_no_file "no codex-voice-host is installed" "$P/bin/codex-voice-host"
a_no_file "no codex-resources is installed" "$P/codex-resources"

a_eq "dev.mavergreen.codex-cli" "$("$PB" -c 'Print :identifier' "$P/mavergreen.plist")" "the manifest identifier"
a_eq "codex-cli" "$("$PB" -c 'Print :product' "$P/mavergreen.plist")" "the manifest product"
a_eq "$V" "$("$PB" -c 'Print :version' "$P/mavergreen.plist")" "the manifest version is the package version"
a_eq "bin/codex-code-mode-host" "$("$PB" -c 'Print :exports-exclude:0' "$P/mavergreen.plist")" "the manifest keeps the host out of the link farm"
a_eq "dev.mavergreen.codex-cli" "$(sh "$SHIPYARD/product-name.sh" identifier codex-cli)" "the manifest identity is the registry's"

a_eq "codex" "$(ls "$FARM")" "the link farm exports codex and nothing else"
a_no_file "codex-code-mode-host is not exported" "$FARM/codex-code-mode-host"
# platform: Codex finds the host beside its canonicalized executable, so follow the link the way it does
_real="$(cd -P "$FARM" && cd -P "$(dirname "$(readlink codex)")" && pwd -P)"
a_file_exists "the exported codex resolves to a directory that holds codex-code-mode-host" "$_real/codex-code-mode-host"
a_eq "$(cd -P "$P/bin" && pwd -P)" "$_real" "the exported codex resolves into the installed tree"

# Upgrade: a stale payload file must go, and the link must come back.
echo stale > "$P/bin/stale-from-last-version"
install_into "$ROOT" >/dev/null 2>&1 || { echo "package-test: the upgrade scripts failed on $ROOT" >&2; exit 1; }
a_no_file "an upgrade removes a stale payload file" "$P/bin/stale-from-last-version"
a_file_exists "an upgrade restores codex" "$P/bin/codex"
a_file_exists "an upgrade relinks codex" "$FARM/codex"

# Uninstall leaves nothing of the product.
"$ROOT/usr/local/bin/mavergreen" --root "$ROOT" uninstall codex-cli >/dev/null 2>&1 || true
a_no_file "uninstall removes the installed tree" "$P"
a_no_file "uninstall removes the exported link" "$FARM/codex"
a_no_file "uninstall removes the updater app" "$ROOT/Library/Application Support/Mavergreen/codex-cli-updater.app"
a_no_file "uninstall removes the updater's LaunchAgent" "$ROOT/Library/LaunchAgents/dev.mavergreen.codex-cli-updatecheck.plist"

# The updater, as shipped in the pkg, against the registry and the package version.
mkdir "$T/out"
( cd "$T/out" && gzip -dc < "$C/Payload" | cpio -id 2>/dev/null )
UP="$T/out/Library/Application Support/Mavergreen/codex-cli-updater.app/Contents/Info.plist"
a_eq "$(sh "$SHIPYARD/product-name.sh" updater-bundle-id codex-cli)" "$("$PB" -c 'Print :CFBundleIdentifier' "$UP")" "the updater's bundle ID is the registry's"
a_eq "$(sh "$SHIPYARD/product-name.sh" feed codex-cli)" "$("$PB" -c 'Print :SUFeedURL' "$UP")" "the updater's feed is the registry's"
a_eq "$V" "$("$PB" -c 'Print :CFBundleShortVersionString' "$UP")" "the updater shows the package version"
_cmp="$("$PB" -c 'Print :CFBundleVersion' "$UP")"
a_eq "$(printf '%s' "$V" | sed 's/-mavericks\./\./')" "$_cmp" "the updater's comparison version is the package version, dotted"
case "$_cmp" in *[!0-9.]*|''|.*|*.|*..*) _d=bad ;; *) _d=ok ;; esac
a_eq ok "$_d" "the updater's comparison version is dotted numeric"
a_done
