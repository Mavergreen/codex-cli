#!/bin/sh
# platform: macOS-only -- drives shipyard's stage_product.sh, build_component_pkg.sh and set_install_floor.sh
#   usage: build-pkg.sh UPDATER-APP VERSION OUT-DIR STANDALONE-ARCHIVE
#          VERSION is the pkg's own YYYYMMDD.N. The pkg is derived from the standalone archive
#          build-standalone.sh made for VERSION: shipyard's stage_pkg_from_archive.sh checks it, drops
#          the requirements it bundles (the pkg requires their products instead) and adds
#          tree/libexec/mavergreen as committed at HEAD. The result is tree/ (the launcher, the installer and the requires, AquaTransport pin
#          and key under share/codex-cli, upstream's LICENSE and NOTICE) with the README and the
#          version file, under /usr/local/mavergreen/codex-cli. With the updater it is wrapped in a
#          10.9.5-floored product archive, OUT-DIR/codex-cli-VERSION.pkg, whose path it prints. The
#          pkg carries no Codex binary: those arrive through the builds channel, by the installer.
set -eu
U="usage: build-pkg.sh UPDATER-APP VERSION OUT-DIR STANDALONE-ARCHIVE"
[ $# -eq 4 ] || { echo "$U" >&2; exit 2; }
APP=$1
V=$2
OUTDIR=$3
SA=$4
REPO=$(cd "$(dirname "$0")/.." && pwd)
# spec: shipyard scripts/source-date-epoch.sh -- the pkg's mtime is this repo's commit time, wherever
#       build-pkg.sh is run from, unless the caller names SOURCE_DATE_EPOCH or MAVERICKS_ROOT
export MAVERICKS_ROOT="${MAVERICKS_ROOT:-$REPO}"
die() { echo "build-pkg: $*" >&2; exit 1; }
. "$REPO/build/msc.sh"
printf '%s\n' "$V" | grep -Eq '^[0-9]{8}\.[1-9][0-9]*$' || die "version '$V' is not YYYYMMDD.N"
[ -s "$REPO/README.md" ] || die "no $REPO/README.md"
[ -d "$APP" ] || die "no updater $APP; configure with -DCODEX_BUILD_UPDATER=ON"
work=$(mktemp -d "${TMPDIR:-/tmp}/codex-cli-pkg.XXXXXX")
trap 'rm -rf "$work"' EXIT
ROOT=$work/root
T=$ROOT/usr/local/mavergreen/codex-cli
mkdir -p "$ROOT"
[ "${SA##*/}" = "codex-cli-$V-macos-x86_64.tar.gz" ] || die "$SA is not codex-cli-$V-macos-x86_64.tar.gz"
[ -f "$SA" ] || die "no standalone archive at $SA"
if command -v git >/dev/null 2>&1 && git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$REPO" archive -o "$work/hooks.tar" HEAD tree/libexec/mavergreen tree/share/codex-cli/requires
  tar -xf "$work/hooks.tar" -C "$work"
  rm -f "$work/hooks.tar"
else
  mkdir -p "$work/tree/libexec" "$work/tree/share/codex-cli"
  cp -Rp "$REPO/tree/libexec/mavergreen" "$work/tree/libexec/"
  cp -p "$REPO/tree/share/codex-cli/requires" "$work/tree/share/codex-cli/"
fi
[ -f "$work/tree/share/codex-cli/requires" ] || die "tree/share/codex-cli/requires is missing"
set --
while read -r short _url || [ -n "$short" ]; do
  [ -n "$short" ] || continue
  set -- "$@" --requires "$short"
done < "$work/tree/share/codex-cli/requires"
[ $# -gt 0 ] || die "tree/share/codex-cli/requires names no product"
REQS="$*"
sh "$SHIPYARD/stage_pkg_from_archive.sh" --repo "$REPO" "$@" \
  --pkg-only "$work/tree/libexec/mavergreen=libexec/mavergreen" \
  "$SA" "$REPO/packaging/codex-cli.standalone-bundled" "$ROOT" >&2
[ "$(tr -d '[:space:]' < "$T/share/codex-cli/version")" = "$V" ] || die "the archive's share/codex-cli/version is not $V"
find "$ROOT" -name '._*' -delete
# spec: the pkg is the launcher, the installer and the updater; Codex itself arrives through the
#       builds channel. Scan everything staged: refuse any Mach-O file, any file called codex or
#       codex-code-mode-host but the launcher script at bin/codex, and Codex's resource names. Only
#       the updater bundle's own executables are exempt (stage_product adds them, so none is staged yet).
UPD="$ROOT/Library/Application Support/Mavergreen/codex-cli-updater.app"
find "$ROOT" -path "$UPD" -prune -o \( -type f -o -type l \) -print > "$work/staged"
[ -f "$T/bin/codex" ] && [ ! -L "$T/bin/codex" ] || die "tree/bin/codex is missing"
[ "$(head -n 1 "$T/bin/codex")" = "#!/bin/sh" ] || die "tree/bin/codex is not the launcher script"
while IFS= read -r f; do
  case "$f" in
    "$T/bin/codex") ;;
    */codex|*/codex-code-mode-host) die "${f#"$ROOT"/}: a Codex binary; the pkg carries none" ;;
  esac
  [ -L "$f" ] && continue
  case "$(od -An -tx1 -N4 "$f" | tr -d ' \n')" in
    cffaedfe|cefaedfe|feedfacf|feedface|cafebabe|bebafeca) die "${f#"$ROOT"/}: a Mach-O file; the pkg carries none" ;;
  esac
done < "$work/staged"
[ -z "$(find "$ROOT" \( -name codex-resources -o -name codex-path \) | head -n 1)" ] \
  || die "the payload holds Codex's resources; the pkg carries none"
# shellcheck disable=SC2086
set -- $REQS
# Only bin/codex is a command, and tree/bin holds nothing else, so the link farm exports it alone.
sh "$SHIPYARD/stage_product.sh" --stage "$ROOT" --product codex-cli --name "Codex CLI for Mavericks" --version "$V" \
  "$@" --scripts-out "$work/scripts" --updater-app "$APP" >&2
sh "$SHIPYARD/build_component_pkg.sh" --root "$ROOT" --identifier dev.mavergreen.codex-cli \
  --version "$V" --install-location / --scripts "$work/scripts" --out "$work/codex-cli-component.pkg" >&2
mkdir -p "$OUTDIR"
OUT=$OUTDIR/codex-cli-$V.pkg
sh "$SHIPYARD/set_install_floor.sh" --identifier dev.mavergreen.codex-cli --title "Codex CLI for Mavericks" \
  --component "$work/codex-cli-component.pkg" --out "$OUT" --require-scripts --host-arch x86_64 >&2
echo "$OUT"
