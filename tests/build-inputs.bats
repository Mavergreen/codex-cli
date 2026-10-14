#!/usr/bin/env bats

setup() {
  export MAVERGREEN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export MAVERICKS_ROOT="$MAVERGREEN_ROOT"
  export SHIPYARD_SCRIPTS="${SHIPYARD_SCRIPTS:-/home/schmonz/Documents/trees/mavergreen-shipyard/scripts}"
  export MAVERICKS_TAGS=""
  export MAVERICKS_BUILD_ROOT="$BATS_TEST_TMPDIR/local-build"
}

@test "version resolution follows the family upstream and packaging axes" {
  upstream=$(tr -d '[:space:]' < "$MAVERGREEN_ROOT/UPSTREAM_VERSION")
  run sh "$MAVERGREEN_ROOT/build/versions.sh" auto
  [ "$status" -eq 0 ]
  [ "$output" = "$upstream-mavericks.1" ]

  export MAVERICKS_TAGS="$upstream-mavericks.1"
  run sh "$MAVERGREEN_ROOT/build/versions.sh" local
  [ "$status" -eq 0 ]
  [ "$output" = "$upstream-mavericks.2" ]
}

@test "build root is host-local and cannot be inside the product source" {
  run sh "$MAVERGREEN_ROOT/build/resolve-build-root.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "$(cd -P "$MAVERICKS_BUILD_ROOT" && pwd)" ]

  export MAVERICKS_BUILD_ROOT="$MAVERGREEN_ROOT/build-output"
  run sh "$MAVERGREEN_ROOT/build/resolve-build-root.sh"
  [ "$status" -ne 0 ]
}

@test "fetch applies the committed patch series to the pinned revision" {
  export CODEX_REPOSITORY="file://$MAVERGREEN_ROOT/codex"
  run sh "$MAVERGREEN_ROOT/build/fetch-codex.sh"
  [ "$status" -eq 0 ]
  source_dir="$MAVERICKS_BUILD_ROOT/codex-src"
  [ "$(git -C "$source_dir" rev-parse HEAD)" = "$(cat "$MAVERGREEN_ROOT/build/codex-revision")" ]
  expected=$(printf '%s\n' \
    codex-rs/Cargo.lock \
    codex-rs/http-client/src/custom_ca.rs \
    codex-rs/core/src/config/mod.rs \
    codex-rs/features/src/lib.rs \
    codex-rs/user-verification/src/lib.rs \
    codex-rs/tui/Cargo.toml \
    codex-rs/tui/src/screen_reader.rs \
    codex-rs/tui/src/system_motion.rs \
    codex-rs/sandboxing/src/seatbelt_base_policy.sbpl \
    codex-rs/sandboxing/src/seatbelt_preferences_policy.sbpl \
    codex-rs/sandboxing/src/seatbelt_tests.rs \
    codex-rs/sandboxing/src/seatbelt.rs \
    codex-rs/sandboxing/src/seatbelt_daemon.rs \
    codex-rs/utils/pty/src/posix_child.rs | sort)
  changed=$(git -C "$source_dir" diff --name-only | sort)
  [ "$changed" = "$expected" ] || { printf 'expected changes:\n%s\nchanged:\n%s\n' "$expected" "$changed"; return 1; }
  others=$(git -C "$source_dir" status --porcelain --untracked-files=all | grep -v '^ M ' || true)
  [ -z "$others" ] || { printf 'status beyond the modified files:\n%s\n' "$others"; return 1; }
}

@test "fetch records the workspace version for every path package in Cargo.lock" {
  export CODEX_REPOSITORY="file://$MAVERGREEN_ROOT/codex"
  run sh "$MAVERGREEN_ROOT/build/fetch-codex.sh"
  [ "$status" -eq 0 ]
  source_dir="$MAVERICKS_BUILD_ROOT/codex-src"
  upstream=$(tr -d '[:space:]' < "$MAVERGREEN_ROOT/UPSTREAM_VERSION")
  changed=$(git -C "$source_dir" diff -U0 codex-rs/Cargo.lock | grep '^[-+][^-+]' | LC_ALL=C sort -u)
  [ "$changed" = "$(printf '+version = "%s"\n-version = "0.0.0"' "$upstream")" ]
  [ "$(grep -c '^version = "0.0.0"$' "$source_dir/codex-rs/Cargo.lock")" -eq 0 ]
}

@test "fetch reuses its own prepared checkout without touching it" {
  export CODEX_REPOSITORY="file://$MAVERGREEN_ROOT/codex"
  run sh "$MAVERGREEN_ROOT/build/fetch-codex.sh"
  [ "$status" -eq 0 ]
  source_dir="$MAVERICKS_BUILD_ROOT/codex-src"
  marker="$source_dir/codex-rs/tui/Cargo.toml"
  touch -t 200001010000 "$marker"
  before=$(stat -f %m "$marker")
  run sh "$MAVERGREEN_ROOT/build/fetch-codex.sh"
  [ "$status" -eq 0 ]
  [ "$(stat -f %m "$marker")" = "$before" ]
}

