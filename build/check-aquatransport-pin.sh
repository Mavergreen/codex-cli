#!/bin/sh
# platform: host-agnostic
#   usage: check-aquatransport-pin.sh [--allow-unreleased]
#          components/aquatransport/min-version names, as YYYY.MM.DD, the oldest Wowfunhappy
#          AquaTransport release with the TLS fixes Codex's native-tls needs. Until that
#          release exists it holds "unreleased", which this check refuses, so a package built from
#          that pin never reaches users. With --allow-unreleased it checks only that the pin is
#          one of the two shapes. On success it names the pin on stderr.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MAVERICKS_BUILD_DIR=$HERE
export MAVERICKS_BUILD_DIR
. "$HERE/lib.sh"

ALLOW=no
case "$#:${1-}" in
  0:) ;;
  1:--allow-unreleased) ALLOW=yes ;;
  *) echo "usage: check-aquatransport-pin.sh [--allow-unreleased]" >&2; exit 2 ;;
esac
PIN_FILE="$MAVERICKS_ROOT/components/aquatransport/min-version"
[ -r "$PIN_FILE" ] || { echo "check-aquatransport-pin: cannot read $PIN_FILE" >&2; exit 1; }
PIN=$(tr -d '[:space:]' < "$PIN_FILE")
case "$PIN" in
  unreleased)
    [ "$ALLOW" = yes ] || {
      echo "check-aquatransport-pin: components/aquatransport/min-version is 'unreleased': no AquaTransport release has the fixes Codex needs yet, so this package cannot be released" >&2
      exit 1
    }
    echo "check-aquatransport-pin: the pin is unreleased" >&2 ;;
  [0-9][0-9][0-9][0-9].[0-9][0-9].[0-9][0-9])
    echo "check-aquatransport-pin: the package needs AquaTransport $PIN or newer" >&2 ;;
  *)
    echo "check-aquatransport-pin: components/aquatransport/min-version is '$PIN', not YYYY.MM.DD or unreleased" >&2
    exit 1 ;;
esac
