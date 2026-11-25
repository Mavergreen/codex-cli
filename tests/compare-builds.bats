#!/usr/bin/env bats
# platform: host-agnostic -- plain files, shasum or sha256sum, cmp and grep
# spec: build/compare-builds.sh header -- two builds of one input set are the same build only when
#       every file of one has the same bytes in the other: the family's build-twice check.

setup() {
  export PRODUCT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  a="$BATS_TEST_TMPDIR/a"; b="$BATS_TEST_TMPDIR/b"
  mkdir -p "$a/sub" "$b/sub"
  printf 'codex built\n' > "$a/codex"; printf 'codex built\n' > "$b/codex"
  printf 'host\n' > "$a/sub/host"; printf 'host\n' > "$b/sub/host"
}

cmpb() { run sh "$PRODUCT_ROOT/build/compare-builds.sh" "$@"; }

@test "two builds with the same bytes in every file are the same" {
  cmpb "$a" "$b"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"same codex "* ]] || false
  [[ "$output" == *"same sub/host "* ]] || false
}

@test "a file whose bytes differ makes them different, and says how many bytes" {
  printf 'codex bxilt\n' > "$b/codex"
  cmpb "$a" "$b"
  [ "$status" -eq 1 ]
  [[ "$output" == *"differs codex: 1 bytes differ"* ]] || false
  [[ "$output" == *"same sub/host "* ]] || false
}

@test "a file only one build has makes them different" {
  printf 'extra\n' > "$b/sub/extra"
  cmpb "$a" "$b"
  [ "$status" -eq 1 ]
  [[ "$output" == *"only in $b: sub/extra"* ]] || false
}

@test "a named path is counted in each differing file, so an embedded build root shows" {
  printf 'x /mnt/root-a/src y /mnt/root-a/src\n' > "$a/codex"
  printf 'x /mnt/root-b/src y /mnt/root-b/src\n' > "$b/codex"
  cmpb --path /mnt/root-a --path /mnt/root-b "$a" "$b"
  [ "$status" -eq 1 ]
  [[ "$output" == *"codex in $a names /mnt/root-a 2 times"* ]] || false
  [[ "$output" == *"codex in $b names /mnt/root-b 2 times"* ]] || false
}

@test "a missing directory or a wrong argument count is misuse" {
  cmpb "$a"
  [ "$status" -eq 2 ]
  cmpb "$a" "$BATS_TEST_TMPDIR/nope"
  [ "$status" -eq 2 ]
}

@test "a file name with a space is compared as one file" {
  printf 'same\n' > "$a/with space"; printf 'same\n' > "$b/with space"
  cmpb "$a" "$b"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"same with space "* ]] || false
}
