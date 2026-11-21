#!/bin/sh
# platform: host-agnostic -- awk reads Cargo.lock; perl's core JSON::PP reads the reviewed evidence
#   usage: check-crate-pins.sh REVIEWED CARGO_LOCK
#          Drydock hashes a crate: citation in the crate sources by the NAME-VERSION of its reviewed
#          crates[] entry, and the crate sources hold every version cargo ever unpacked there. So each
#          registry crate REVIEWED pins (an entry with a checksum) must be one CARGO_LOCK locked: the
#          same name (a `_` in the pin matching a `-` in the lock), version and checksum, from
#          crates.io. Otherwise a citation could pass by hashing a version the compiler never read.
#          An entry without a checksum is a workspace crate, which no crate: citation names.
#          Exit 0 every pin locked, 1 naming each pin that is not, 2 usage.
set -eu
[ $# -eq 2 ] && [ -f "$1" ] && [ -f "$2" ] || { echo "usage: check-crate-pins.sh REVIEWED CARGO_LOCK" >&2; exit 2; }
# spec: Cargo.lock's [[package]] tables -- one "name version checksum" line per crates.io package
locked=$(awk '
  function emit() { if (name != "" && src ~ /^registry\+https:\/\/github\.com\/rust-lang\/crates\.io-index$/ && sum != "") { gsub(/-/, "_", name); print name, ver, sum } }
  /^\[\[package\]\]$/ { emit(); name = ver = src = sum = ""; next }
  /^\[/ { emit(); name = ver = src = sum = ""; next }
  { v = $0; sub(/^[a-z]+ = "/, "", v); sub(/"$/, "", v) }
  /^name = "/ { name = v } /^version = "/ { ver = v } /^source = "/ { src = v } /^checksum = "/ { sum = v }
  END { emit() }' "$2")
pins=$(perl -MJSON::PP -e '
  local $/; open my $h, "<", $ARGV[0] or die "$ARGV[0]: $!\n"; my $e = JSON::PP->new->decode(<$h>);
  print "$_->{name} $_->{version} $_->{checksum}\n" for grep { defined $_->{checksum} } @{$e->{crates} || []}' "$1") ||
  { echo "check-crate-pins: unreadable $1" >&2; exit 2; }
bad=0
for pin in $(printf '%s\n' "$pins" | tr ' ' '|'); do
  [ -n "$pin" ] || continue
  line=$(printf '%s' "$pin" | tr '|' ' ')
  printf '%s\n' "$locked" | grep -qxF "$line" || {
    echo "check-crate-pins: $1 pins ${line% *}, which $2 does not lock from crates.io with that checksum" >&2; bad=1; }
done
exit "$bad"
