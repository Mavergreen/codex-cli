#!/bin/sh
# platform: host-agnostic -- plain sh, cp -R and find; runs on Linux, 10.9 and modern macOS
#   usage: derive-pkg-tree.sh [--pkg-only SRC=DEST]... STANDALONE_TREE BUNDLED_LIST OUT_TREE
#          The pkg's tree, derived from the standalone archive's: a copy of STANDALONE_TREE without
#          the requirements the archive bundles, plus the files only the pkg carries. BUNDLED_LIST
#          has one line per bundled requirement, "SHORT PATH": the product's short name and its
#          directory, relative to the tree. The pkg declares SHORT as a requirement instead of
#          carrying it. Each --pkg-only copies SRC to DEST, relative to OUT_TREE (an uninstall
#          hook, which names the install location and so has no place in a relocatable archive).
#          Every PATH must be in STANDALONE_TREE. A directory the removals leave empty goes too.
#          Nothing else changes, so the pkg differs from the archive only by these declared steps.
#          OUT_TREE must not exist; a failed run leaves none. Exit 1 when a bundled PATH is
#          missing, 2 on a usage error, a bad list line, a missing SRC or an existing OUT_TREE.
# spec: tests/derive-pkg-tree-test.sh
set -eu
usage='usage: derive-pkg-tree.sh [--pkg-only SRC=DEST]... STANDALONE_TREE BUNDLED_LIST OUT_TREE'
die() { echo "derive-pkg-tree: $1" >&2; exit "$2"; }
good_rel() {
  case "$1" in ''|.|/*|..|../*|*/..|*/../*|*/.|./*|*/./*) return 1 ;; esac
}
adds=""
nadd=0
while [ "${1-}" = --pkg-only ]; do
  [ $# -ge 2 ] || { echo "$usage" >&2; exit 2; }
  src="${2%%=*}" dest="${2#*=}"
  [ "$src" != "$2" ] || die "--pkg-only takes SRC=DEST, not '$2'" 2
  [ -e "$src" ] || die "--pkg-only source '$src' does not exist" 2
  good_rel "$dest" || die "--pkg-only destination '$dest' is not a path inside the tree" 2
  nadd=$((nadd+1))
  eval "add_src_$nadd=\$src add_dest_$nadd=\$dest"
  shift 2
done
[ $# -eq 3 ] || { echo "$usage" >&2; exit 2; }
SA="${1%/}" LIST="$2" OUT="${3%/}"
[ -d "$SA" ] || die "no standalone tree at $SA" 2
[ -f "$LIST" ] || die "no bundled list at $LIST" 2
{ [ -e "$OUT" ] || [ -L "$OUT" ]; } && die "$OUT already exists" 2

n=0
while read -r short path extra || [ -n "$short" ]; do
  [ -n "$short" ] || continue
  [ -n "${path-}" ] && [ -z "${extra-}" ] || die "$LIST: '$short${path:+ $path}${extra:+ $extra}' is not 'SHORT PATH'" 2
  case "$short" in -*|*[!a-z0-9-]*) die "$LIST: '$short' is not a short name" 2 ;; esac
  good_rel "$path" || die "$LIST: $short: '$path' is not a path inside the tree" 2
done < "$LIST"
while read -r short path || [ -n "$short" ]; do
  [ -n "$short" ] || continue
  [ -e "$SA/$path" ] || die "$short: $path is not in $SA" 1
  n=$((n+1))
done < "$LIST"

work="$OUT.derive.$$"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work"
cp -Rp "$SA/." "$work/"
while read -r short path || [ -n "$short" ]; do
  [ -n "$short" ] || continue
  rm -rf "$work/$path"
  d="$(dirname "$path")"
  while [ "$d" != . ] && rmdir "$work/$d" 2>/dev/null; do d="$(dirname "$d")"; done
done < "$LIST"
i=1
while [ "$i" -le "$nadd" ]; do
  eval "src=\$add_src_$i dest=\$add_dest_$i"
  mkdir -p "$work/$(dirname "$dest")"
  cp -Rp "$src" "$work/$dest"
  i=$((i+1))
done
mv "$work" "$OUT"
trap - EXIT
echo "derive-pkg-tree: dropped $n bundled requirement(s), added $nadd pkg-only path(s)" >&2
