#!/usr/bin/env bats
# platform: host-agnostic -- fixtures and plain sh; runs on ultimate-hat and modern macOS

setup() {
  export MAVERGREEN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export MAVERICKS_ROOT="$MAVERGREEN_ROOT"
  export SHIPYARD_SCRIPTS="${SHIPYARD_SCRIPTS:-/home/schmonz/Documents/trees/mavergreen-shipyard/scripts}"
  export MAVERICKS_BUILD_ROOT="$BATS_TEST_TMPDIR/local-build"
}

# need_codex_checkout: the fetch tests clone the gitignored codex/ inspection checkout, which a
# clean checkout (CI's actions/checkout, a git archive copy) lacks. They skip unless codex/ is a git
# checkout holding the pinned revision; CI's build-codex.sh cross runs the same fetch for real.
need_codex_checkout() {
  revision=$(sh "$MAVERGREEN_ROOT/build/codex-pin.sh" revision)
  git -C "$MAVERGREEN_ROOT/codex" cat-file -e "$revision^{commit}" 2>/dev/null ||
    skip "codex/ is not a git checkout holding the pinned revision $revision"
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
  need_codex_checkout
  export CODEX_REPOSITORY="file://$MAVERGREEN_ROOT/codex"
  run sh "$MAVERGREEN_ROOT/build/fetch-codex.sh"
  [ "$status" -eq 0 ]
  source_dir="$MAVERICKS_BUILD_ROOT/codex-src"
  [ "$(git -C "$source_dir" rev-parse HEAD)" = "$(sh "$MAVERGREEN_ROOT/build/codex-pin.sh" revision)" ]
  expected=$(printf '%s\n' \
    codex-rs/Cargo.lock \
    codex-rs/install-context/src/lib.rs \
    codex-rs/install-context/src/mavergreen.rs \
    codex-rs/user-verification/src/lib.rs \
    codex-rs/app-server-daemon/src/managed_install.rs \
    codex-rs/app-server-daemon/src/managed_install_path_tests.rs \
    codex-rs/app-server-daemon/src/prepare_install.rs \
    codex-rs/app-server-daemon/src/prepare_install_tests.rs \
    codex-rs/app-server-daemon/src/update_loop.rs \
    codex-rs/app-server-daemon/src/update_loop_tests.rs \
    codex-rs/cli/src/doctor/updates.rs \
    codex-rs/cli/src/main.rs \
    codex-rs/tui/Cargo.toml \
    codex-rs/tui/src/history_cell/notices.rs \
    codex-rs/tui/src/history_cell/snapshots/codex_tui__history_cell__tests__standalone_unix_update_available_history_cell_snapshot.snap \
    codex-rs/tui/src/history_cell/snapshots/codex_tui__history_cell__tests__standalone_windows_update_available_history_cell_snapshot.snap \
    codex-rs/tui/src/history_cell/tests.rs \
    codex-rs/tui/src/lib.rs \
    codex-rs/tui/src/update_action.rs \
    codex-rs/tui/src/update_prompt.rs \
    codex-rs/tui/src/update_versions.rs \
    codex-rs/tui/src/updates.rs \
    codex-rs/tui/src/screen_reader.rs \
    codex-rs/tui/src/system_motion.rs \
    codex-rs/sandboxing/src/seatbelt_base_policy.sbpl \
    codex-rs/sandboxing/src/seatbelt_preferences_policy.sbpl \
    codex-rs/sandboxing/src/seatbelt_tests.rs \
    codex-rs/sandboxing/src/seatbelt.rs \
    codex-rs/sandboxing/src/seatbelt_daemon.rs \
    codex-rs/utils/pty/src/posix_child.rs | LC_ALL=C sort)
  changed=$({ git -C "$source_dir" diff --name-only; git -C "$source_dir" ls-files --others --exclude-standard; } | LC_ALL=C sort)
  [ "$changed" = "$expected" ] || { printf 'expected changes:\n%s\nchanged:\n%s\n' "$expected" "$changed"; return 1; }
  others=$(git -C "$source_dir" status --porcelain --untracked-files=all | grep -v '^ M \|^?? codex-rs/install-context/src/mavergreen.rs$' || true)
  [ -z "$others" ] || { printf 'status beyond the modified files:\n%s\n' "$others"; return 1; }
}

@test "fetch records the workspace version for every path package in Cargo.lock" {
  need_codex_checkout
  export CODEX_REPOSITORY="file://$MAVERGREEN_ROOT/codex"
  run sh "$MAVERGREEN_ROOT/build/fetch-codex.sh"
  [ "$status" -eq 0 ]
  source_dir="$MAVERICKS_BUILD_ROOT/codex-src"
  upstream=$(sh "$MAVERGREEN_ROOT/build/codex-pin.sh" version)
  changed=$(git -C "$source_dir" diff -U0 codex-rs/Cargo.lock | grep '^[-+][^-+]' | LC_ALL=C sort -u)
  [ "$changed" = "$(printf '+version = "%s"\n-version = "0.0.0"' "$upstream")" ]
  [ "$(grep -c '^version = "0.0.0"$' "$source_dir/codex-rs/Cargo.lock")" -eq 0 ]
}

@test "fetch reuses its own prepared checkout without touching it" {
  need_codex_checkout
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
  need_codex_checkout
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

@test "re-preparing keeps the mtime of a file it prepares the same" {
  need_codex_checkout
  export CODEX_REPOSITORY="file://$MAVERGREEN_ROOT/codex"
  copy_product
  run sh "$product/build/fetch-codex.sh"
  [ "$status" -eq 0 ]
  source_dir="$MAVERICKS_BUILD_ROOT/codex-src"
  patched="$source_dir/codex-rs/tui/src/system_motion.rs"
  touch -t 200001010000 "$patched" "$source_dir/codex-rs/Cargo.lock"
  before=$(stat -f %m "$patched")
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
  [ "$(stat -f %m "$patched")" = "$before" ]
  [ "$(stat -f %m "$source_dir/codex-rs/Cargo.lock")" = "$before" ]
  [ ! -e "$MAVERICKS_BUILD_ROOT/codex-src-kept" ]
}

@test "fetch refuses a Codex workspace version other than the pinned tag's" {
  need_codex_checkout
  export CODEX_REPOSITORY="file://$MAVERGREEN_ROOT/codex"
  copy_product
  run sh "$product/build/fetch-codex.sh"
  [ "$status" -eq 0 ]
  sed 's/^REF=.*/REF=rust-v0.0.1/' "$MAVERGREEN_ROOT/components/codex/version" > "$product/components/codex/version"
  run sh "$product/build/fetch-codex.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"workspace version"*"is not 0.0.1"* ]] || false
}

@test "fetch discards a checkout it did not prepare and applies the series again" {
  need_codex_checkout
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
  [ -z "$(git -C "$source_dir" status --porcelain --untracked-files=all | grep -v '^ M \|^?? codex-rs/install-context/src/mavergreen.rs$')" ]
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
