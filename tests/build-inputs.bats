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
  [[ "$output" == "$MAVERICKS_BUILD_ROOT" ]]

  export MAVERICKS_BUILD_ROOT="$MAVERGREEN_ROOT/build-output"
  run sh "$MAVERGREEN_ROOT/build/resolve-build-root.sh"
  [ "$status" -ne 0 ]
}

@test "fetch uses the committed upstream revision" {
  export CODEX_REPOSITORY="file://$MAVERGREEN_ROOT/codex"
  run sh "$MAVERGREEN_ROOT/build/fetch-codex.sh"
  [ "$status" -eq 0 ]
  source_dir="$MAVERICKS_BUILD_ROOT/codex-src"
  [ "$(git -C "$source_dir" rev-parse HEAD)" = "$(cat "$MAVERGREEN_ROOT/build/codex-revision")" ]
  [ -z "$(git -C "$source_dir" status --porcelain)" ]
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
