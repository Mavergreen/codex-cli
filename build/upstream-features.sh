#!/bin/sh
# platform: host-agnostic -- plain sh and awk; runs on ultimate-hat and modern macOS
#   usage: upstream-features.sh all|reachable LIB-RS
#          Reads the FEATURES table of Codex's codex-rs/features/src/lib.rs. all prints
#          "<key> <stage> <on|off>" per FeatureSpec in table order, the stage as its bare variant name;
#          reachable prints, sorted, the keys a user can reach: default_enabled true with a stage other
#          than Removed or Deprecated, or any Experimental stage, which /experimental offers.
#          A stage upstream picks with cfg! counts as its most reachable branch (Experimental, when
#          one branch is), so the ledger is asked about it rather than told it is out of reach.
#          It fails, naming LIB-RS, on an entry missing its key, stage or default_enabled, or on fewer
#          than 50 entries: upstream's table has over 150, so fewer means its shape has changed under
#          this parser, and a check that read nothing must not pass.
set -eu
case "$#:${1-}" in
  2:all|2:reachable) ;;
  *) echo "usage: upstream-features.sh all|reachable LIB-RS" >&2; exit 2 ;;
esac
MODE=$1 LIB=$2
[ -f "$LIB" ] || { echo "upstream-features: no $LIB" >&2; exit 1; }

# platform: one pass reads both the multi-line entries upstream writes and a one-line entry: inside
#           the FEATURES list, a record starts at each "FeatureSpec {" and takes the first key and
#           default_enabled after it, and every Stage:: variant. 10.9's awk has no match() captures,
#           so each value is cut out with sub().
ALL=$(awk -v lib="$LIB" '
  function flush() {
    if (!open) return
    if (key == "" || stage == "" || dflt == "") {
      printf "upstream-features: %s: entry %d (%s) lacks its key, stage or default_enabled\n",
        lib, n, (key == "" ? "no key" : key) > "/dev/stderr"
      bad = 1
    }
    print key, stage, dflt
    open = 0
  }
  !inlist && index($0, "FEATURES: &[FeatureSpec]") { inlist = 1; next }
  !inlist { next }
  /^];/ { inlist = 0; next }
  {
    line = $0
    while ((i = index(line, "FeatureSpec {")) > 0) {
      flush()
      open = 1; n++; key = ""; stage = ""; dflt = ""
      line = substr(line, i + 13)
      take(line)
    }
    if (open) take(line)
  }
  function take(s,   t, u, v) {
    if (key == "" && (t = index(s, "key: \"")) > 0) {
      key = substr(s, t + 6); sub(/".*/, "", key)
    }
    u = s
    while ((t = index(u, "Stage::")) > 0) {
      u = substr(u, t + 7); v = u; sub(/[^A-Za-z].*/, "", v)
      if (stage == "" || v == "Experimental") stage = v
    }
    if (dflt == "" && (t = index(s, "default_enabled: ")) > 0) {
      dflt = substr(s, t + 17); sub(/[^a-z].*/, "", dflt)
      dflt = (dflt == "true" ? "on" : "off")
    }
  }
  END {
    flush()
    if (n < 50) {
      printf "upstream-features: %s has %d FeatureSpec entries, fewer than 50: has the table changed shape?\n",
        lib, n > "/dev/stderr"
      bad = 1
    }
    exit bad
  }
' "$LIB")

case "$MODE" in
  all) printf '%s\n' "$ALL" ;;
  reachable)
    printf '%s\n' "$ALL" | awk '
      $2 == "Experimental" || ($3 == "on" && $2 != "Removed" && $2 != "Deprecated") { print $1 }
    ' | LC_ALL=C sort ;;
esac
