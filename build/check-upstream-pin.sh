#!/bin/sh
# platform: host-agnostic -- plain sh and git; the release workflow runs it with --remote on the
#           modern runner, the tests run the same checks against a local repository
#   usage: check-upstream-pin.sh [--remote]
#          The Codex pin, components/codex/version, must be well formed (codex-pin.sh says what that
#          means). With --remote, its DIGEST must also be the commit its REF tag points at in REPO
#          (CODEX_REPOSITORY overrides the repository, as for fetch-codex.sh).
# spec: INGREDIENTS.md "Releasing" -- Renovate moves REF and DIGEST together; this catches a tag
#       that moved, or a hand edit that changed one without the other, before anything is built.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REMOTE=no
case "${1:-}" in
  '') ;;
  --remote) REMOTE=yes ;;
  *) echo "usage: check-upstream-pin.sh [--remote]" >&2; exit 2 ;;
esac
TAG=$(sh "$HERE/codex-pin.sh" tag)
REVISION=$(sh "$HERE/codex-pin.sh" revision)

if [ "$REMOTE" = yes ]; then
  REPO=${CODEX_REPOSITORY:-$(sh "$HERE/codex-pin.sh" repository)}
  refs=$(git ls-remote "$REPO" "refs/tags/$TAG" "refs/tags/$TAG^{}") || {
    echo "check-upstream-pin: cannot list tags of $REPO" >&2; exit 1;
  }
  # An annotated tag lists the tag object, then its commit as TAG^{}; the commit is the last line.
  actual=$(printf '%s\n' "$refs" | awk 'NF { sha = $1 } END { print sha }')
  [ -n "$actual" ] || { echo "check-upstream-pin: $REPO has no tag $TAG (components/codex/version's REF)" >&2; exit 1; }
  [ "$actual" = "$REVISION" ] || {
    echo "check-upstream-pin: components/codex/version pins $TAG at $REVISION, but $TAG is commit $actual." >&2
    echo "  Set DIGEST to $actual, or REF to the tag you meant." >&2
    exit 1
  }
fi
echo "check-upstream-pin: ok -- $TAG at $REVISION"
