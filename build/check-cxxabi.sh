#!/bin/sh
# platform: macOS-only -- shipyard's macho-cxxabi.sh and cxxabi-allowlist.sh, with clang-22's llvm tools (fetch-clang-22.sh)
#   usage: [NM=..] [LIPO=..] [OTOOL=..] [AR=..] [CODEX_CXXABI_RECAULK_ARCHIVE=<librecaulk.a>] check-cxxabi.sh BINARY
#          One C++ runtime per Codex binary: exit 0 when BINARY defines no C++ runtime machinery beyond
#          what Recaulk back-fills (shipyard's cxxabi-allowlist.sh, from the Recaulk shipyard pins unless
#          CODEX_CXXABI_RECAULK_ARCHIVE names an archive) and loads no libc++abi but /usr/lib/libc++abi.dylib.
#          Exit 1 printing each offending line, or when BINARY cannot be read; 2 on a usage error.
#          With NM unset, NM/LIPO/OTOOL/AR are the pinned clang-22's (clang22-cross on Apple Silicon).
#          Artifact conformance holds a pkg to the same rule; the Codex binaries come from the builds
#          channel, not the pkg, so conformance never reads them.
set -eu
[ "$#" -eq 1 ] || { echo "usage: check-cxxabi.sh BINARY" >&2; exit 2; }
BINARY=$1
: "${SHIPYARD_SCRIPTS:?check-cxxabi: SHIPYARD_SCRIPTS names no shipyard scripts directory}"
if [ -z "${NM:-}" ]; then
  HERE=$(cd "$(dirname "$0")" && pwd)
  product=clang22
  [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = 1 ] && product=clang22-cross
  bin="$(sh "$HERE/fetch-clang-22.sh" "$product")/bin" || exit 1
  NM="$bin/llvm-nm" LIPO="$bin/llvm-lipo" OTOOL="$bin/llvm-otool" AR="$bin/llvm-ar"
fi
export NM LIPO="${LIPO:-llvm-lipo}" OTOOL="${OTOOL:-llvm-otool}" AR="${AR:-llvm-ar}"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/check-cxxabi.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

sh "$SHIPYARD_SCRIPTS/macho-cxxabi.sh" "$BINARY" > "$WORK/found" || {
  echo "check-cxxabi: cannot read the C++ runtime symbols of $BINARY" >&2; exit 1;
}

bad=no
if grep -q ' defines ' "$WORK/found"; then
  # shellcheck disable=SC2086
  sh "$SHIPYARD_SCRIPTS/cxxabi-allowlist.sh" ${CODEX_CXXABI_RECAULK_ARCHIVE:+"$CODEX_CXXABI_RECAULK_ARCHIVE"} \
    > "$WORK/allow" || { echo "check-cxxabi: no Recaulk allow-list (cxxabi-allowlist.sh failed)" >&2; exit 1; }
  # spec: shipyard scripts/artifact-facts.sh cxxabi_allowlist -- the pointer-catch vtables are allowed hidden only
  awk '$1 == "__ZTVN10__cxxabiv119__pointer_type_infoE" || $1 == "__ZTVN10__cxxabiv129__pointer_to_member_type_infoE" { $2 = "hidden" } 1' \
    "$WORK/allow" > "$WORK/allowed"
  awk 'NR == FNR { a[$1] = $2; next }
       $2 == "defines" && !(($3 in a) && (a[$3] == "visible" || a[$3] == $4)) { print }' \
    "$WORK/allowed" "$WORK/found" > "$WORK/defines"
  [ ! -s "$WORK/defines" ] || bad=yes
fi
: > "$WORK/loads"
while read -r arch kind what; do
  [ "$kind" = loads ] || continue
  [ "$what" = /usr/lib/libc++abi.dylib ] || printf '%s loads %s\n' "$arch" "$what" >> "$WORK/loads"
done < "$WORK/found"
[ ! -s "$WORK/loads" ] || bad=yes

if [ "$bad" = yes ]; then
  echo "check-cxxabi: $BINARY carries a C++ runtime besides the system's libc++abi and Recaulk:" >&2
  cat "$WORK/defines" "$WORK/loads" 2>/dev/null | sed 's/^/  /' >&2
  exit 1
fi
echo "check-cxxabi: one C++ runtime in $BINARY"
