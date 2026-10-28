#!/bin/sh
# platform: host-agnostic -- plain sh and awk; runs on ultimate-hat and modern macOS
#   usage: check-upstream-features.sh LIB-RS [LEDGER]
#          Holds the features Codex's LIB-RS (codex-rs/features/src/lib.rs) makes reachable to the
#          ledger, components/codex/features (or LEDGER): one "<key> <verdict> [reason]" line per
#          feature, verdict works, needs-work or deferred, the last two with a reason; # starts a
#          comment. It fails, saying each problem on stderr, when a reachable feature has no line, a
#          line names a feature upstream does not have, a verdict is unknown or lacks its reason, or a
#          key has two lines. A line for a feature upstream has but does not yet make reachable is
#          allowed, so a verdict can wait for it.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
case "$#" in 1|2) ;; *) echo "usage: check-upstream-features.sh LIB-RS [LEDGER]" >&2; exit 2 ;; esac
LIB=$1
LEDGER=${2:-$HERE/../components/codex/features}
[ -f "$LEDGER" ] || { echo "check-upstream-features: no ledger at $LEDGER" >&2; exit 1; }

work=$(mktemp -d "${TMPDIR:-/tmp}/check-upstream-features.XXXXXX")
trap 'rm -rf "$work"' EXIT
sh "$HERE/upstream-features.sh" all "$LIB" > "$work/all"
sh "$HERE/upstream-features.sh" reachable "$LIB" > "$work/reachable"

# One pass over three files, told apart by which has been read: every upstream key, the reachable
# keys, then the ledger with its comments and surrounding blanks gone.
awk -v ledger="$LEDGER" '
  FILENAME == ARGV[1] { known[$1] = 1; next }
  FILENAME == ARGV[2] { reachable[$1] = 1; order[++n] = $1; next }
  {
    line = $0
    sub(/#.*/, "", line)
    sub(/[ \t]+$/, "", line)
    if (line ~ /^[ \t]*$/) next
    split(line, f, /[ \t]+/)
    if (f[1] == "") { key = f[2]; verdict = f[3]; reasoned = (f[4] != "") }
    else { key = f[1]; verdict = f[2]; reasoned = (f[3] != "") }
    if (key in judged) problem(key ": has more than one line")
    judged[key] = 1
    if (!(key in known)) problem(key ": upstream has no such feature")
    if (verdict != "works" && verdict != "needs-work" && verdict != "deferred")
      problem(key ": \"" verdict "\" is not a verdict (works, needs-work or deferred)")
    else if (verdict != "works" && !reasoned) problem(key ": " verdict " needs a reason")
  }
  function problem(msg) { printf "check-upstream-features: %s\n", msg > "/dev/stderr"; bad = 1 }
  END {
    for (i = 1; i <= n; i++)
      if (!(order[i] in judged)) problem(order[i] ": reachable upstream, with no verdict in " ledger)
    if (bad) {
      printf "    fix: add \"<key> works\" (or needs-work/deferred with a reason) to components/codex/features for each feature named, and remove lines for features upstream dropped\n" > "/dev/stderr"
      exit 1
    }
    printf "check-upstream-features: %d reachable features, each with a verdict\n", n > "/dev/stderr"
  }
' "$work/all" "$work/reachable" "$LEDGER"
