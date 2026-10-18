#!/bin/sh
# platform: macOS-only -- builds a product archive with shipyard's pkgbuild/productbuild scripts and expands it with pkgutil
#   usage: sh tests/build-pkg-test.sh
#          build-pkg.sh from a scratch clone of this repo with a stand-in updater: a committed tree/
#          draws no warning; an uncommitted one still builds, warns, and the pkg holds HEAD's tree;
#          a stray Mach-O, or a codex binary anywhere but the launcher, is refused.
set -eu
. "$(dirname "$0")/lib/harness.sh"
if [ -z "${SHIPYARD_SCRIPTS:-}" ] || [ ! -d "$SHIPYARD_SCRIPTS" ]; then
  . "$H_REPO/build/msc.sh" || exit 1
fi
h_setup
PN="$SHIPYARD_SCRIPTS/product-name.sh"
R="$H/repo"
mkdir -p "$R/build"
cp -R "$H_REPO/packaging" "$H_REPO/tree" "$R/"
cp "$H_REPO/build/msc.sh" "$R/build/"
cp "$H_REPO/README.md" "$R/"
git -C "$R" init -q
git -C "$R" add -A
git -C "$R" -c user.name=test -c user.email=test@example.invalid -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -qm fixture

APPREL="$(sh "$PN" updater-app codex-cli)"
APP="$H/${APPREL##*/}"
mkdir -p "$APP/Contents/MacOS"
printf '#!/bin/sh\n' > "$APP/Contents/MacOS/codex-cli-updater"
chmod +x "$APP/Contents/MacOS/codex-cli-updater"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $(sh "$PN" updater-bundle-id codex-cli)" \
  -c "Add :SUFeedURL string $(sh "$PN" feed codex-cli)" -c 'Add :CFBundleExecutable string codex-cli-updater' \
  -c 'Add :CFBundlePackageType string APPL' "$APP/Contents/Info.plist" >/dev/null

V=20261017.1
bp() { sh "$R/packaging/build-pkg.sh" "$APP" "$V" "$1" 2>&1; }
rc=0; out="$(bp "$H/d1")" || rc=$?
h_assert_eq 0 "$rc" "a committed tree/ builds: $out"
case "$out" in *uncommitted*) h_assert_eq "no warning" "$out" "a committed tree/ draws no warning" ;; esac
[ -f "$H/d1/codex-cli-$V.pkg" ] || { echo "FAIL: no pkg built" >&2; exit 1; }

cp "$R/tree/bin/codex" "$H/committed-codex"
printf '# a local edit\n' >> "$R/tree/bin/codex"
: > "$R/tree/untracked"
rc=0; out="$(bp "$H/d2")" || rc=$?
h_assert_eq 0 "$rc" "a tree/ with uncommitted changes still builds: $out"
h_assert_contains "$out" "build-pkg: tree/ has uncommitted changes, which this package leaves out (it stages tree/ as committed at HEAD)" "and warns that they are not in the package"
mkdir "$H/x"
pkgutil --expand "$H/d2/codex-cli-$V.pkg" "$H/x/e"
( cd "$H/x" && mkdir root && cd root && gzip -dc < "$H/x/e/codex-cli-component.pkg/Payload" | cpio -id 2>/dev/null )
h_assert_ok cmp -s "$H/committed-codex" "$H/x/root/usr/local/mavergreen/codex-cli/bin/codex"
h_assert_absent "$H/x/root/usr/local/mavergreen/codex-cli/untracked" "an untracked file in tree/ stays out of the package"
git -C "$R" checkout -q -- tree/bin/codex
rm -f "$R/tree/untracked"

# a stray Mach-O, in the scratch tree and committed, is refused wherever it sits and whatever it is called
commit_stray() {
  git -C "$R" add -A
  git -C "$R" -c user.name=test -c user.email=test@example.invalid -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -qm "$1"
}
refused() {
  rc=0; out="$(bp "$H/dr")" || rc=$?
  h_assert_eq 1 "$rc" "$1: refused"
  h_assert_contains "$out" "$2" "$1: and says why"
  h_assert_absent "$H/dr/codex-cli-$V.pkg" "$1: and builds nothing"
}
cp /bin/ls "$R/tree/share/codex-cli/tool"
commit_stray stray
refused "a Mach-O under share/" "share/codex-cli/tool: a Mach-O file"
git -C "$R" rm -q -f tree/share/codex-cli/tool
cp /bin/ls "$R/tree/bin/codex"
commit_stray "launcher replaced"
refused "a Mach-O bin/codex" "tree/bin/codex is not the launcher script"
git -C "$R" checkout -q HEAD~1 -- tree/bin/codex
mkdir -p "$R/tree/libexec/codex-cli"
printf '#!/bin/sh\n' > "$R/tree/libexec/codex-cli/codex"
commit_stray "codex elsewhere"
refused "a file named codex outside bin/" "libexec/codex-cli/codex: a Codex binary"
h_done
