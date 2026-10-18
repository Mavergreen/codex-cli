#!/bin/sh
# platform: host-agnostic -- plain sh and git; the release workflow runs it with --remote on the
#           modern runner, the tests run the same checks against a local repository
#   usage: check-upstream-pin.sh [--remote]
#          components/codex/version must be a stable x.y.z, because the family version <x.y.z>-mavericks.N and
#          the updater's comparison order only hold for one: a prerelease tag such as
#          rust-v0.162.0-alpha.1 has no order-preserving form there. build/codex-revision must be a
#          full lowercase commit SHA. With --remote, the SHA must also be the commit that Codex's
#          rust-v<components/codex/version> tag points at (CODEX_REPOSITORY overrides the repository, as for
#          fetch-codex.sh).
# spec: INGREDIENTS.md "Releasing" -- Renovate edits components/codex/version and cannot derive the commit
#       from it, so a bump alone must fail here, early and naming the file to update, rather than
#       reach fetch-codex.sh's checkout mismatch deep in the build.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/.." && pwd)
REMOTE=no
case "${1:-}" in
  '') ;;
  --remote) REMOTE=yes ;;
  *) echo "usage: check-upstream-pin.sh [--remote]" >&2; exit 2 ;;
esac
VERSION=$(tr -d '[:space:]' < "$ROOT/components/codex/version")
REVISION=$(tr -d '[:space:]' < "$HERE/codex-revision")

case "$VERSION" in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *) echo "check-upstream-pin: components/codex/version '$VERSION' is not a stable x.y.z" >&2; exit 1 ;;
esac
case "$VERSION" in
  *[!0-9.]*|*..*|.*|*.) echo "check-upstream-pin: components/codex/version '$VERSION' is not a stable x.y.z (a prerelease or other suffix has no order-preserving -mavericks.N form)" >&2; exit 1 ;;
esac
case "$REVISION" in
  ''|*[!0-9a-f]*) echo "check-upstream-pin: build/codex-revision is not a lowercase hex commit SHA" >&2; exit 1 ;;
esac
[ "${#REVISION}" -eq 40 ] || { echo "check-upstream-pin: build/codex-revision must be a full 40-digit commit SHA" >&2; exit 1; }

if [ "$REMOTE" = yes ]; then
  REPO=${CODEX_REPOSITORY:-https://github.com/openai/codex.git}
  TAG="rust-v$VERSION"
  refs=$(git ls-remote "$REPO" "refs/tags/$TAG" "refs/tags/$TAG^{}") || {
    echo "check-upstream-pin: cannot list tags of $REPO" >&2; exit 1;
  }
  # An annotated tag lists the tag object, then its commit as TAG^{}; the commit is the last line.
  actual=$(printf '%s\n' "$refs" | awk 'NF { sha = $1 } END { print sha }')
  [ -n "$actual" ] || { echo "check-upstream-pin: $REPO has no tag $TAG (components/codex/version is $VERSION)" >&2; exit 1; }
  [ "$actual" = "$REVISION" ] || {
    echo "check-upstream-pin: components/codex/version is $VERSION but build/codex-revision is $REVISION; $TAG is commit $actual." >&2
    echo "  Update build/codex-revision to $actual (Renovate bumps components/codex/version alone), refresh patches/ if they no longer apply, and push to the same branch." >&2
    exit 1
  }
fi
echo "check-upstream-pin: ok -- $VERSION at $REVISION"
