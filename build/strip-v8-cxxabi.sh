#!/bin/sh
# platform: host-agnostic -- llvm-ar, llvm-nm and shipyard's cxxabi-machinery.txt; runs on ultimate-hat and modern macOS
#   usage: [AR=<llvm-ar>] [NM=<llvm-nm>] strip-v8-cxxabi.sh IN OUT
#          strip-v8-cxxabi.sh --list
#          Writes OUT, a copy of IN (OpenAI's rusty_v8 archive, plain or gzipped) without V8's own
#          libc++abi, so codex-code-mode-host uses the system's libc++abi and Recaulk instead. Prints the
#          removed members, one per line, as --list does. Refuses (exit 1, OUT untouched) when a listed member is
#          missing from IN, or when what is left defines a symbol matching shipyard's
#          cxxabi-machinery.txt (any visibility). --list prints the members it removes. Exit 2 on a usage error.
set -eu

MEMBERS="abort_message.pic.o
cxa_aux_runtime.pic.o
cxa_default_handlers.pic.o
cxa_demangle.pic.o
cxa_exception.pic.o
cxa_exception_storage.pic.o
cxa_guard.pic.o
cxa_handlers.pic.o
cxa_personality.pic.o
cxa_vector.pic.o
cxa_virtual.pic.o
fallback_malloc.pic.o
private_typeinfo.pic.o
stdlib_exception.pic.o
stdlib_stdexcept.pic.o
stdlib_typeinfo.pic.o"

usage() { echo "usage: strip-v8-cxxabi.sh IN OUT | --list" >&2; exit 2; }

if [ "$#" -eq 1 ] && [ "$1" = --list ]; then
  printf '%s\n' "$MEMBERS"
  exit 0
fi
[ "$#" -eq 2 ] || usage
IN=$1
OUT=$2
[ -r "$IN" ] || { echo "strip-v8-cxxabi: cannot read $IN" >&2; exit 2; }
: "${SHIPYARD_SCRIPTS:?strip-v8-cxxabi: SHIPYARD_SCRIPTS names no shipyard scripts directory}"
AR=${AR:-llvm-ar}
NM=${NM:-llvm-nm}

WORK=$(mktemp -d "$(dirname -- "$OUT")/.strip-v8-cxxabi.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
case "$(head -c 2 "$IN" | od -An -tx1 | tr -d ' \n')" in
  1f8b) gzip -dc "$IN" > "$WORK/v8.a" ;;
  *) cp "$IN" "$WORK/v8.a" ;;
esac

"$AR" t "$WORK/v8.a" > "$WORK/before"
missing=
for m in $MEMBERS; do
  grep -qxF "$m" "$WORK/before" || missing="$missing $m"
done
[ -z "$missing" ] || {
  echo "strip-v8-cxxabi: $IN lacks members this script removes:$missing (review the list for this V8)" >&2
  exit 1
}

printf '%s\n' "$MEMBERS" > "$WORK/members"
while "$AR" t "$WORK/v8.a" | grep -xF -f "$WORK/members" > "$WORK/present"; do
  # shellcheck disable=SC2046
  "$AR" dD "$WORK/v8.a" $(sort -u "$WORK/present")
done

RULE="$SHIPYARD_SCRIPTS/cxxabi-machinery.txt"
grep -v '^#' "$RULE" 2>/dev/null | grep . > "$WORK/rule" || {
  echo "strip-v8-cxxabi: no machinery pattern in $RULE" >&2; exit 1;
}
(cd "$WORK" && "$NM" -P -A v8.a) > "$WORK/symbols" 2> "$WORK/nm-errors" || {
  echo "strip-v8-cxxabi: $NM could not read the stripped archive:" >&2; cat "$WORK/nm-errors" >&2; exit 1;
}
awk '$3 != "U" && $3 != "u" { print $2 }' "$WORK/symbols" | sort -u > "$WORK/defined"
if grep -E -f "$WORK/rule" "$WORK/defined" > "$WORK/left"; then
  echo "strip-v8-cxxabi: the stripped archive still defines C++ runtime machinery:" >&2
  sed 's/^/  /' "$WORK/left" >&2
  exit 1
fi

mv "$WORK/v8.a" "$OUT"
printf '%s\n' "$MEMBERS"
