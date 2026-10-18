#!/bin/sh
# platform: macOS-only -- pkgutil expands the product archive, lsbom lists the component's payload, and
#   PlistBuddy reads the manifest and the updater; the install steps run against a temporary target root
#   usage: package-test.sh PKG
#          PKG must be named codex-cli-<YYYYMMDD.N>.pkg. Its codex-cli component must carry exactly the
#          launcher (bin/codex, a script), the installer's modules, share/codex-cli/
#          {requires,aquatransport-min-version,ed25519_key.pub}, upstream's LICENSE and NOTICE, the
#          repo's README, the mavergreen.plist manifest and the updater app (Sparkle framework aside)
#          with its LaunchAgent, and no Codex binary. Its preinstall must require each product in
#          tree/share/codex-cli/requires. It then
#          runs the pkg's own preinstall and postinstall against a temporary target root (never "/",
#          so nothing system-wide is touched) to prove the link farm exports codex alone and resolves
#          to the launcher, that an upgrade drops a stale payload file, and that uninstall leaves
#          nothing behind. Finally the updater's bundle ID and feed must agree with shipyard's registry, and its
#          versions with the pkg's.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
. "$HERE/helpers/assert.sh"
PKG="${1:-}"
[ -n "$PKG" ] || { echo "package-test: usage: package-test.sh PKG" >&2; exit 77; }
MAVERICKS_BUILD_DIR="$REPO/build"; export MAVERICKS_BUILD_DIR
. "$REPO/build/lib.sh"
PB=/usr/libexec/PlistBuddy

V="$(basename "$PKG")"; V="${V#codex-cli-}"; V="${V%.pkg}"
case "$(basename "$PKG")" in codex-cli-*.pkg) _n=ok ;; *) _n=bad ;; esac
a_eq ok "$_n" "the pkg is named codex-cli-<version>.pkg"
case "$V" in
  *[!0-9.]*|'') _n=bad ;;
  *) printf '%s' "$V" | grep -Eq '^[0-9]{8}\.[1-9][0-9]*$' && _n=ok || _n=bad ;;
esac
a_eq ok "$_n" "the pkg's version is YYYYMMDD.N"
a_file_exists "the pkg exists" "$PKG"

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
M=usr/local/mavergreen/codex-cli
a_eq "" "$(grep -E '/(codex|codex-code-mode-host)$' "$T/bom" | grep -v "^$M/bin/codex\$" || true)" "no Codex binary is in the payload"
a_eq "" "$(grep -E 'codex-code-mode-host|codex-resources|codex-voice-host|build-manifest|codex-path|/packages/' "$T/bom" || true)" "the payload has no Codex host, resources, voice runtime or build manifest"
for f in bin/codex libexec/codex-cli/lib.sh libexec/codex-cli/link.sh libexec/codex-cli/install.sh; do
  a_eq "100755" "$(awk -F'\t' -v p="$M/$f" '$1 == p { print $2 }' "$T/modes")" "$f is executable"
done
for f in share/codex-cli/requires share/codex-cli/aquatransport-min-version share/codex-cli/ed25519_key.pub share/doc/codex-cli/LICENSE share/doc/codex-cli/NOTICE share/doc/codex-cli/README.md; do
  a_eq "100644" "$(awk -F'\t' -v p="$M/$f" '$1 == p { print $2 }' "$T/modes")" "$f is a plain file"
done
grep -v '/Sparkle\.framework/' "$T/bom" | LC_ALL=C sort > "$T/payload"
a_eq "Library/Application Support/Mavergreen/codex-cli-updater.app/Contents/Info.plist
Library/Application Support/Mavergreen/codex-cli-updater.app/Contents/MacOS/codex-cli-updater
Library/LaunchAgents/dev.mavergreen.codex-cli-updatecheck.plist
usr/local/mavergreen/codex-cli/bin/codex
usr/local/mavergreen/codex-cli/libexec/codex-cli/install.sh
usr/local/mavergreen/codex-cli/libexec/codex-cli/lib.sh
usr/local/mavergreen/codex-cli/libexec/codex-cli/link.sh
usr/local/mavergreen/codex-cli/mavergreen.plist
usr/local/mavergreen/codex-cli/share/codex-cli/aquatransport-min-version
usr/local/mavergreen/codex-cli/share/codex-cli/ed25519_key.pub
usr/local/mavergreen/codex-cli/share/codex-cli/requires
usr/local/mavergreen/codex-cli/share/doc/codex-cli/LICENSE
usr/local/mavergreen/codex-cli/share/doc/codex-cli/NOTICE
usr/local/mavergreen/codex-cli/share/doc/codex-cli/README.md" "$(cat "$T/payload")" "the payload is the launcher, the installer, the requires, AquaTransport pin and key, the docs, the manifest, the updater and its LaunchAgent"

