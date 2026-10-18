#!/bin/sh
# platform: macOS-only -- builds with 10.9's bsdtar and reads the result back with tar and plutil
#   usage: sh tests/codex-package-test.sh
#          Builds the Codex build tarball from a fake artifact directory (small executables, LICENSE,
#          NOTICE, build-manifest) under a path with a space, extracts it, and checks every entry, its
#          mode, the codex-package.json fields and the codex-path/rg wrapper; then checks that each
#          refused input exits non-zero and leaves no tarball behind.
set -eu
. "$(dirname "$0")/lib/harness.sh"
h_setup
BP="$H_REPO/packaging/build-codex-package.sh"
VER="$(tr -d '[:space:]' < "$H_REPO/components/codex/version")"
ID="$VER-mavericks.3"

A="$H/artifact"
mkdir -p "$A"
printf '#!/bin/sh\necho codex\n' > "$A/codex"
printf '#!/bin/sh\necho host\n' > "$A/codex-code-mode-host"
chmod 0755 "$A/codex" "$A/codex-code-mode-host"
printf 'license\n' > "$A/LICENSE"
printf 'notice\n' > "$A/NOTICE"
printf 'manifest\n' > "$A/build-manifest"

OUT="$H/out dir"
TB="$OUT/codex-package-x86_64-apple-darwin-$ID.tar.gz"
GOT="$(sh "$BP" "$A" "$ID" "$OUT")"
h_assert_eq "$TB" "$GOT" "the script prints the tarball's path"
h_assert_ok test -f "$TB"

X="$H/x"
mkdir -p "$X"
tar -xzf "$TB" -C "$X"
h_assert_eq "" "$(tar -tzf "$TB" | grep '\._' || true)" "no AppleDouble entries"
h_assert_eq "codex-package.json
bin/codex
bin/codex-code-mode-host
codex-resources/
codex-path/rg
LICENSE
NOTICE
build-manifest" "$(tar -tzf "$TB")" "the tarball holds exactly the package layout, in a stable order"

for f in codex codex-code-mode-host; do
  h_assert_ok cmp "$A/$f" "$X/bin/$f"
  h_assert_eq 755 "$(stat -f %Lp "$X/bin/$f")" "bin/$f is mode 0755"
done
for f in LICENSE NOTICE build-manifest; do
  h_assert_ok cmp "$A/$f" "$X/$f"
done
h_assert_ok test -d "$X/codex-resources"
h_assert_eq "" "$(ls -A "$X/codex-resources")" "codex-resources is empty"
# the app-server daemon copies the package and refuses any link that leaves it, so rg is a script
h_assert_eq "" "$(find "$X" -type l)" "the package holds no links"
# (read only a regular file: a link would lead to whatever rg is installed)
RGW="$H/rg-wrapper"
: > "$RGW"
[ -L "$X/codex-path/rg" ] || cp "$X/codex-path/rg" "$RGW"
h_assert_eq 755 "$(stat -f %Lp "$X/codex-path/rg")" "codex-path/rg is mode 0755"
h_assert_eq '#!/bin/sh
exec /usr/local/mavergreen/rg/bin/rg "$@"' "$(cat "$RGW")" "codex-path/rg execs the rg package's rg"
# the wrapper passes its arguments through unchanged, spaces included
mkdir -p "$H/fake rg/bin"
printf '#!/bin/sh\nfor a in "$@"; do printf "<%%s>" "$a"; done\n' > "$H/fake rg/bin/rg"
chmod 0755 "$H/fake rg/bin/rg"
sed "s|/usr/local/mavergreen/rg/bin/rg|'$H/fake rg/bin/rg'|" "$RGW" > "$RGW.test"
h_assert_eq '<a b><-->' "$(sh "$RGW.test" 'a b' --)" "the wrapper passes every argument through"

h_assert_ok plutil -convert json -o /dev/null "$X/codex-package.json"
h_assert_eq '{
  "layoutVersion": 1,
  "version": "'"$VER"'",
  "target": "x86_64-apple-darwin",
  "variant": "codex",
  "entrypoint": "bin/codex",
  "resourcesDir": "codex-resources",
  "pathDir": "codex-path",
  "mavergreenBuild": "'"$ID"'"
}' "$(cat "$X/codex-package.json")" "codex-package.json holds upstream's fields plus mavergreenBuild"

# a refused build exits non-zero and leaves no tarball (and no OUT-DIR)
refuse() {
  _r_msg="$1"; shift
  _r_o="$H/refused-out"
  rm -rf "$_r_o"
  h_assert_fails sh "$BP" "$@" "$_r_o"
  h_assert_absent "$_r_o" "$_r_msg leaves nothing behind"
}
A2="$H/artifact voice"
cp -R "$A" "$A2"; : > "$A2/codex-voice-host"
refuse "an artifact with codex-voice-host" "$A2" "$ID"
A3="$H/artifact res"
cp -R "$A" "$A3"; mkdir "$A3/codex-resources"
refuse "an artifact with codex-resources" "$A3" "$ID"
A4="$H/artifact short"
cp -R "$A" "$A4"; rm "$A4/NOTICE"
refuse "an artifact without NOTICE" "$A4" "$ID"
refuse "an ID for another Codex version" "$A" "9.9.9-mavericks.1"
refuse "an ID without the mavericks suffix" "$A" "$VER"
refuse "an ID with N = 0" "$A" "$VER-mavericks.0"
refuse "an ID with a leading-zero N" "$A" "$VER-mavericks.01"
refuse "an ID with trailing junk" "$A" "$ID-x"
h_assert_fails sh "$BP" "$A" "$ID"

h_done
