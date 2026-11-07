#!/bin/sh
# platform: macOS-only -- builds packages with 10.9's bsdtar and reads them back with tar
# spec: build/objc-publication-check.sh header -- nothing is packaged or signed without a current
#       Objective-C proof whose strict runs both passed, for a build linked with a released provider.
#   usage: sh tests/objc-publication-test.sh
#          Lays out a fake build root with a proof as build/objc-build-evidence.sh writes one (no
#          shipyard runs: the fake binaries are never analyzed), checks that the publication check
#          accepts it, and that each way the proof can fail blocks it. Then checks that builds.yml
#          writes the proof before CTest, runs the guards through build/compat-guard.sh, and runs the
#          check before packaging and again before signing. Nothing is published, signed or fetched.
set -eu
. "$(dirname "$0")/lib/harness.sh"
h_setup
: "${SHIPYARD_SCRIPTS:?set SHIPYARD_SCRIPTS}"
CHECK="$H_REPO/build/objc-publication-check.sh"
BP="$H_REPO/packaging/build-codex-package.sh"
ID="$(sh "$H_REPO/build/codex-pin.sh" version)-mavericks.1"
sha() { shasum -a 256 "$1" | cut -c1-64; }

MAVERICKS_BUILD_ROOT="$H/build root"
export MAVERICKS_BUILD_ROOT
RD="$(sh "$H_REPO/build/objc-reviewed-dir.sh")"
ART="$MAVERICKS_BUILD_ROOT/codex-cross"
OBJC="$MAVERICKS_BUILD_ROOT/objc-cross"
# proof ORIGIN CODEX-STATUS HOST-STATUS: a fresh build and the proof objc-build-evidence.sh would write
proof() {
  rm -rf "$MAVERICKS_BUILD_ROOT"
  mkdir -p "$ART" "$OBJC/evidence" "$OBJC/reports" "$OBJC/linkmaps"
  printf '#!/bin/sh\necho codex\n' > "$ART/codex"
  printf '#!/bin/sh\necho host\n' > "$ART/codex-code-mode-host"
  chmod 0755 "$ART/codex" "$ART/codex-code-mode-host"
  printf 'license\n' > "$ART/LICENSE"
  printf 'notice\n' > "$ART/NOTICE"
  printf 'manifest\nrecaulk_origin=%s\n' "$1" > "$ART/build-manifest"
  printf 'map\n' > "$OBJC/linkmaps/codex.map"
  for n in codex codex-code-mode-host; do
    printf '{}\n' > "$OBJC/evidence/$n.json"
    printf '{}\n' > "$OBJC/evidence/$n.generated.json"
    printf '{"mode":"strict"}\n' > "$OBJC/reports/$n.objc-compat.json"
  done
  printf '%s\n' "$2" > "$OBJC/reports/codex.status"
  printf '%s\n' "$3" > "$OBJC/reports/codex-code-mode-host.status"
  for f in "$ART/codex" "$ART/codex-code-mode-host" "$ART/build-manifest" "$OBJC/linkmaps/codex.map" \
           "$OBJC/evidence/codex.json" "$OBJC/evidence/codex-code-mode-host.json" \
           "$OBJC/evidence/codex.generated.json" "$OBJC/evidence/codex-code-mode-host.generated.json" \
           "$OBJC/reports/codex.objc-compat.json" "$OBJC/reports/codex-code-mode-host.objc-compat.json" \
           "$OBJC/reports/codex.status" "$OBJC/reports/codex-code-mode-host.status" \
           "$RD/codex-reviewed-evidence.json" "$RD/codex-code-mode-host-reviewed-evidence.json"; do
    [ -f "$f" ] || continue   # an arm64 host has no reviewed rows until they are derived for it
    printf '%s %s\n' "$(sha "$f")" "$f"
  done > "$OBJC/identity"
}
# refused WHY EXPECTED-TEXT ARGS...: the check exits 1 and says EXPECTED-TEXT
refused() {
  why=$1; want=$2; shift 2
  rc=0; out="$(sh "$CHECK" "$@" 2>&1)" || rc=$?
  h_assert_eq 1 "$rc" "refused, exit 1: $why"
  h_assert_contains "$out" "$want" "says why: $why"
}

