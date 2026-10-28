#!/usr/bin/env bats
# platform: host-agnostic -- fixture tables and plain sh; runs on ultimate-hat and modern macOS

setup() {
  export PRODUCT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  . "$PRODUCT_ROOT/tests/lib/feature-table.sh"
  table="$BATS_TEST_TMPDIR/lib.rs"
  ledger="$BATS_TEST_TMPDIR/features"
  # reachable: alpha (Stable, on) and gamma (Experimental); beta is Removed, filler_1.. are off
  feature_table "$table" 47 "alpha Stable on" "beta Removed on" "gamma Experimental off"
}

check() { sh "$PRODUCT_ROOT/build/check-upstream-features.sh" "$table" "$ledger"; }

@test "every reachable feature judged passes" {
  printf 'alpha works\ngamma deferred upstream offers it only on hardware 10.9 lacks\n' > "$ledger"
  run check
  [ "$status" -eq 0 ]
  [[ "$output" == *"2 reachable features, each with a verdict"* ]]
}

@test "a reachable feature without a line fails, naming it" {
  printf 'alpha works\n' > "$ledger"
  run check
  [ "$status" -eq 1 ]
  [[ "$output" == *gamma* ]]
  [[ "$output" == *"fix:"* ]]
}

@test "a verdict for a feature upstream no longer has fails" {
  printf 'alpha works\ngamma works\nomega works\n' > "$ledger"
  run check
  [ "$status" -eq 1 ]
  [[ "$output" == *omega* ]]
}

@test "a verdict for a known but unreachable feature is allowed" {
  printf 'alpha works\ngamma works\nfiller_3 deferred not yet\nbeta works\n' > "$ledger"
  run check
  [ "$status" -eq 0 ]
}

@test "an unknown verdict fails" {
  printf 'alpha maybe\ngamma works\n' > "$ledger"
  run check
  [ "$status" -eq 1 ]
  [[ "$output" == *maybe* ]]
}

@test "needs-work or deferred without a reason fails" {
  printf 'alpha needs-work\ngamma deferred\n' > "$ledger"
  run check
  [ "$status" -eq 1 ]
  [[ "$output" == *alpha* ]]
  [[ "$output" == *gamma* ]]
}

@test "a duplicate key fails" {
  printf 'alpha works\nalpha works\ngamma works\n' > "$ledger"
  run check
  [ "$status" -eq 1 ]
  [[ "$output" == *alpha* ]]
}

@test "comments, blank lines and trailing spaces are fine" {
  printf '# the ledger\n\nalpha works   \n  # indented comment\ngamma deferred a reason  # and a note\n\t\n' > "$ledger"
  run check
  [ "$status" -eq 0 ]
}

@test "all problems are reported, not just the first" {
  printf 'alpha works\nomega works\n' > "$ledger"
  run check
  [ "$status" -eq 1 ]
  [[ "$output" == *gamma* ]]
  [[ "$output" == *omega* ]]
}

@test "a table the parser refuses fails the check" {
  feature_table "$table" 10 "alpha Stable on"
  printf 'alpha works\n' > "$ledger"
  run check
  [ "$status" -eq 1 ]
}

@test "a missing ledger fails, naming it" {
  run check
  [ "$status" -eq 1 ]
  [[ "$output" == *"$ledger"* ]]
}
