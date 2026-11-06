#!/bin/sh
# platform: macOS-only -- plutil reads the provider declaration; shipyard's provider helper builds against the host SDK
#   usage: fetch-recaulk-objc.sh
#          The Recaulk prefix whose Objective-C provider recaulk.nsworkspace.open-urls.v1 (the 10.9
#          backfill of -[NSWorkspace openURLs:withApplicationAtURL:options:configuration:error:], which
#          webbrowser calls when `codex login` opens the browser) the codex binary links. Prints three
#          lines on stdout: the prefix, its origin (`released` or `development`) and its version (the
#          pinned release tag, or `development`). Everything else goes to stderr.
#          released: components/recaulk/version holds an actual Recaulk release tag (YYYYMMDD.N); the
#            pkg is fetched and verified against the release's SHA256SUMS by shipyard's
#            fetch_product_pkg.sh and extracted under the build root, never installed.
#          development: CODEX_DEV_RECAULK_PREFIX names a staged prefix (Recaulk's build/build-objc.sh
#            STAGE WORK) by absolute path. It wins over the pin, and its origin is always development:
#            build-codex.sh records that in the build manifest, and packaging refuses such a build
#            whatever its BUILD_ID.
#          With neither, it fails: there is no fallback to an installed Recaulk, to the clang-22
#          product's librecaulk.a or to an older package. Until a released Recaulk carries the
#          provider, components/recaulk/version stays absent and only development builds link it.
#          Either prefix must pass shipyard's declaration check (objc-provider-link-args.sh: exact keys,
#          a shipping x86_64 archive for 10.9 whose bytes match the declared digest) and then declare
#          exactly the provider Codex needs: id, class, method kind, selector, ABI encoding and
#          activation root. This validates metadata only; whether the final artifact really carries the
#          provider is objc-compat.sh's verdict on the built bytes.
#          Exit 0 printed, 1 refused.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MAVERICKS_BUILD_DIR=$HERE
export MAVERICKS_BUILD_DIR
. "$HERE/lib.sh"

PROVIDER_ID=recaulk.nsworkspace.open-urls.v1
CLASS=NSWorkspace
KIND=-
SELECTOR='openURLs:withApplicationAtURL:options:configuration:error:'
ENCODING='@56@0:8@16@24Q32@40^@48'
ROOT=__recaulk_objc_activate

fail() { echo "fetch-recaulk-objc: $*" >&2; exit 1; }

# platform: the shared interfaces this provider's linkage and proof go through. A shipyard too old to
#           have them cannot link or prove the provider, so it is refused here, before anything links.
for helper in objc-provider-link-args.sh objc-build-evidence.sh objc-compat.sh; do
  [ -f "$SHIPYARD_SCRIPTS/$helper" ] ||
    fail "shipyard at $SHIPYARD_SCRIPTS has no $helper: Codex needs a shipyard with Objective-C artifact enforcement"
done

nl='
'
cr=$(printf '\r')
# pl KEYPATH: the one-line string at KEYPATH in $decl, or nothing.
pl() { plutil -extract "$1" xml1 -o - "$decl" 2>/dev/null | sed -n 's:^<string>\(.*\)</string>$:\1:p'; }
check() {
  got=$(pl "$1")
  [ "$got" = "$2" ] || fail "$decl: $1 is '$got', Codex needs '$2'"
}
# validate PREFIX: PREFIX declares exactly the provider Codex needs, and shipyard accepts its declaration.
validate() {
  p=$1
  case "$p" in /*) ;; *) fail "the Recaulk prefix must be an absolute path: $p" ;; esac
  case "$p" in *"$nl"*|*"$cr"*) fail "the Recaulk prefix holds a line break" ;; esac
  [ -d "$p" ] || fail "no Recaulk prefix at $p"
  decl="$p/share/recaulk/objc-providers.json"
  [ -f "$decl" ] || fail "$p has no share/recaulk/objc-providers.json: a Recaulk without Objective-C providers cannot back-fill openURLs on 10.9"
  probe=$(mktemp -d "${TMPDIR:-/tmp}/fetch-recaulk-objc.XXXXXX")
  rc=0
  sh "$SHIPYARD_SCRIPTS/objc-provider-link-args.sh" --prefix "$p" --link-map "$probe/probe.map" > "$probe/args" 2> "$probe/err" || rc=$?
  args=$(cat "$probe/args"); err=$(cat "$probe/err")
  rm -rf "$probe"
  [ "$rc" = 0 ] || fail "shipyard refused the provider declaration of $p (exit $rc): $err"
  printf '%s\n' "$args" | grep -qx -- "-Wl,-u,_$ROOT" ||
    fail "$p does not root $ROOT (shipyard printed no -Wl,-u,_$ROOT)"
  found=
  i=0
  # platform: plutil prints a failed -extract's error on stdout, so both streams are discarded.
  while plutil -extract "providers.$i" xml1 -o /dev/null "$decl" >/dev/null 2>&1; do
    if [ "$(pl "providers.$i.provider_id")" = "$PROVIDER_ID" ]; then
      [ -z "$found" ] || fail "$decl declares $PROVIDER_ID twice"
      found=$i
    fi
    i=$((i + 1))
  done
  [ -n "$found" ] || fail "$decl does not declare $PROVIDER_ID"
  check "providers.$found.class" "$CLASS"
  check "providers.$found.method_kind" "$KIND"
  check "providers.$found.selector" "$SELECTOR"
  check "providers.$found.encoding" "$ENCODING"
  check "providers.$found.activation_root" "$ROOT"
  [ -n "$(pl "providers.$found.implementation_symbol")" ] || fail "$PROVIDER_ID in $decl names no implementation symbol"
  check build.architecture x86_64
  check build.artifact_role shipping
  check build.minimum_macos 10.9
}

if [ -n "${CODEX_DEV_RECAULK_PREFIX:-}" ]; then
  validate "$CODEX_DEV_RECAULK_PREFIX"
  echo "fetch-recaulk-objc: development provider at $CODEX_DEV_RECAULK_PREFIX: this build is never publishable" >&2
  printf '%s\ndevelopment\ndevelopment\n' "$CODEX_DEV_RECAULK_PREFIX"
  exit 0
fi

PIN="$MAVERICKS_ROOT/components/recaulk/version"
[ -f "$PIN" ] || fail "no components/recaulk/version: no released Recaulk carrying $PROVIDER_ID is pinned yet, and nothing falls back to an installed one. For a development build, name a staged prefix (Recaulk's build/build-objc.sh STAGE WORK) with CODEX_DEV_RECAULK_PREFIX; such a build is never publishable"
TAG=$(tr -d '[:space:]' < "$PIN")
printf '%s\n' "$TAG" | grep -Eqx '[0-9]{8}\.[1-9][0-9]*' || fail "components/recaulk/version holds '$TAG', not a Recaulk release tag (YYYYMMDD.N)"
BUILD_ROOT=$(mavericks_build_root)
PREFIX=$(sh "$SHIPYARD_SCRIPTS/fetch_product_pkg.sh" recaulk "$TAG" "$BUILD_ROOT/recaulk-$TAG") ||
  fail "could not fetch and verify Recaulk $TAG"
validate "$PREFIX"
printf '%s\nreleased\n%s\n' "$PREFIX" "$TAG"