# copy_product: a scratch copy of the product (without the codex/ inspection checkout) whose
# patches and UPSTREAM_VERSION a test may change. Its build root stays the test's own.
copy_product() {
  product="$BATS_TEST_TMPDIR/product"
  mkdir -p "$product"
  cp -R "$MAVERGREEN_ROOT/build" "$MAVERGREEN_ROOT/patches" "$MAVERGREEN_ROOT/components" \
    "$MAVERGREEN_ROOT/UPSTREAM_VERSION" "$product/"
}

@test "a change to the patch series invalidates the prepared checkout" {
  export CODEX_REPOSITORY="file://$MAVERGREEN_ROOT/codex"
  copy_product
  run sh "$product/build/fetch-codex.sh"
  [ "$status" -eq 0 ]
  source_dir="$MAVERICKS_BUILD_ROOT/codex-src"
  [ ! -e "$source_dir/codex-rs/mavergreen-series-probe.txt" ]
  cat > "$product/patches/0099-series-probe.patch" <<'PATCH'
diff --git a/codex-rs/mavergreen-series-probe.txt b/codex-rs/mavergreen-series-probe.txt
new file mode 100644
index 0000000..9daeafb
--- /dev/null
+++ b/codex-rs/mavergreen-series-probe.txt
@@ -0,0 +1 @@
+test
PATCH
  run sh "$product/build/fetch-codex.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"discarding a stale prepared checkout"* ]] || false
  [ -f "$source_dir/codex-rs/mavergreen-series-probe.txt" ]

  rm "$product/patches/0099-series-probe.patch"
  run sh "$product/build/fetch-codex.sh"
  [ "$status" -eq 0 ]
  [ ! -e "$source_dir/codex-rs/mavergreen-series-probe.txt" ]
}

@test "fetch refuses a Codex workspace version other than UPSTREAM_VERSION" {
  export CODEX_REPOSITORY="file://$MAVERGREEN_ROOT/codex"
  copy_product
  run sh "$product/build/fetch-codex.sh"
  [ "$status" -eq 0 ]
  printf '0.0.1\n' > "$product/UPSTREAM_VERSION"
  run sh "$product/build/fetch-codex.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"workspace version"*"is not 0.0.1"* ]] || false
}

@test "fetch discards a checkout it did not prepare and applies the series again" {
  export CODEX_REPOSITORY="file://$MAVERGREEN_ROOT/codex"
  run sh "$MAVERGREEN_ROOT/build/fetch-codex.sh"
  [ "$status" -eq 0 ]
  source_dir="$MAVERICKS_BUILD_ROOT/codex-src"
  printf 'stray\n' >> "$source_dir/codex-rs/Cargo.toml"
  printf 'stray\n' > "$source_dir/codex-rs/stray.txt"
  mkdir -p "$source_dir/codex-rs/target"
  printf 'stray\n' > "$source_dir/codex-rs/target/ignored-stray"
  run sh "$MAVERGREEN_ROOT/build/fetch-codex.sh"
  [ "$status" -eq 0 ]
  [ -z "$(git -C "$source_dir" status --porcelain --untracked-files=all | grep -v '^ M ')" ]
  [ -z "$(git -C "$source_dir" diff --name-only codex-rs/Cargo.toml)" ]
  [ ! -e "$source_dir/codex-rs/target/ignored-stray" ]
}

@test "patch application applies the committed patch series in lexical order" {
  source_dir="$BATS_TEST_TMPDIR/source"
  patch_dir="$BATS_TEST_TMPDIR/patches"
  mkdir -p "$source_dir" "$patch_dir"
  printf 'before\n' > "$source_dir/sample.txt"
  git -C "$source_dir" init -q
  git -C "$source_dir" -c user.name=test -c user.email=test@example.invalid add sample.txt
  git -C "$source_dir" -c user.name=test -c user.email=test@example.invalid commit -qm fixture
  cat > "$patch_dir/0001-sample.patch" <<'PATCH'
diff --git a/sample.txt b/sample.txt
index 5d5a9bc..7e3e8e4 100644
--- a/sample.txt
+++ b/sample.txt
@@ -1 +1 @@
-before
+after
PATCH

  run sh -c 'MAVERICKS_BUILD_DIR="$1/build"; export MAVERICKS_BUILD_DIR; . "$MAVERICKS_BUILD_DIR/lib.sh"; mavericks_apply_patches "$2" "$3"' _ \
    "$MAVERGREEN_ROOT" "$source_dir" "$patch_dir"
  [ "$status" -eq 0 ]
  [ "$(cat "$source_dir/sample.txt")" = after ]
}
