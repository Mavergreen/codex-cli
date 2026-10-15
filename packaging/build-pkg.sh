#!/bin/sh
# platform: macOS-only -- drives shipyard's stage_product.sh, build_component_pkg.sh and set_install_floor.sh
#   usage: build-pkg.sh UPDATER-APP CODEX-OUT VERSION OUT-DIR
#          CODEX-OUT is a Codex build's artifact directory (build/build-codex.sh's codex-native or
#          codex-cross): codex, codex-code-mode-host and build-manifest. Stages the two executables
#          (byte for byte as built and checked) side by side in bin/, the build manifest, upstream's LICENSE and NOTICE and the updater
#          under /usr/local/mavergreen/codex-cli, and wraps them in a 10.9.5-floored product archive,
#          OUT-DIR/codex-cli-VERSION.pkg, whose path it prints. The same script packages either mode.
set -eu
U="usage: build-pkg.sh UPDATER-APP CODEX-OUT VERSION OUT-DIR"
APP=${1:?$U}
OUT_IN=${2:?$U}
V=${3:?$U}
OUTDIR=${4:?$U}
REPO=$(cd "$(dirname "$0")/.." && pwd)
MAVERICKS_BUILD_DIR=$REPO/build; export MAVERICKS_BUILD_DIR
. "$REPO/build/lib.sh"
for f in codex codex-code-mode-host build-manifest LICENSE NOTICE; do
  [ -f "$OUT_IN/$f" ] || { echo "build-pkg: no $OUT_IN/$f" >&2; exit 1; }
done
# spec: INGREDIENTS.md "Packaging" -- voice is deferred, so neither of its payloads may ever be packaged
for f in codex-voice-host codex-resources; do
  [ ! -e "$OUT_IN/$f" ] || { echo "build-pkg: $OUT_IN/$f: voice is not packaged" >&2; exit 1; }
done
[ -d "$APP" ] || { echo "build-pkg: no updater $APP; configure with -DCODEX_BUILD_UPDATER=ON" >&2; exit 1; }
work=$(mktemp -d "${TMPDIR:-/tmp}/codex-cli-pkg.XXXXXX")
trap 'rm -rf "$work"' EXIT
ROOT=$work/root
T=$ROOT/usr/local/mavergreen/codex-cli
install -d "$T/bin" "$T/share/doc/codex-cli"
# platform: Codex finds codex-code-mode-host beside its canonicalized executable, so both live in bin/
install -m 0755 "$OUT_IN/codex" "$T/bin/codex"
install -m 0755 "$OUT_IN/codex-code-mode-host" "$T/bin/codex-code-mode-host"
# spec: INGREDIENTS.md "License notices" -- the artifact carries OpenAI's Apache-2.0 LICENSE and NOTICE
for f in build-manifest LICENSE NOTICE; do
  install -m 0644 "$OUT_IN/$f" "$T/share/doc/codex-cli/$f"
done
find "$ROOT" -name '._*' -delete
# Only codex is a command; the host is an implementation detail the link farm must not export.
sh "$SHIPYARD/stage_product.sh" --stage "$ROOT" --product codex-cli --name "Codex CLI for Mavericks" --version "$V" \
  --exclude bin/codex-code-mode-host \
  --scripts-out "$work/scripts" --updater-app "$APP" >&2
sh "$SHIPYARD/build_component_pkg.sh" --root "$ROOT" --identifier dev.mavergreen.codex-cli \
  --version "$V" --install-location / --scripts "$work/scripts" --out "$work/codex-cli-component.pkg" >&2
mkdir -p "$OUTDIR"
OUT=$OUTDIR/codex-cli-$V.pkg
sh "$SHIPYARD/set_install_floor.sh" --identifier dev.mavergreen.codex-cli --title "Codex CLI for Mavericks" \
  --component "$work/codex-cli-component.pkg" --out "$OUT" --require-scripts --host-arch x86_64 >&2
echo "$OUT"
