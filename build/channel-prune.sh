#!/bin/sh
# platform: host-agnostic -- plain sh; runs on ultimate-hat and modern macOS
#   usage: channel-prune.sh [--keep-newest 10] [--keep-minors 30]
#          Reads build identities (<x.y.z>-mavericks.<N>) on stdin and prints, one per line and newest
#          first, those the retention rule deletes. Keeps: the newest --keep-newest builds; the last
#          build of each of the newest --keep-minors major.minors; the last build of every major.minor
#          whose minor is divisible by 10; the last build of every major. "Last build" of a minor is
#          the highest patch, then the highest N. Everything is compared numerically. Lines that are
#          not identities are ignored, with a warning on stderr. Reads and writes nothing else.
set -eu

KEEP_NEWEST=10
KEEP_MINORS=30
while [ "$#" -gt 0 ]; do
  if [ "$#" -lt 2 ]; then
    echo "usage: channel-prune.sh [--keep-newest N] [--keep-minors N]" >&2
    exit 2
  fi
  case "$1" in
    --keep-newest) KEEP_NEWEST=$2 ;;
    --keep-minors) KEEP_MINORS=$2 ;;
    *) echo "usage: channel-prune.sh [--keep-newest N] [--keep-minors N]" >&2; exit 2 ;;
  esac
  shift 2
done
for count in "$KEEP_NEWEST" "$KEEP_MINORS"; do
  case "$count" in
    ''|*[!0-9]*) echo "channel-prune: not a count: $count" >&2; exit 2 ;;
  esac
done

LC_ALL=C
export LC_ALL

# one "x y z n id" line per distinct identity, the invalid ones warned about, then newest first
awk '
  /^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)-mavericks\.[1-9][0-9]*$/ {
    if (seen[$0]++) next
    split($0, v, /[.-]/)
    print v[1], v[2], v[3], v[5], $0
    next
  }
  { print "channel-prune: ignoring a line that is not a build identity: " $0 > "/dev/stderr" }
' | sort -k1,1nr -k2,2nr -k3,3nr -k4,4nr | awk -v keep_newest="$KEEP_NEWEST" -v keep_minors="$KEEP_MINORS" '
  {
    keep = 0
    if (NR <= keep_newest) keep = 1
    minor = $1 "." $2
    if (!(minor in minor_seen)) {            # first seen, so the last build of its minor
      minor_seen[minor] = 1
      if (++minors <= keep_minors) keep = 1
      if ($2 % 10 == 0) keep = 1
    }
    if (!($1 in major_seen)) {               # likewise the last build of its major
      major_seen[$1] = 1
      keep = 1
    }
    if (!keep) print $5
  }
'
