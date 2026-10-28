#!/usr/bin/env bats
# platform: host-agnostic -- fixture tables and plain sh; runs on ultimate-hat and modern macOS

setup() {
  export PRODUCT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  . "$PRODUCT_ROOT/tests/lib/feature-table.sh"
  table="$BATS_TEST_TMPDIR/lib.rs"
  # 46 fillers and four that matter: 50 entries, the fewest the parser accepts
  feature_table "$table" 46 "alpha Stable on" "beta Removed on" "gamma Experimental off" "delta Deprecated on"
}

features() { sh "$PRODUCT_ROOT/build/upstream-features.sh" "$@"; }

# drop_after FROM LINE: deletes from $table the first line matching LINE at or after one matching FROM
drop_after() {
  awk -v from="$1" -v line="$2" '!done && index($0, from) { armed = 1 }
    armed && !done && index($0, line) { done = 1; next } { print }' "$table" > "$table.new"
  mv "$table.new" "$table"
}

@test "reachable lists Stable-on and any Experimental, sorted" {
  run features reachable "$table"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'alpha\ngamma')" ]
}

@test "all prints key, stage and default for every entry" {
  run features all "$table"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 50 ]
  printf '%s\n' "$output" | grep -qx 'gamma Experimental off'
  printf '%s\n' "$output" | grep -qx 'beta Removed on'
  [ "${lines[0]}" = "alpha Stable on" ]
}

@test "fewer than 50 entries fails, naming the file" {
  feature_table "$table" 45 "alpha Stable on" "beta Removed on" "gamma Experimental off" "delta Deprecated on"
  run features reachable "$table"
  [ "$status" -eq 1 ]
  [[ "$output" == *"$table"* ]]
  [[ "$output" == *49* ]]
}

@test "an entry without default_enabled fails" {
  feature_table "$table" 50
  drop_after 'key: "filler_7"' default_enabled
  run features all "$table"
  [ "$status" -eq 1 ]
  [[ "$output" == *filler_7* ]]
}

@test "an entry without a key fails" {
  feature_table "$table" 50
  drop_after 'id: Feature::X' 'key: "filler_3"'
  run features all "$table"
  [ "$status" -eq 1 ]
}

@test "a one-line FeatureSpec is still read" {
  feature_table "$table" 50
  sed 's/^pub const FEATURES: &\[FeatureSpec\] = &\[$/&\
    FeatureSpec { id: Feature::A, key: "alpha", stage: Stage::Stable, default_enabled: true },/' "$table" > "$table.new"
  mv "$table.new" "$table"
  run features reachable "$table"
  [ "$status" -eq 0 ]
  [ "$output" = alpha ]
}

@test "a stage chosen by cfg! counts as its most reachable branch" {
  feature_table "$table" 50
  sed 's/^pub const FEATURES: &\[FeatureSpec\] = &\[$/&\
    FeatureSpec {\
        id: Feature::S,\
        key: "sleepy",\
        stage: if cfg!(target_os = "macos") {\
            Stage::Experimental { name: "S", menu_description: "d", announcement: "" }\
        } else {\
            Stage::UnderDevelopment\
        },\
        default_enabled: false,\
    },/' "$table" > "$table.new"
  mv "$table.new" "$table"
  run features reachable "$table"
  [ "$status" -eq 0 ]
  [ "$output" = sleepy ]
}

@test "only the FEATURES list is read, not a FeatureSpec elsewhere in the file" {
  { printf 'fn info(self) -> &'"'"'static FeatureSpec {\n    &FEATURES[0]\n}\n'; cat "$table"; } > "$table.new"
  mv "$table.new" "$table"
  run features all "$table"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 50 ]
}

@test "a missing file and a bad mode fail" {
  run features reachable "$BATS_TEST_TMPDIR/absent.rs"
  [ "$status" -eq 1 ]
  run features sideways "$table"
  [ "$status" -eq 2 ]
  run features reachable
  [ "$status" -eq 2 ]
}
