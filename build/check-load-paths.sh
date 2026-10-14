#!/bin/sh
# platform: modern macOS or Mavericks -- otool -l lists load commands the same way on both.
#   usage: check-load-paths.sh BINARY...   exits 0 when every BINARY loads libraries only from
#          /usr/lib/ and /System/Library/ and has no LC_RPATH; 1 if one does not; 2 on misuse
# platform: interim, until shipyard's family guard checks load paths. assert_binary_compatible.sh
#           checks arches, minos, SDK and imports, not where libraries load from, and it passed a
#           codex that loaded ultimate-hat's pkgsrc /opt/pkg/lib/liblzma.5.dylib.
set -eu

[ "$#" -ge 1 ] || { echo "usage: check-load-paths.sh BINARY..." >&2; exit 2; }
rc=0
for binary in "$@"; do
  [ -f "$binary" ] || { echo "check-load-paths: not a file: $binary" >&2; exit 2; }
  # platform: otool -l exits 0 on a file that is not Mach-O, after saying so.
  commands=$(otool -l "$binary") || { echo "check-load-paths: otool cannot read $binary" >&2; exit 1; }
  case "$commands" in
    *"is not an object file"*) echo "check-load-paths: $binary is not a Mach-O file" >&2; exit 1 ;;
  esac
  refused=$(printf '%s\n' "$commands" | awk '
    $1 == "cmd" { cmd = $2; next }
    $1 == "name" && cmd ~ /^LC_(LOAD|LOAD_WEAK|REEXPORT|LAZY_LOAD|LOAD_UPWARD)_DYLIB$/ {
      path = $0
      sub(/^[ \t]*name /, "", path); sub(/ \(offset [0-9]+\)$/, "", path)
      if (path !~ /^\/(usr\/lib|System\/Library)\// || path ~ /\/\.\.\//)
        print cmd " " path " is outside /usr/lib/ and /System/Library/"
      next
    }
    $1 == "path" && cmd == "LC_RPATH" {
      path = $0
      sub(/^[ \t]*path /, "", path); sub(/ \(offset [0-9]+\)$/, "", path)
      print cmd " " path " (an rpath can reach any directory)"
    }
  ')
  [ -n "$refused" ] || continue
  rc=1
  printf '%s\n' "$refused" | awk -v binary="$binary" '{ print "check-load-paths: " binary ": " $0 }' >&2
done
exit "$rc"
