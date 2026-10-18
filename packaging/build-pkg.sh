#!/bin/sh
# platform: macOS-only -- drives shipyard's stage_product.sh, build_component_pkg.sh and set_install_floor.sh
#   usage: build-pkg.sh UPDATER-APP VERSION OUT-DIR
#          VERSION is the pkg's own YYYYMMDD.N. Stages tree/ as committed at HEAD (the launcher, the
#          installer and the requires, AquaTransport pin and key under share/codex-cli, upstream's
#          LICENSE and NOTICE), the README and the updater under /usr/local/mavergreen/codex-cli, and
#          wraps them in a 10.9.5-floored product archive, OUT-DIR/codex-cli-VERSION.pkg, whose path it prints. The
#          pkg carries no Codex binary: those arrive through the builds channel, by the installer.
set -eu
U="usage: build-pkg.sh UPDATER-APP VERSION OUT-DIR"
[ $# -eq 3 ] || { echo "$U" >&2; exit 2; }
APP=$1
V=$2
OUTDIR=$3
REPO=$(cd "$(dirname "$0")/.." && pwd)
die() { echo "build-pkg: $*" >&2; exit 1; }
. "$REPO/build/msc.sh"
printf '%s\n' "$V" | grep -Eq '^[0-9]{8}\.[1-9][0-9]*$' || die "version '$V' is not YYYYMMDD.N"
[ -s "$REPO/README.md" ] || die "no $REPO/README.md"
[ -d "$APP" ] || die "no updater $APP; configure with -DCODEX_BUILD_UPDATER=ON"
work=$(mktemp -d "${TMPDIR:-/tmp}/codex-cli-pkg.XXXXXX")
trap 'rm -rf "$work"' EXIT
ROOT=$work/root
T=$ROOT/usr/local/mavergreen/codex-cli
install -d "$T" "$T/share/doc/codex-cli"
if command -v git >/dev/null 2>&1 && git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
  if [ -n "$(git -C "$REPO" status --porcelain -- tree)" ]; then
    echo "build-pkg: tree/ has uncommitted changes, which this package leaves out (it stages tree/ as committed at HEAD)" >&2
  fi
  git -C "$REPO" archive -o "$work/tree.tar" HEAD tree
  tar -xf "$work/tree.tar" -C "$work"
  rm -f "$work/tree.tar"
  cp -Rp "$work/tree/." "$T/"
  rm -rf "$work/tree"
else
  echo "build-pkg: no git here; staging tree/ as it is on disk, tracked or not" >&2
  cp -Rp "$REPO/tree/." "$T/"
fi
# spec: INGREDIENTS.md "Packaging" -- the installed README is the repo's own, as in mavergreen-gh, so the
#       pkg carries whatever the maintainer's edit of it leaves
install -m 0644 "$REPO/README.md" "$T/share/doc/codex-cli/README.md"
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
[ -f "$T/share/codex-cli/requires" ] || die "tree/share/codex-cli/requires is missing"
set --
while read -r short _url || [ -n "$short" ]; do
  [ -n "$short" ] || continue
  set -- "$@" --requires "$short"
done < "$T/share/codex-cli/requires"
[ $# -gt 0 ] || die "tree/share/codex-cli/requires names no product"
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
