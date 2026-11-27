#!/bin/sh
# platform: host-agnostic -- shasum or sha256sum, cmp and grep; runs on Linux, 10.9 and modern macOS
#   usage: compare-builds.sh [--path P]... DIR_A DIR_B
#          Two builds of one input set are the same build only when every file under DIR_A has the
#          same bytes under DIR_B and neither has a file the other lacks. Prints one line per file:
#          "same REL SHA256", "differs REL: N bytes differ" (with each --path P counted in both copies,
#          so an embedded build root or home shows) or "only in DIR: REL". Exit 0 the same, 1 different,
#          2 misuse.
# spec: the family build-twice check: a build is reproducible when two builds of one input set compare the same here; kept standalone so shipyard can lift it
set -eu
usage() { echo "usage: compare-builds.sh [--path P]... DIR_A DIR_B" >&2; exit 2; }
paths=
while [ $# -gt 0 ]; do
  case "$1" in
    --path) [ $# -ge 2 ] || usage; paths="$paths
$2"; shift 2 ;;
    --) shift; break ;;
    -*) usage ;;
    *) break ;;
  esac
done
[ $# -eq 2 ] && [ -d "$1" ] && [ -d "$2" ] || usage
A=$1 B=$2
if command -v sha256sum > /dev/null 2>&1; then sha() { sha256sum < "$1" | cut -c1-64; }
else sha() { shasum -a 256 < "$1" | cut -c1-64; }; fi
files() { ( cd "$1" && find . -type f | sed 's,^\./,,' | LC_ALL=C sort ); }
la=$(files "$A") || exit 2
lb=$(files "$B") || exit 2
rc=0
list=$(mktemp "${TMPDIR:-/tmp}/compare-builds.XXXXXX")
trap 'rm -f "$list"' EXIT
printf '%s\n%s\n' "$la" "$lb" | LC_ALL=C sort -u | sed '/^$/d' > "$list"
while IFS= read -r rel; do
  if [ ! -f "$A/$rel" ]; then echo "only in $B: $rel"; rc=1; continue; fi
  if [ ! -f "$B/$rel" ]; then echo "only in $A: $rel"; rc=1; continue; fi
  sa=$(sha "$A/$rel"); sb=$(sha "$B/$rel")
  if [ "$sa" = "$sb" ]; then echo "same $rel $sa"; continue; fi
  rc=1
  n=$(cmp -l "$A/$rel" "$B/$rel" 2>/dev/null | wc -l | tr -d ' ')
  echo "differs $rel: $n bytes differ ($(wc -c < "$A/$rel" | tr -d ' ') and $(wc -c < "$B/$rel" | tr -d ' ') bytes long)"
  printf '%s\n' "$paths" | while IFS= read -r p; do
    [ -n "$p" ] || continue
    for d in "$A" "$B"; do
      c=$(grep -a -o -F -e "$p" "$d/$rel" | wc -l | tr -d ' ')
      [ "$c" -eq 0 ] || echo "  $rel in $d names $p $c times"
    done
  done
done < "$list"
exit "$rc"
