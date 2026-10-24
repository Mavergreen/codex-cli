#!/bin/sh
# platform: host-agnostic -- plain sh; runs on ultimate-hat and modern macOS
#   usage: codex-pin.sh version|tag|revision|repository [PIN-FILE]
#          Prints one field of the Codex pin, components/codex/version (or PIN-FILE): REPO, REF and
#          DIGEST lines, as the family pins a tag with its commit. tag is REF, rust-v<x.y.z>; version
#          is its x.y.z; revision is DIGEST, the tag's commit; repository is REPO. The pin is refused
#          unless REF is a stable rust-v<x.y.z>, because the family version <x.y.z>-mavericks.N and
#          the updater's comparison order only hold for one, and DIGEST a full lowercase commit SHA.
set -eu
FIELD=${1:-}
case "$FIELD" in
  version|tag|revision|repository) ;;
  *) echo "usage: codex-pin.sh version|tag|revision|repository [PIN-FILE]" >&2; exit 2 ;;
esac
PIN=${2:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/components/codex/version}
NAME=components/codex/version
[ -f "$PIN" ] || { echo "codex-pin: no $NAME" >&2; exit 1; }

value() {
  count=$(grep -c "^$1=" "$PIN" || :)
  [ "$count" -eq 1 ] || { echo "codex-pin: $NAME must have exactly one $1= line" >&2; exit 1; }
  sed -n "s/^$1=//p" "$PIN" | tr -d '[:space:]'
}
REPO=$(value REPO)
TAG=$(value REF)
REVISION=$(value DIGEST)

VERSION=${TAG#rust-v}
case "$TAG" in
  rust-v[0-9]*.[0-9]*.[0-9]*) ;;
  *) echo "codex-pin: $NAME REF '$TAG' is not a stable rust-v<x.y.z>" >&2; exit 1 ;;
esac
case "$VERSION" in
  *[!0-9.]*|*..*|.*|*.) echo "codex-pin: $NAME REF '$TAG' is not a stable rust-v<x.y.z> (a prerelease or other suffix has no order-preserving -mavericks.N form)" >&2; exit 1 ;;
esac
case "$REVISION" in
  ''|*[!0-9a-f]*) echo "codex-pin: $NAME DIGEST is not a lowercase hex commit SHA" >&2; exit 1 ;;
esac
[ "${#REVISION}" -eq 40 ] || { echo "codex-pin: $NAME DIGEST must be a full 40-digit commit SHA" >&2; exit 1; }
[ -n "$REPO" ] || { echo "codex-pin: $NAME REPO is empty" >&2; exit 1; }

case "$FIELD" in
  version) printf '%s\n' "$VERSION" ;;
  tag) printf '%s\n' "$TAG" ;;
  revision) printf '%s\n' "$REVISION" ;;
  repository) printf '%s\n' "$REPO" ;;
esac