# The preinstall requires each product the tree's requires file names, and says where to get it.
pre="$C/Scripts/preinstall"
a_file_exists "the codex-cli component has a preinstall" "$pre"
_want="" 
while read -r _s _u || [ -n "$_s" ]; do
  [ -n "$_s" ] || continue
  _want="$_want${_want:+ }$_s"
done < "$REPO/tree/share/codex-cli/requires"
a_eq "rg ed25519" "$_want" "the tree requires rg and ed25519"
a_eq "$_want" "$(sed -n 's/.*needs \([^ ]*\) installed first.*/\1/p' "$pre" | tr '\n' ' ' | sed 's/ $//')" "the preinstall requires exactly the requires file's products, in its order"
while read -r _s _u || [ -n "$_s" ]; do
  [ -n "$_s" ] || continue
  a_contains "$(cat "$pre")" "$_u" "the preinstall names where to get $_s"
done < "$REPO/tree/share/codex-cli/requires"

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
# the preinstall refuses a volume lacking a required product
if sh "$C/Scripts/preinstall" pkg dest "$ROOT" >/dev/null 2>&1; then _r=accepted; else _r=refused; fi
a_eq refused "$_r" "the preinstall refuses a volume without the required products"
for _s in $_want; do mkdir -p "$ROOT/usr/local/mavergreen/$_s"; : > "$ROOT/usr/local/mavergreen/$_s/mavergreen.plist"; done
install_into "$ROOT" >/dev/null 2>&1 || { echo "package-test: the pkg's install scripts failed on $ROOT" >&2; exit 1; }
P="$ROOT/usr/local/mavergreen/codex-cli"
FARM="$ROOT/usr/local/mavergreen/bin"

for f in bin/codex libexec/codex-cli/lib.sh libexec/codex-cli/link.sh libexec/codex-cli/install.sh \
         share/codex-cli/requires share/codex-cli/aquatransport-min-version share/codex-cli/ed25519_key.pub share/doc/codex-cli/LICENSE share/doc/codex-cli/NOTICE; do
  a_file_exists "$f is installed" "$P/$f"
  cmp "$P/$f" "$REPO/tree/$f" && _s=same || _s=differs
  a_eq same "$_s" "the installed $f is byte-identical to the committed one"
done
a_file_exists "README.md is installed" "$P/share/doc/codex-cli/README.md"
cmp "$P/share/doc/codex-cli/README.md" "$REPO/README.md" && _s=same || _s=differs
a_eq same "$_s" "the installed README.md is byte-identical to the repo's"
a_eq "#!/bin/sh" "$(head -n 1 "$P/bin/codex")" "bin/codex is the launcher script"
case "$(file "$P/bin/codex")" in *Mach-O*) _k=binary ;; *) _k=script ;; esac
a_eq script "$_k" "bin/codex is not a Mach-O binary"
a_no_file "no codex-code-mode-host is installed" "$P/bin/codex-code-mode-host"
a_no_file "no codex-resources is installed" "$P/codex-resources"

a_eq "dev.mavergreen.codex-cli" "$("$PB" -c 'Print :identifier' "$P/mavergreen.plist")" "the manifest identifier"
a_eq "codex-cli" "$("$PB" -c 'Print :product' "$P/mavergreen.plist")" "the manifest product"
a_eq "$V" "$("$PB" -c 'Print :version' "$P/mavergreen.plist")" "the manifest version is the package version"
a_eq "dev.mavergreen.codex-cli" "$(sh "$SHIPYARD/product-name.sh" identifier codex-cli)" "the manifest identity is the registry's"

a_eq "codex" "$(ls "$FARM")" "the link farm exports codex and nothing else"
a_eq "$(cd -P "$P/bin" && pwd -P)/codex" "$(cd -P "$FARM" && cd -P "$(dirname "$(readlink codex)")" && pwd -P)/codex" "the exported codex resolves to the installed launcher"

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

# The updater, as shipped in the pkg, against the registry.
mkdir "$T/out"
( cd "$T/out" && gzip -dc < "$C/Payload" | cpio -id 2>/dev/null )
UP="$T/out/Library/Application Support/Mavergreen/codex-cli-updater.app/Contents/Info.plist"
a_eq "$(sh "$SHIPYARD/product-name.sh" updater-bundle-id codex-cli)" "$("$PB" -c 'Print :CFBundleIdentifier' "$UP")" "the updater's bundle ID is the registry's"
a_eq "$(sh "$SHIPYARD/product-name.sh" feed codex-cli)" "$("$PB" -c 'Print :SUFeedURL' "$UP")" "the updater's feed is the registry's"
a_eq "$V" "$("$PB" -c 'Print :CFBundleShortVersionString' "$UP")" "the updater shows the package version"
a_eq "$V" "$("$PB" -c 'Print :CFBundleVersion' "$UP")" "the updater's comparison version is the package version"
a_done
