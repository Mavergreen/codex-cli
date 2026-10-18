#!/bin/sh
# platform: host-agnostic -- plain sh; runs on ultimate-hat and modern macOS
#   usage: channel-json.sh --id ID --codex-version X.Y.Z --tarball PATH --min-pkg V --state HEX
#          Prints, on one line, the JSON describing one build on the builds channel. It is shaped like
#          a GitHub release (tag_name, assets[].name and .digest) so the installer's parser reads it.
#          The tarball must be named <prefix>ID.tar.gz (--tarball-prefix, default below).
#          --min-pkg is the oldest package version (YYYYMMDD.N) the build needs, or empty.
set -eu

usage() {
  echo "usage: channel-json.sh --id ID --codex-version X.Y.Z --tarball PATH --min-pkg V --state HEX [--tarball-prefix P]" >&2
  exit 2
}

ID=
CODEX=
TARBALL=
MIN_PKG=
STATE=
HAVE_MIN_PKG=no
PREFIX=codex-package-x86_64-apple-darwin-
while [ "$#" -gt 0 ]; do
  [ "$#" -ge 2 ] || usage
  case "$1" in
    --id) ID=$2 ;;
    --codex-version) CODEX=$2 ;;
    --tarball) TARBALL=$2 ;;
    --min-pkg) MIN_PKG=$2; HAVE_MIN_PKG=yes ;;
    --state) STATE=$2 ;;
    --tarball-prefix) PREFIX=$2 ;;
    *) usage ;;
  esac
  shift 2
done
[ -n "$ID" ] && [ -n "$CODEX" ] && [ -n "$TARBALL" ] && [ -n "$STATE" ] && [ "$HAVE_MIN_PKG" = yes ] || usage

if ! printf '%s\n' "$ID" | grep -Eq '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)-mavericks\.[1-9][0-9]*$'; then
  echo "channel-json: not a build identity: $ID" >&2
  exit 1
fi
if [ "${ID%-mavericks.*}" != "$CODEX" ]; then
  echo "channel-json: identity $ID is not a build of Codex $CODEX" >&2
  exit 1
fi
if [ -n "$MIN_PKG" ] && ! printf '%s\n' "$MIN_PKG" | grep -Eq '^[0-9]{8}\.[0-9]{1,4}$'; then
  echo "channel-json: --min-pkg is neither empty nor YYYYMMDD.N: $MIN_PKG" >&2
  exit 1
fi
if ! printf '%s\n' "$STATE" | grep -Eq '^[0-9a-f]{64}$'; then
  echo "channel-json: --state is not 64 hex digits: $STATE" >&2
  exit 1
fi
if [ ! -f "$TARBALL" ]; then
  echo "channel-json: no tarball at $TARBALL" >&2
  exit 1
fi

DIGEST=$(shasum -a 256 < "$TARBALL" | awk '{print $1}')
[ -n "$DIGEST" ] || { echo "channel-json: cannot digest $TARBALL" >&2; exit 1; }
NAME=$(basename "$TARBALL")
if [ "$NAME" != "$PREFIX$ID.tar.gz" ]; then
  echo "channel-json: the tarball is named $NAME, not $PREFIX$ID.tar.gz" >&2
  exit 1
fi

printf '{"tag_name":"rust-v%s","mavergreen_build":"%s","mavergreen_codex_version":"%s","mavergreen_min_pkg":"%s","mavergreen_state":"%s","assets":[{"name":"%s","digest":"sha256:%s"}]}\n' \
  "$ID" "$ID" "$CODEX" "$MIN_PKG" "$STATE" "$NAME" "$DIGEST"
