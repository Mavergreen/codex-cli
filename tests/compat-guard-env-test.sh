#!/bin/sh
# platform: host-agnostic -- plain sh; shipyard's guard is a stand-in that reports what it was given
# spec: build/compat-guard.sh header -- the guard passes the analyzer's roots as MAVERGREEN_OBJC_*
#       and leaves the caller's own environment, SDKROOT included, as it found it.
#   usage: sh tests/compat-guard-env-test.sh
set -eu
. "$(dirname "$0")/lib/harness.sh"
h_setup
mkdir -p "$H/shipyard" "$H/elsewhere"
: "${SHIPYARD_SCRIPTS:?set SHIPYARD_SCRIPTS}"
for f in "$SHIPYARD_SCRIPTS"/*; do ln -s "$f" "$H/shipyard/"; done
rm -f "$H/shipyard/assert_binary_compatible.sh"
printf '#!/bin/sh\necho "SDKROOT=${SDKROOT-unset} OBJC_SDK=${MAVERGREEN_OBJC_SDK_ROOT-unset}"\n' > "$H/shipyard/assert_binary_compatible.sh"
printf 'x' > "$H/elsewhere/codex"
out=$(SHIPYARD_SCRIPTS="$H/shipyard" MAVERICKS_BUILD_ROOT="$H/broot" SDKROOT=/the/callers/sdk \
  sh "$H_REPO/build/compat-guard.sh" "$H/elsewhere/codex" 2>&1) || true
h_assert_eq "SDKROOT=/the/callers/sdk OBJC_SDK=unset" "$out" "an override run with no CODEX_OBJC_SDK_ROOT leaves SDKROOT alone and names no SDK root"
out=$(SHIPYARD_SCRIPTS="$H/shipyard" MAVERICKS_BUILD_ROOT="$H/broot" SDKROOT=/the/callers/sdk CODEX_OBJC_SDK_ROOT=/pinned/sdk \
  sh "$H_REPO/build/compat-guard.sh" "$H/elsewhere/codex" 2>&1) || true
h_assert_eq "SDKROOT=/the/callers/sdk OBJC_SDK=/pinned/sdk" "$out" "CODEX_OBJC_SDK_ROOT reaches the guard as MAVERGREEN_OBJC_SDK_ROOT, and SDKROOT stays the caller's"
h_done
