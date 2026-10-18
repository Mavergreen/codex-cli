#!/bin/sh
# platform: macOS-only -- tars with 10.9's bsdtar (COPYFILE_DISABLE keeps AppleDouble entries out)
#   usage: build-codex-package.sh CODEX-OUT BUILD-ID OUT-DIR
#          CODEX-OUT is a Codex build's artifact directory (build/build-codex.sh's codex-native or
#          codex-cross): codex, codex-code-mode-host, build-manifest, LICENSE and NOTICE. Lays them out
#          as upstream Codex's standalone package (codex-package.json, bin/, codex-resources/,
#          codex-path/) and writes OUT-DIR/codex-package-x86_64-apple-darwin-BUILD-ID.tar.gz, whose
#          path it prints. BUILD-ID is <codex x.y.z>-mavericks.<N>, x.y.z being components/codex/version.
#          A refused input leaves no tarball and no OUT-DIR.
set -eu
U="usage: build-codex-package.sh CODEX-OUT BUILD-ID OUT-DIR"
OUT_IN=${1:?$U}
ID=${2:?$U}
OUTDIR=${3:?$U}
REPO=$(cd "$(dirname "$0")/.." && pwd)
for f in codex codex-code-mode-host build-manifest LICENSE NOTICE; do
  [ -f "$OUT_IN/$f" ] || { echo "build-codex-package: no $OUT_IN/$f" >&2; exit 1; }
done
# spec: INGREDIENTS.md "Packaging" -- voice is deferred, so neither of its payloads may ever be packaged
for f in codex-voice-host codex-resources; do
  [ ! -e "$OUT_IN/$f" ] || { echo "build-codex-package: $OUT_IN/$f: voice is not packaged" >&2; exit 1; }
done
VER=$(tr -d '[:space:]' < "$REPO/components/codex/version")
printf '%s\n' "$ID" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+-mavericks\.[1-9][0-9]*$' \
  || { echo "build-codex-package: BUILD-ID $ID is not <x.y.z>-mavericks.<N>, N >= 1" >&2; exit 1; }
[ "${ID%-mavericks.*}" = "$VER" ] \
  || { echo "build-codex-package: BUILD-ID $ID is not a build of Codex $VER (components/codex/version)" >&2; exit 1; }
work=$(mktemp -d "${TMPDIR:-/tmp}/codex-package.XXXXXX")
trap 'rm -rf "$work"' EXIT
P=$work/pkg
install -d "$P/bin" "$P/codex-resources" "$P/codex-path"
# platform: Codex finds codex-code-mode-host beside its canonicalized executable, so both live in bin/
install -m 0755 "$OUT_IN/codex" "$P/bin/codex"
install -m 0755 "$OUT_IN/codex-code-mode-host" "$P/bin/codex-code-mode-host"
for f in build-manifest LICENSE NOTICE; do
  install -m 0644 "$OUT_IN/$f" "$P/$f"
done
# spec: the rg package provides rg, which need not exist when the tarball is built. A script, not a
#       link: the app-server daemon copies this package and refuses any link that leaves it.
printf '#!/bin/sh\nexec /usr/local/mavergreen/rg/bin/rg "$@"\n' > "$P/codex-path/rg"
chmod 0755 "$P/codex-path/rg"
# upstream's codex_package/layout.py writes these fields in this order, indented two spaces
cat > "$P/codex-package.json" <<JSON
{
  "layoutVersion": 1,
  "version": "$VER",
  "target": "x86_64-apple-darwin",
  "variant": "codex",
  "entrypoint": "bin/codex",
  "resourcesDir": "codex-resources",
  "pathDir": "codex-path",
  "mavergreenBuild": "$ID"
}
JSON
chmod 0644 "$P/codex-package.json"
NAME=codex-package-x86_64-apple-darwin-$ID.tar.gz
# named entries, not a directory walk, so the order is the same on every build
COPYFILE_DISABLE=1 tar -czf "$work/$NAME" -C "$P" \
  codex-package.json bin/codex bin/codex-code-mode-host codex-resources codex-path/rg LICENSE NOTICE build-manifest
mkdir -p "$OUTDIR"
mv "$work/$NAME" "$OUTDIR/$NAME"
echo "$OUTDIR/$NAME"
