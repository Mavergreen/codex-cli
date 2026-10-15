#!/bin/sh
# platform: macOS-only -- validates a transferred artifact with otool and file; modern macOS or Mavericks
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
# spec: a `._` AppleDouble member (made by bsdtar on macOS 27) is a sixth member, so this count and the
#       five named checks below already refuse it; no separate `._` check is needed.
member_count=$(printf '%s\n' "$members" | awk 'NF { n++ } END { print n+0 }')
[ "$member_count" -eq 5 ] || { echo "verify-artifact: archive must contain exactly codex, codex-code-mode-host, build-manifest, LICENSE and NOTICE" >&2; exit 1; }
printf '%s\n' "$members" | grep -qx codex || { echo "verify-artifact: archive has no codex executable" >&2; exit 1; }
printf '%s\n' "$members" | grep -qx codex-code-mode-host || { echo "verify-artifact: archive has no codex-code-mode-host executable" >&2; exit 1; }
printf '%s\n' "$members" | grep -qx build-manifest || { echo "verify-artifact: archive has no build-manifest" >&2; exit 1; }
for notice in LICENSE NOTICE; do
  printf '%s\n' "$members" | grep -qx "$notice" || { echo "verify-artifact: archive has no $notice" >&2; exit 1; }
done

for member in codex codex-code-mode-host; do
  tar -tvf "$ARCHIVE" | awk -v member="$member" '
    $NF == member {
      mode = $1
      if (substr(mode, 4, 1) == "x" || substr(mode, 7, 1) == "x" || substr(mode, 10, 1) == "x") found = 1
    }
    END { exit !found }
  ' || { echo "verify-artifact: $member executable bit is missing" >&2; exit 1; }
done

BUILD_ROOT=$(sh "$HERE/resolve-build-root.sh")
TMP="$BUILD_ROOT/verify-artifact.$$"
mkdir "$TMP"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
tar -xOf "$ARCHIVE" build-manifest > "$TMP/build-manifest"
tar -xOf "$ARCHIVE" codex > "$TMP/codex"
tar -xOf "$ARCHIVE" codex-code-mode-host > "$TMP/codex-code-mode-host"

field() { sed -n "s/^$1=//p" "$TMP/build-manifest"; }
target=$(field target)
deployment_target=$(field deployment_target)
source_revision=$(field source_revision)
rust_version=$(field rust_version)
rusty_v8_version=$(field rusty_v8_version)
[ "$target" = "$EXPECTED_TARGET" ] || { echo "verify-artifact: target mismatch ($target)" >&2; exit 1; }
[ "$deployment_target" = 10.9 ] || { echo "verify-artifact: deployment target must be 10.9" >&2; exit 1; }
[ "$source_revision" = "$(tr -d '[:space:]' < "$HERE/codex-revision")" ] || {
  echo "verify-artifact: Codex source revision mismatch" >&2; exit 1;
}
[ "$rust_version" = "$(tr -d '[:space:]' < "$PRODUCT_ROOT/components/rust/version")" ] || {
  echo "verify-artifact: Rust toolchain version mismatch" >&2; exit 1;
}
case "$rusty_v8_version" in
  ''|*[!0-9.]*|.*) echo "verify-artifact: malformed rusty_v8_version ($rusty_v8_version)" >&2; exit 1 ;;
esac
for member in codex codex-code-mode-host; do
  # platform: upstream file(1), as pkgsrc ships it, prints "Mach-O 64-bit x86_64 executable".
  #           Apple's /usr/bin/file, on 10.9 and on modern macOS, prints "Mach-O 64-bit
  #           executable x86_64".
  file -b "$TMP/$member" | grep -Eq 'Mach-O 64-bit (x86_64 executable|executable x86_64)' || {
    echo "verify-artifact: $member is not an x86_64 Mach-O executable" >&2; exit 1;
  }
done
sh "$HERE/check-load-paths.sh" "$TMP/codex" "$TMP/codex-code-mode-host" || {
  echo "verify-artifact: a member loads a library from outside the OS" >&2; exit 1;
}
echo "verify-artifact: ok ($target, macOS $deployment_target)"
