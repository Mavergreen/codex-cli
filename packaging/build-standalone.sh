#!/bin/sh
# platform: host-agnostic -- shipyard's stage_standalone.sh, fetch_product_pkg.sh and check-standalone-archive.sh run on any host
#   usage: build-standalone.sh VERSION OUT-DIR
#          The standalone archive, the release's primary form: OUT-DIR/codex-cli-VERSION-macos-x86_64.tar.gz,
#          whose path it prints. VERSION is the release's YYYYMMDD.N. It holds tree/ as committed at
#          HEAD (the launcher, the installer, the key and the pins), less the pkg-only libexec/mavergreen,
#          plus the README, share/codex-cli/version, and each requirement packaging/codex-cli.standalone-bundled
#          names, unpacked from that product's pinned release (components/SHORT/version) without its
#          manifest. Unpacked anywhere, it runs Codex with nothing else from Mavergreen.
#          build-pkg.sh derives the pkg from it. CODEX_STANDALONE_BUNDLES=DIR takes each SHORT's tree from
#          DIR/SHORT instead of its release (the tests).
set -eu
U="usage: build-standalone.sh VERSION OUT-DIR"
[ $# -eq 2 ] || { echo "$U" >&2; exit 2; }
V=$1
OUTDIR=$2
REPO=$(cd "$(dirname "$0")/.." && pwd)
# spec: shipyard scripts/source-date-epoch.sh -- the archive's mtime is this repo's commit time
export MAVERICKS_ROOT="${MAVERICKS_ROOT:-$REPO}"
die() { echo "build-standalone: $*" >&2; exit 1; }
. "$REPO/build/msc.sh"
printf '%s\n' "$V" | grep -Eq '^[0-9]{8}\.[1-9][0-9]*$' || die "version '$V' is not YYYYMMDD.N"
[ -s "$REPO/README.md" ] || die "no $REPO/README.md"
work=$(mktemp -d "${TMPDIR:-/tmp}/codex-cli-standalone.XXXXXX")
trap 'rm -rf "$work"' EXIT
ROOT=$work/root
T=$ROOT/usr/local/mavergreen/codex-cli
install -d "$T" "$T/share/doc/codex-cli"
if command -v git >/dev/null 2>&1 && git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
  if [ -n "$(git -C "$REPO" status --porcelain -- tree)" ]; then
    echo "build-standalone: tree/ has uncommitted changes, which this archive leaves out (it stages tree/ as committed at HEAD)" >&2
  fi
  git -C "$REPO" archive -o "$work/tree.tar" HEAD tree
  tar -xf "$work/tree.tar" -C "$work"
  rm -f "$work/tree.tar"
  cp -Rp "$work/tree/." "$T/"
  rm -rf "$work/tree"
else
  echo "build-standalone: no git here; staging tree/ as it is on disk, tracked or not" >&2
  cp -Rp "$REPO/tree/." "$T/"
fi
# spec: shipyard scripts/derive_pkg_tree.sh -- the uninstall hook names the install location; only the pkg carries it
rm -rf "$T/libexec/mavergreen"
# spec: INGREDIENTS.md "Packaging" -- the installed README is the repo's own, as in mavergreen-gh, so the
#       archive and the pkg derived from it carry whatever the maintainer's edit of it leaves
install -m 0644 "$REPO/README.md" "$T/share/doc/codex-cli/README.md"
printf '%s\n' "$V" > "$T/share/codex-cli/version"
while read -r short path || [ -n "$short" ]; do
  [ -n "$short" ] || continue
  if [ -n "${CODEX_STANDALONE_BUNDLES:-}" ]; then
    [ -d "$CODEX_STANDALONE_BUNDLES/$short" ] || die "no $short in CODEX_STANDALONE_BUNDLES ($CODEX_STANDALONE_BUNDLES)"
    src="$CODEX_STANDALONE_BUNDLES/$short"
  else
    pin="$REPO/components/$short/version"
    [ -f "$pin" ] || die "no components/$short/version to bundle $short from"
    src="$work/fetched/$short"
    mkdir -p "$work/fetched"
    sh "$SHIPYARD_SCRIPTS/fetch_product_pkg.sh" "$short" "$(tr -d '[:space:]' < "$pin")" "$src" >/dev/null
  fi
  mkdir -p "$T/$path"
  cp -Rp "$src/." "$T/$path/"
  rm -f "$T/$path/mavergreen.plist"
done < "$REPO/packaging/codex-cli.standalone-bundled"
find "$ROOT" -name '._*' -delete
mkdir -p "$OUTDIR"
OUT=$OUTDIR/codex-cli-$V-macos-x86_64.tar.gz
sh "$SHIPYARD_SCRIPTS/stage_standalone.sh" "$ROOT" codex-cli "$V" x86_64 "$OUT" >&2
sh "$SHIPYARD_SCRIPTS/check-standalone-archive.sh" "$OUT" >&2 || { rm -f "$OUT"; die "check-standalone-archive.sh refused $OUT"; }
echo "$OUT"
