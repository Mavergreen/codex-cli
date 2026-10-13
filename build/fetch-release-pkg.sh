#!/bin/sh
# platform: macOS-only -- pkgutil expands the pkg
#   usage: fetch-release-pkg.sh NAME BASE-URL PKG STEM DIR PREFIX PROBE...
#          The shared body of the Mavergreen release fetchers (fetch-rust.sh, fetch-clang-22.sh).
#          Verifies PKG against BASE-URL/SHA256SUMS, downloads it into DIR, and extracts the
#          payload of its STEM-component.pkg under DIR/root -- never installed, so no root is
#          needed and the build uses exactly the pinned product. Prints DIR/root/PREFIX once every
#          PROBE (a path under that prefix) exists. A DIR already stamped `extracted` with its
#          probes in place is reused without any download. NAME labels the messages.
set -eu
. "$SHIPYARD_SCRIPTS/mavericks_fetch.sh"

[ "$#" -ge 7 ] || { echo "usage: fetch-release-pkg.sh NAME BASE-URL PKG STEM DIR PREFIX PROBE..." >&2; exit 2; }
name=$1 base=$2 pkg=$3 stem=$4 dir=$5 prefix=$6
shift 6
tc="$dir/root/$prefix"

probes_present() {
  for probe in "$@"; do [ -e "$tc/$probe" ] || return 1; done
}
if [ -f "$dir/extracted" ] && probes_present "$@"; then printf '%s\n' "$tc"; exit 0; fi

mkdir -p "$dir"
sums=$(curl -fsSL "$base/SHA256SUMS") || { echo "$name: cannot read $base/SHA256SUMS" >&2; exit 1; }
sha=$(printf '%s\n' "$sums" | awk -v f="$pkg" '$2 == f || $2 == "*" f { print $1 }')
case "$sha" in
  "") echo "$name: $pkg is not listed in $base/SHA256SUMS -- refusing an unverified pkg" >&2; exit 1 ;;
  *[!0-9a-f]*) echo "$name: $pkg is listed more than once in $base/SHA256SUMS" >&2; exit 1 ;;
esac
mav_fetch_verified "$base/$pkg" "$sha" "$dir" "$pkg" || { echo "$name: $pkg failed verification" >&2; exit 1; }

rm -rf "$dir/expanded" "$dir/root" "$dir/extracted"
pkgutil --expand "$dir/$pkg" "$dir/expanded"
payload="$dir/expanded/$stem-component.pkg/Payload"
[ -f "$payload" ] || { echo "$name: $pkg has no $stem-component.pkg payload" >&2; exit 1; }
mkdir -p "$dir/root"
# platform: bsdtar reads a pkg Payload (gzip-compressed cpio) directly, so no pipe can hide a
#           truncated extraction
tar -xf "$payload" -C "$dir/root"
rm -rf "$dir/expanded"
probes_present "$@" || { echo "$name: $pkg holds no $* under $prefix" >&2; exit 1; }
: > "$dir/extracted"
printf '%s\n' "$tc"
