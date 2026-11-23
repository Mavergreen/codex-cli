#!/bin/sh
# platform: macOS-only -- the harness drives 10.9's tools
#   usage: sh tests/derive-pkg-tree-test.sh
#          derive-pkg-tree.sh turns the standalone archive's tree into the pkg's: the bundled
#          requirements go, the pkg-only files come in, and nothing else changes. The pkg tree it
#          derives from codex-cli's archive is tree/ as committed, plus the archive's version file.
set -eu
. "$(dirname "$0")/lib/harness.sh"
h_setup
DERIVE="$H_REPO/packaging/derive-pkg-tree.sh"
LIST="$H_REPO/packaging/standalone-bundled"

# codex-cli's archive tree, as build-standalone.sh stages it
SA="$H/stand alone/codex-cli-20261123.1"
mkdir -p "$SA"
cp -R "$H_REPO/tree/." "$SA/"
rm -rf "$SA/libexec/mavergreen"
printf '20261123.1\n' > "$SA/share/codex-cli/version"
while read -r short path || [ -n "$short" ]; do
  [ -n "$short" ] || continue
  mkdir -p "$SA/$path/bin" "$SA/$path/share/doc"
  printf 'binary\n' > "$SA/$path/bin/$short"
  printf 'license\n' > "$SA/$path/share/doc/LICENSE"
done < "$LIST"

run() { "$@" >"$H/out" 2>"$H/err" && rc=0 || rc=$?; }

run sh "$DERIVE" --pkg-only "$H_REPO/tree/libexec/mavergreen=libexec/mavergreen" "$SA" "$LIST" "$H/pkg tree"
h_assert_eq 0 "$rc" "derives ($(cat "$H/err"))"
mkdir -p "$H/want"
cp -R "$H_REPO/tree/." "$H/want/"
printf '20261123.1\n' > "$H/want/share/codex-cli/version"
run diff -r "$H/want" "$H/pkg tree"
h_assert_eq 0 "$rc" "the pkg tree is tree/ plus the version file ($(cat "$H/out"))"
h_assert_absent "$H/pkg tree/libexec/codex-cli/bundled" "no bundled directory is left, empty or not"
h_assert_present "$SA/libexec/codex-cli/bundled/rg/bin/rg" "the standalone tree is left as it was"

# the list names exactly the products the pkg requires
h_assert_eq "$(awk 'NF { print $1 }' "$H_REPO/tree/share/codex-cli/requires")" "$(awk 'NF { print $1 }' "$LIST")" \
  "every bundled requirement is one the pkg declares, in the same order"

run sh "$DERIVE" "$SA" "$LIST" "$H/pkg tree"
h_assert_eq 2 "$rc" "an existing output is refused"

rm -rf "$SA/libexec/codex-cli/bundled/ed25519"
run sh "$DERIVE" "$SA" "$LIST" "$H/out tree"
h_assert_eq 1 "$rc" "a bundled path the tree lacks fails"
h_assert_contains "$(cat "$H/err")" "ed25519: libexec/codex-cli/bundled/ed25519 is not in" "it names the missing bundle"
h_assert_absent "$H/out tree" "a failed derivation leaves no output"

for bad in "rg /abs/path" "rg ../up" "rg a/../../up" "rg" "rg ." ; do
  printf '%s\n' "$bad" > "$H/bad list"
  run sh "$DERIVE" "$SA" "$H/bad list" "$H/bad tree"
  h_assert_eq 2 "$rc" "a bad list line is refused: $bad"
done

run sh "$DERIVE" --pkg-only "$H/nowhere=libexec/x" "$SA" "$LIST" "$H/bad tree"
h_assert_eq 2 "$rc" "a missing pkg-only source is refused"

h_done
