#!/bin/sh
# platform: modern macOS or Mavericks -- validates a transferred native artifact.
set -eu

if [ "$#" -ne 3 ]; then
  echo "usage: verify-artifact.sh ARCHIVE SHA256-MANIFEST EXPECTED-TARGET" >&2
  exit 2
fi
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PRODUCT_ROOT=$(CDPATH= cd -- "$HERE/.." && pwd)
ARCHIVE=$1
CHECKSUM=$2
EXPECTED_TARGET=$3

[ -f "$ARCHIVE" ] || { echo "verify-artifact: archive not found: $ARCHIVE" >&2; exit 1; }
[ -f "$CHECKSUM" ] || { echo "verify-artifact: checksum manifest not found: $CHECKSUM" >&2; exit 1; }
[ "$EXPECTED_TARGET" = x86_64-apple-darwin ] || {
  echo "verify-artifact: unsupported expected target: $EXPECTED_TARGET" >&2; exit 1;
}

expected_hash=$(awk 'NR == 1 { print $1 }' "$CHECKSUM")
[ "$(wc -l < "$CHECKSUM" | tr -d '[:space:]')" -eq 1 ] || {
  echo "verify-artifact: SHA-256 manifest must have exactly one line" >&2; exit 1;
}
case "$expected_hash" in
  ''|*[!0-9a-f]*) echo "verify-artifact: invalid SHA-256 manifest" >&2; exit 1 ;;
esac
[ "${#expected_hash}" -eq 64 ] || { echo "verify-artifact: invalid SHA-256 length" >&2; exit 1; }
actual_hash=$(shasum -a 256 "$ARCHIVE" | awk '{ print $1 }')
[ "$actual_hash" = "$expected_hash" ] || { echo "verify-artifact: SHA-256 mismatch" >&2; exit 1; }

members=$(tar -tf "$ARCHIVE") || { echo "verify-artifact: cannot list archive" >&2; exit 1; }
member_count=$(printf '%s\n' "$members" | awk 'NF { n++ } END { print n+0 }')
[ "$member_count" -eq 2 ] || { echo "verify-artifact: archive must contain exactly codex and build-manifest" >&2; exit 1; }
printf '%s\n' "$members" | grep -qx codex || { echo "verify-artifact: archive has no codex executable" >&2; exit 1; }
printf '%s\n' "$members" | grep -qx build-manifest || { echo "verify-artifact: archive has no build-manifest" >&2; exit 1; }

tar -tvf "$ARCHIVE" | awk '
  $NF == "codex" {
    mode = $1
    if (substr(mode, 4, 1) == "x" || substr(mode, 7, 1) == "x" || substr(mode, 10, 1) == "x") found = 1
  }
  END { exit !found }
' || { echo "verify-artifact: codex executable bit is missing" >&2; exit 1; }

BUILD_ROOT=$(sh "$HERE/resolve-build-root.sh")
TMP="$BUILD_ROOT/verify-artifact.$$"
mkdir "$TMP"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
tar -xOf "$ARCHIVE" build-manifest > "$TMP/build-manifest"
tar -xOf "$ARCHIVE" codex > "$TMP/codex"

field() { sed -n "s/^$1=//p" "$TMP/build-manifest"; }
target=$(field target)
deployment_target=$(field deployment_target)
source_revision=$(field source_revision)
rust_revision=$(field rust_revision)
[ "$target" = "$EXPECTED_TARGET" ] || { echo "verify-artifact: target mismatch ($target)" >&2; exit 1; }
[ "$deployment_target" = 10.9 ] || { echo "verify-artifact: deployment target must be 10.9" >&2; exit 1; }
[ "$source_revision" = "$(tr -d '[:space:]' < "$HERE/codex-revision")" ] || {
  echo "verify-artifact: Codex source revision mismatch" >&2; exit 1;
}
[ "$rust_revision" = "$(tr -d '[:space:]' < "$PRODUCT_ROOT/mavericks-rust.pin")" ] || {
  echo "verify-artifact: Rust toolchain revision mismatch" >&2; exit 1;
}
file "$TMP/codex" | grep -q 'Mach-O 64-bit x86_64 executable' || {
  echo "verify-artifact: codex is not an x86_64 Mach-O executable" >&2; exit 1;
}
echo "verify-artifact: ok ($target, macOS $deployment_target)"
