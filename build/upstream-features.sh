#!/bin/sh
# platform: host-agnostic -- plain sh and awk; runs on ultimate-hat and modern macOS
#   usage: upstream-features.sh all|reachable LIB-RS
#          Reads the FEATURES table of Codex's codex-rs/features/src/lib.rs. all prints
#          "<key> <stage> <on|off>" per FeatureSpec in table order, the stage as its bare variant name;
#          reachable prints, sorted, the keys a user can reach: default_enabled true with a stage other
#          than Removed or Deprecated, or any Experimental stage, which /experimental offers.
#          Where upstream does not write a literal, the reading errs toward reachable, so the ledger is
#          asked rather than told a feature is out of reach: a stage picked with cfg! counts as its
#          most reachable branch (Experimental, then Stable, UnderDevelopment, Deprecated, Removed),
#          and a default_enabled other than a literal true or false counts as on.
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
#           the FEATURES list, with // comments gone, a record starts at each "FeatureSpec {" and
#           takes the first key and default_enabled field after it, and every Stage:: variant. A
#           field is its name at the start of a line or after a non-identifier character, so
#           legacy_key is not key. 10.9's awk has no match() captures, so each value is cut out
#           with sub().
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
  BEGIN {
    rank["Removed"] = 1; rank["Deprecated"] = 2; rank["UnderDevelopment"] = 3
    rank["Stable"] = 4; rank["Experimental"] = 5
  }
  !inlist && index($0, "FEATURES: &[FeatureSpec]") { inlist = 1; next }
  !inlist { next }
  /^];/ { inlist = 0; next }
  {
    line = $0
    sub(/(^|[ \t])\/\/.*/, "", line)
    while ((i = index(line, "FeatureSpec {")) > 0) {
      flush()
      open = 1; n++; key = ""; stage = ""; dflt = ""
      line = substr(line, i + 13)
      take(line)
    }
    if (open) take(line)
  }
  # field(s, name): what follows "name:" in s, where name begins a line or follows a
  # non-identifier character; "" when s has no such field
  function field(s, name,   t, before) {
    while ((t = index(s, name ":")) > 0) {
      before = (t == 1 ? "" : substr(s, t - 1, 1))
      if (before !~ /[A-Za-z0-9_]/) {
        s = substr(s, t + length(name) + 1); sub(/^[ \t]*/, "", s)
        return (s == "" ? " " : s)
      }
      s = substr(s, t + length(name) + 1)
    }
    return ""
  }
  function take(s,   t, u, v) {
    if (key == "" && (v = field(s, "key")) != "" && substr(v, 1, 1) == "\"") {
      key = substr(v, 2); sub(/".*/, "", key)
    }
    u = s
    while ((t = index(u, "Stage::")) > 0) {
      u = substr(u, t + 7); v = u; sub(/[^A-Za-z].*/, "", v)
      if (stage == "" || rank[v] > rank[stage]) stage = v
    }
    if (dflt == "" && (v = field(s, "default_enabled")) != "") {
      if (v ~ /^false([^A-Za-z0-9_]|$)/) dflt = "off"
      else dflt = "on"
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
