#!/bin/sh
# platform: host-agnostic -- plain sh; runs on ultimate-hat and modern macOS
#   usage: channel-assets.sh [--ids] REPO TAG
#          Prints the name of every asset of the release TAG of REPO, one per line, and exits non-zero
#          when the release or its assets cannot be read. With --ids each line is "<asset id> <name>",
#          the id being what repos/REPO/releases/assets/<id> fetches exactly. gh's embedded asset list
#          may be capped, so this asks the assets endpoint page by page.
set -eu

usage() {
  echo "usage: channel-assets.sh [--ids] REPO TAG" >&2
  exit 2
}
FIELDS='.[].name'
if [ "${1:-}" = --ids ]; then
  FIELDS='.[] | "\(.id) \(.name)"'
  shift
fi
[ "$#" -eq 2 ] || usage
REPO=$1
TAG=$2

RELEASE_ID=$(gh api "repos/$REPO/releases/tags/$TAG" -q .id) || {
  echo "channel-assets: cannot read the $TAG release of $REPO" >&2
  exit 1
}
gh api --paginate "repos/$REPO/releases/$RELEASE_ID/assets?per_page=100" -q "$FIELDS" || {
  echo "channel-assets: cannot list the assets of the $TAG release of $REPO" >&2
  exit 1
}
