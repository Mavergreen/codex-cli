#!/bin/sh
# platform: host-agnostic -- plutil on a Mac (10.9 included), libplist's plistutil on Linux
#   usage: decl-plist.sh JSON OUT     writes OUT: the provider declaration JSON as an xml1 plist, which
#                                     `stevedore plist get` reads by KEY:INDEX:KEY paths
#          decl-plist.sh --tool       prints the converter, and on Linux its version, for the build manifest
#          Exit 0 written, 1 no converter or not JSON (OUT is then absent), 2 misuse. CODEX_DECL_HOST
#          replaces `uname -s` (test-only).
# spec: INGREDIENTS.md "Deviations" -- interim until drydock-objc ships a schema-aware manifest query
set -eu
host=${CODEX_DECL_HOST:-$(uname -s)}
need_plistutil() {
  command -v plistutil > /dev/null 2>&1 || { echo "decl-plist: no plistutil: install libplist-utils" >&2; exit 1; }
}
if [ "${1:-}" = --tool ] && [ $# -eq 1 ]; then
  if [ "$host" = Linux ]; then need_plistutil; plistutil --version | head -n 1; else echo plutil; fi
  exit 0
fi
[ $# -eq 2 ] || { echo "usage: decl-plist.sh JSON OUT | --tool" >&2; exit 2; }
rm -f "$2"
if [ "$host" = Linux ]; then
  need_plistutil
  plistutil -i "$1" -o "$2" -f xml > /dev/null 2>&1 || { rm -f "$2"; echo "decl-plist: plistutil cannot read $1 as JSON" >&2; exit 1; }
else
  plutil -convert xml1 -o "$2" "$1" > /dev/null 2>&1 || { rm -f "$2"; echo "decl-plist: plutil cannot read $1 as JSON" >&2; exit 1; }
fi
[ -s "$2" ] || { rm -f "$2"; echo "decl-plist: no plist from $1" >&2; exit 1; }
