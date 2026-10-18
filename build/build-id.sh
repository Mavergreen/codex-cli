#!/bin/sh
# platform: host-agnostic -- plain sh; runs on ultimate-hat and modern macOS
#   usage: build-id.sh auto|rebuild
#          Prints ID=, STATE= and PUBLISH= for the Codex build this tree would make. The ID is
#          <codex x.y.z>-mavericks.<N>, N >= 1; STATE is the digest of everything that decides what
#          the build contains. `auto` publishes only when STATE differs from the newest build of
#          this Codex version on the builds channel; `rebuild` always takes the next N.
#          A channel whose release does not exist yet (gh's "release not found") holds no builds;
#          any other failure to read it stops the run. Tests name the channel by files:
#          CODEX_BUILDS_ASSET_LIST (asset names, one per line) and CODEX_BUILDS_JSON_DIR (a directory
#          of codex-build-<ID>.json); real runs ask gh, and fetch the newest build's JSON by its asset
#          id from the paginated listing (build/channel-assets.sh --ids), since gh's lookup by name
#          reads an asset list that may be capped.
set -eu

if [ "$#" -ne 1 ]; then
  echo "usage: build-id.sh auto|rebuild" >&2
  exit 2
fi
MODE=$1
case "$MODE" in auto|rebuild) ;; *) echo "build-id: mode must be auto or rebuild" >&2; exit 2 ;; esac

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CHANNEL_REPO=Mavergreen/codex-cli
CHANNEL_TAG=codex-builds
LC_ALL=C
export LC_ALL

CODEX=$(tr -d '[:space:]' < "$ROOT/components/codex/version")
case "$CODEX" in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *) echo "build-id: components/codex/version is not x.y.z: $CODEX" >&2; exit 1 ;;
esac

# the four pins, then every patch (the C-locale glob order), so a patch-only change is a new build,
# then the script that lays out the tarball users install, so a change to that layout is one too.
# A pipeline hides a failed cat, so every input is checked before any digest is computed.
cd "$ROOT"
for input in components/codex/version build/codex-revision components/rust/version components/clang-22/version \
  packaging/build-codex-package.sh; do
  [ -f "$input" ] || { echo "build-id: no $input" >&2; exit 1; }
done
set -- patches/*.patch
[ -f "$1" ] || { echo "build-id: no patches/*.patch" >&2; exit 1; }
STATE=$(cat components/codex/version build/codex-revision components/rust/version \
  components/clang-22/version "$@" packaging/build-codex-package.sh | shasum -a 256 | awk '{print $1}')

LISTING=
if [ -n "${CODEX_BUILDS_ASSET_LIST:-}" ]; then
  ASSETS=$(cat "$CODEX_BUILDS_ASSET_LIST")
else
  VIEW_OUT=$(gh release view "$CHANNEL_TAG" -R "$CHANNEL_REPO" 2>&1) && VIEW_STATUS=0 || VIEW_STATUS=$?
  if [ "$VIEW_STATUS" -ne 0 ]; then
    case "$VIEW_OUT" in
      *"release not found"*) ASSETS= ;;
      *) echo "build-id: cannot tell whether the $CHANNEL_TAG release of $CHANNEL_REPO exists: $VIEW_OUT" >&2
         exit 1 ;;
    esac
  else
    LISTING=$(sh "$ROOT/build/channel-assets.sh" --ids "$CHANNEL_REPO" "$CHANNEL_TAG") || {
      echo "build-id: cannot list the $CHANNEL_TAG release of $CHANNEL_REPO" >&2
      exit 1
    }
    ASSETS=$(printf '%s\n' "$LISTING" | sed -n 's/^[0-9][0-9]* //p')
  fi
fi

ESCAPED=$(printf '%s\n' "$CODEX" | sed 's/\./\\./g')
NEWEST=$(printf '%s\n' "$ASSETS" |
  sed -n "s/^codex-build-$ESCAPED-mavericks\\.\\([1-9][0-9]*\\)\\.json\$/\\1/p" | sort -n | tail -n 1)

PUBLISH=yes
if [ -z "$NEWEST" ]; then
  N=1
elif [ "$MODE" = auto ]; then
  NAME="codex-build-$CODEX-mavericks.$NEWEST.json"
  if [ -n "${CODEX_BUILDS_JSON_DIR:-}" ]; then
    JSON=$(cat "$CODEX_BUILDS_JSON_DIR/$NAME")
  else
    ASSET_ID=$(printf '%s\n' "$LISTING" | awk -v n="$NAME" '$2 == n { print $1; exit }')
    [ -n "$ASSET_ID" ] || { echo "build-id: the listing of $CHANNEL_REPO names no asset id for $NAME" >&2; exit 1; }
    JSON=$(gh api -H 'Accept: application/octet-stream' "repos/$CHANNEL_REPO/releases/assets/$ASSET_ID") || {
      echo "build-id: cannot download $NAME (asset $ASSET_ID) from $CHANNEL_REPO" >&2
      exit 1
    }
  fi
  PUBLISHED=$(printf '%s\n' "$JSON" | sed -n 's/.*"mavergreen_state":"\([0-9a-f]*\)".*/\1/p')
  [ -n "$PUBLISHED" ] || { echo "build-id: $NAME records no mavergreen_state" >&2; exit 1; }
  if [ "$PUBLISHED" = "$STATE" ]; then
    N=$NEWEST
    PUBLISH=no
  else
    N=$((NEWEST + 1))
  fi
else
  N=$((NEWEST + 1))
fi

printf 'ID=%s-mavericks.%s\nSTATE=%s\nPUBLISH=%s\n' "$CODEX" "$N" "$STATE" "$PUBLISH"