proof released 0 0
out="$(sh "$CHECK" cross 2>&1)" || true
h_assert_contains "$out" "may be packaged" "a current, strict-clean proof of a released-provider build is accepted"
TB="$(sh "$BP" "$ART" "$ID" "$H/channel")"
h_assert_ok sh "$CHECK" cross "$TB"

# the payload changed after it was analyzed
proof released 0 0
printf 'x' >> "$ART/codex"
refused "a binary changed since its proof" "changed since its proof" cross
proof released 0 0
printf 'x' >> "$ART/build-manifest"
refused "the manifest changed since its proof" "changed since its proof" cross
proof released 0 0
rm "$OBJC/reports/codex-code-mode-host.objc-compat.json"
refused "a report is gone" "is gone" cross
rm -rf "$OBJC"
refused "no proof at all" "no current Objective-C proof" cross

# a proof whose identity was cut short (a killed run, an edit): every input and output must be listed
proof released 0 0
grep -v "/evidence/codex.json\$" "$OBJC/identity" > "$H/id"; mv "$H/id" "$OBJC/identity"
refused "an identity without the codex evidence" "does not list" cross

# the analyzer did not pass
proof released 1 0
refused "codex's strict run found a blocking send" "codex: strict run exited 1" cross
proof released 0 4
refused "the host could not be measured" "codex-code-mode-host: strict run exited 4" cross
proof released 0 0
# a proof written before strict runs were recorded
rm "$OBJC/reports/codex.status"
grep -v "/reports/codex.status\$" "$OBJC/identity" > "$H/id"; mv "$H/id" "$OBJC/identity"
refused "no recorded strict run" "codex: no strict run recorded" cross

# a development provider
proof development 0 0
refused "a development provider" "development Recaulk provider" cross

# the tarball does not hold the proven bytes
proof released 0 0
TB="$(sh "$BP" "$ART" "$ID" "$H/channel2")"
X="$H/x"; mkdir -p "$X"; tar -xzf "$TB" -C "$X"
printf 'x' >> "$X/bin/codex-code-mode-host"
COPYFILE_DISABLE=1 tar -czf "$H/bad.tar.gz" -C "$X" codex-package.json bin/codex bin/codex-code-mode-host \
  codex-resources codex-path/rg LICENSE NOTICE build-manifest
refused "a tarball whose host is not the proven one" "bin/codex-code-mode-host is not the proven" cross "$H/bad.tar.gz"
refused "a tarball that is not there" "no tarball" cross "$H/none.tar.gz"

rc=0; sh "$CHECK" sideways >/dev/null 2>&1 || rc=$?
h_assert_eq 2 "$rc" "an unknown mode is a usage error"

# ---- the workflow and the CTest guards ----
WF="$H_REPO/.github/workflows/builds.yml"
# line LITERAL: the first builds.yml line holding LITERAL, or 0
line() { grep -nF -- "$1" "$WF" | head -1 | cut -d: -f1 || true; }
before() {
  a=$(line "$1"); b=$(line "$2")
  if [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]; then :; else
    echo "FAIL: builds.yml: '$1' (line ${a:-none}) must come before '$2' (line ${b:-none})" >&2; H_FAILS=$((H_FAILS+1)); fi
}
before "sh build/build-codex.sh cross" "sh build/objc-build-evidence.sh cross"
before "sh build/objc-build-evidence.sh cross" "shipyard-cmake --preset cross"
before "shipyard-ctest --preset cross" "sh build/objc-publication-check.sh cross"
before "sh build/objc-publication-check.sh cross" "sh packaging/build-codex-package.sh"
before "sh packaging/build-codex-package.sh" 'sh build/objc-publication-check.sh cross "$BUILD/channel/'
before 'sh build/objc-publication-check.sh cross "$BUILD/channel/' "sh build/channel-publish.sh sign"
for t in compat_guard_codex compat_guard_codex-code-mode-host; do
  h_assert_contains "$(cat "$WF")" "$t" "builds.yml requires CTest to have $t"
done
h_assert_contains "$(cat "$WF")" "name: codex-build-objc-proof" "builds.yml uploads the proof as a diagnostic, beside the channel"
CM="$(sed -n '/add_test(NAME compat_guard_/,/)$/p' "$H_REPO/CMakeLists.txt")"
h_assert_contains "$CM" 'build/compat-guard.sh' "the CTest guard is build/compat-guard.sh, which uses the build's own proof"
h_done
