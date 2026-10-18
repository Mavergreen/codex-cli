#!/bin/sh
# platform: host-agnostic -- plain sh; runs on ultimate-hat and modern macOS
#   usage: channel-publish.sh sign --repo R --tag T --dir D --id ID --key-env VAR --signer PATH
#                             [--tarball-prefix P]
#          channel-publish.sh upload --repo R --tag T --dir D --id ID [--verify-with PUBKEY]
#                             [--title TITLE] [--tarball-prefix P] [--keep-newest N] [--keep-minors N]
#          Publishes the build ID to the release T of repo R, which serves as a builds channel and is
#          never the repo's Latest, in two steps, so that only the step that signs holds the key and
#          the step that writes to the channel holds none. D holds <P>ID.tar.gz and
#          codex-build-ID.json. Both steps first check the staged JSON against ID and the tarball,
#          refuse a build that needs a newer package than the repo's Latest, and refuse an ID older
#          than a build already on the channel. The same ID is a retry only when the channel's
#          codex-build-ID.json is byte for byte the staged one; otherwise another run published this
#          build number first, and this one is refused. Neither step changes the channel when a check
#          fails. Assets are fetched by their id from the paginated listing, never by name lookup.
#          sign: signs the JSON (the private key goes from the environment variable named by
#          --key-env to the signer's stdin, nowhere else) into codex-build-ID.json.sig, and writes
#          latest.json and latest.json.sig as byte copies. It only reads the channel.
#          upload: takes no key. It requires the signature and both byte copies, one line each; with
#          --verify-with, each signature must verify over its JSON against PUBKEY (the base64 raw
#          Ed25519 public key the package ships), checked with OpenSSL 3. It then creates the
#          release if absent, uploads the build, and replaces latest.json and latest.json.sig.
#          A newer run can publish between this run's staleness check and that replace, so the
#          replace may leave latest.json naming an older build than the channel's newest. So the
#          channel is listed again, and while its newest build is not the one latest.json names,
#          that build's own JSON and signature (verified, with --verify-with) are uploaded as
#          latest.json and latest.json.sig. It gives up, non-zero, after a few attempts
#          (CODEX_CHANNEL_SETTLE_SECONDS apart, default 10). Only then does it delete the builds
#          channel-prune.sh drops, never ID or what latest.json names. gh is found on PATH.
set -eu

usage() {
  echo "usage: channel-publish.sh sign --repo R --tag T --dir D --id ID --key-env VAR --signer PATH" >&2
  echo "       channel-publish.sh upload --repo R --tag T --dir D --id ID [--verify-with PUBKEY]" >&2
  exit 2
}

MODE=${1:-}
case "$MODE" in
  sign|upload) shift ;;
  *) usage ;;
esac
REPO=
TAG=
DIR=
ID=
KEY_ENV=
SIGNER=
VERIFY_WITH=
TITLE='Codex builds (fetched by codex update)'
PREFIX=codex-package-x86_64-apple-darwin-
KEEP_NEWEST=10
KEEP_MINORS=30
while [ "$#" -gt 0 ]; do
  [ "$#" -ge 2 ] || usage
  case "$1" in
    --repo) REPO=$2 ;;
    --tag) TAG=$2 ;;
    --dir) DIR=$2 ;;
    --id) ID=$2 ;;
    --key-env) KEY_ENV=$2 ;;
    --signer) SIGNER=$2 ;;
    --verify-with) VERIFY_WITH=$2 ;;
    --title) TITLE=$2 ;;
    --tarball-prefix) PREFIX=$2 ;;
    --keep-newest) KEEP_NEWEST=$2 ;;
    --keep-minors) KEEP_MINORS=$2 ;;
    *) usage ;;
  esac
  shift 2
done
[ -n "$REPO" ] && [ -n "$TAG" ] && [ -n "$DIR" ] && [ -n "$ID" ] || usage
if [ "$MODE" = sign ]; then
  [ -n "$KEY_ENV" ] && [ -n "$SIGNER" ] && [ -z "$VERIFY_WITH" ] || usage
elif [ -n "$KEY_ENV" ] || [ -n "$SIGNER" ]; then
  echo "channel-publish: upload takes no key; sign the directory first" >&2
  exit 2
fi

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
LC_ALL=C
export LC_ALL

ID_FORMAT='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)-mavericks\.[1-9][0-9]*$'
die() {
  echo "channel-publish: $*" >&2
  exit 1
}
SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/channel-publish.XXXXXX")
trap 'rm -rf "$SCRATCH"' EXIT
printf '%s\n' "$ID" | grep -Eq "$ID_FORMAT" || die "not a build identity: $ID"
TARBALL="$PREFIX$ID.tar.gz"
JSON="codex-build-$ID.json"
for file in "$TARBALL" "$JSON"; do
  [ -f "$DIR/$file" ] || die "no $file in $DIR"
done

# one_line FILE: FILE holds exactly one non-empty line
one_line() {
  [ -s "$1" ] && [ "$(wc -l < "$1" | tr -d ' ')" -eq 1 ] && [ -n "$(head -n 1 "$1")" ]
}

if [ "$MODE" = sign ]; then
  [ -x "$SIGNER" ] || die "cannot run the signer at $SIGNER"
  # The key is only ever named (printenv VAR) and piped; it is never expanded into a command line,
  # which `sh -x` would trace.
  printenv "$KEY_ENV" | grep -q . || die "\$$KEY_ENV is not set"
else
  one_line "$DIR/$JSON.sig" || die "$JSON.sig is missing or not one line; sign the directory first"
  cmp -s "$DIR/$JSON" "$DIR/latest.json" || die "latest.json is not a byte copy of $JSON"
  cmp -s "$DIR/$JSON.sig" "$DIR/latest.json.sig" || die "latest.json.sig is not a byte copy of $JSON.sig"
fi

# verify_sig DIR FILE: DIR/FILE.sig verifies over DIR/FILE against $VERIFY_WITH. OpenSSL takes an
# Ed25519 public key as a SubjectPublicKeyInfo: this fixed 12-byte DER prefix, then the raw 32 bytes.
verify_sig() {
  tr -d '[:space:]' < "$1/$2.sig" | openssl base64 -d -A > "$SCRATCH/sig" ||
    die "$2.sig is not base64"
  openssl pkeyutl -verify -pubin -inkey "$SCRATCH/key.der" -keyform DER -rawin \
    -in "$1/$2" -sigfile "$SCRATCH/sig" > /dev/null 2>&1 ||
    die "$2.sig does not verify against $VERIFY_WITH"
}
if [ -n "$VERIFY_WITH" ]; then
  [ -f "$VERIFY_WITH" ] || die "no public key at $VERIFY_WITH"
  command -v openssl > /dev/null 2>&1 || die "--verify-with needs openssl on PATH"
  { printf '\060\052\060\005\006\003\053\145\160\003\041\000'
    tr -d '[:space:]' < "$VERIFY_WITH" | openssl base64 -d -A; } > "$SCRATCH/key.der" ||
    die "cannot read the public key $VERIFY_WITH"
  [ "$(wc -c < "$SCRATCH/key.der" | tr -d ' ')" -eq 44 ] ||
    die "$VERIFY_WITH is not a base64 raw Ed25519 public key (32 bytes)"
  verify_sig "$DIR" "$JSON"
  verify_sig "$DIR" latest.json
fi

# newest: of the build identities on stdin, the newest, numerically (major, minor, patch, N)
newest() {
  awk '
    /^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)-mavericks\.[1-9][0-9]*$/ { split($0, v, /[.-]/); print v[1], v[2], v[3], v[5], $0 }' |
    sort -k1,1nr -k2,2nr -k3,3nr -k4,4nr | awk 'NR == 1 { print $5 }'
}

# list_channel: LISTING ("<id> <name>" lines) and ASSETS (the names) of the release, or fail
list_channel() {
  LISTING=$(sh "$HERE/channel-assets.sh" --ids "$REPO" "$TAG") || return 1
  ASSETS=$(printf '%s\n' "$LISTING" | sed -n 's/^[0-9][0-9]* //p')
}

# fetch NAME OUT: the bytes of the asset NAME, fetched by its id from the last listing
fetch() {
  _asset_id=$(printf '%s\n' "$LISTING" | awk -v n="$1" '$2 == n { print $1; exit }')
  [ -n "$_asset_id" ] || return 1
  gh api -H 'Accept: application/octet-stream' "repos/$REPO/releases/assets/$_asset_id" > "$2"
}

# the staged JSON must describe exactly this build and this tarball
json_field() {
  sed -n "s/.*\"$1\":\"\\([^\"]*\\)\".*/\\1/p" "$DIR/$JSON"
}
[ "$(json_field mavergreen_build)" = "$ID" ] || die "$JSON does not record mavergreen_build $ID"
[ "$(json_field tag_name)" = "rust-v$ID" ] || die "$JSON does not record tag_name rust-v$ID"
JSON_ASSET=$(sed -n 's/.*"assets":\[{"name":"\([^"]*\)","digest":"sha256:\([0-9a-f]*\)"}\].*/\1 \2/p' "$DIR/$JSON")
[ "${JSON_ASSET%% *}" = "$TARBALL" ] || die "$JSON does not name $TARBALL as its one asset"
TARBALL_DIGEST=$(shasum -a 256 < "$DIR/$TARBALL" | awk '{print $1}')
[ -n "$TARBALL_DIGEST" ] && [ "${JSON_ASSET#* }" = "$TARBALL_DIGEST" ] || die "$JSON records a digest that is not the staged $TARBALL's"

# True when version $1 (YYYYMMDD.N) is newer than $2, by date and then N, both numerically.
pkg_newer() {
  [ "${1%%.*}" -ne "${2%%.*}" ] && { [ "${1%%.*}" -gt "${2%%.*}" ]; return; }
  [ "${1#*.}" -gt "${2#*.}" ]
}

# the min-pkg refusal comes first, before the channel is read at all
MIN_PKG=$(json_field mavergreen_min_pkg)
if [ -n "$MIN_PKG" ]; then
  PKG_FORMAT='^[0-9]{8}\.[0-9]{1,4}$'
  printf '%s\n' "$MIN_PKG" | grep -Eq "$PKG_FORMAT" ||
    die "$JSON asks for a package version that is not YYYYMMDD.N: $MIN_PKG"
  LATEST_TAG=$(gh release view -R "$REPO" --json tagName -q .tagName) ||
    die "cannot read the Latest release of $REPO"
  LATEST_PKG=${LATEST_TAG#v}
  printf '%s\n' "$LATEST_PKG" | grep -Eq "$PKG_FORMAT" ||
    die "the Latest release of $REPO is $LATEST_TAG, not [v]YYYYMMDD.N"
  if pkg_newer "$MIN_PKG" "$LATEST_PKG"; then
    die "$ID needs package $MIN_PKG, newer than the Latest release $LATEST_TAG; release the package first"
  fi
fi

# a missing release holds no builds; an existing one must not hold a build newer than ID
ASSETS=
RELEASE_EXISTS=no
# only gh's own "release not found" means absent; any other failure may hide builds, so stop
VIEW_OUT=$(gh release view "$TAG" -R "$REPO" 2>&1) && VIEW_STATUS=0 || VIEW_STATUS=$?
if [ "$VIEW_STATUS" -ne 0 ]; then
  case "$VIEW_OUT" in
    *"release not found"*) ;;
    *) die "cannot tell whether the $TAG release of $REPO exists: $VIEW_OUT" ;;
  esac
else
  RELEASE_EXISTS=yes
  list_channel || die "cannot list the $TAG release of $REPO"
  TOP=$({ printf '%s\n' "$ASSETS" | sed -n 's/^codex-build-\(.*\)\.json$/\1/p'; printf '%s\n' "$ID"; } | newest)
  [ "$TOP" = "$ID" ] || die "$TOP is already on the channel and is newer than $ID; refusing to publish a stale build"
  # the same ID on the channel is a retry only if it is this very build
  if printf '%s\n' "$ASSETS" | grep -Fxq "$JSON"; then
    fetch "$JSON" "$SCRATCH/published.json" ||
      die "$ID is already on the channel, and its $JSON cannot be fetched to compare"
    cmp -s "$SCRATCH/published.json" "$DIR/$JSON" ||
      die "$ID is already on the channel as a different build: another run published this build number first; this one publishes nothing (dispatch builds.yml again to take the next number)"
  fi
fi

if [ "$MODE" = sign ]; then
  SIG=$(printenv "$KEY_ENV" | "$SIGNER" -f - "$DIR/$JSON") || die "signing $JSON failed"
  [ -n "$SIG" ] || die "the signer printed no signature"
  case "$SIG" in
    *'
'*) die "the signer printed more than one line" ;;
  esac
  printf '%s\n' "$SIG" > "$DIR/$JSON.sig"
  cp "$DIR/$JSON" "$DIR/latest.json"
  cp "$DIR/$JSON.sig" "$DIR/latest.json.sig"
  exit 0
fi

if [ "$RELEASE_EXISTS" = no ]; then
  gh release create "$TAG" -R "$REPO" --latest=false --title "$TITLE" --notes "" >/dev/null
fi
gh release upload "$TAG" -R "$REPO" --clobber "$DIR/$TARBALL" "$DIR/$JSON" "$DIR/$JSON.sig"
gh release upload "$TAG" -R "$REPO" --clobber "$DIR/latest.json" "$DIR/latest.json.sig"

# From here the new build is live. Re-point latest.json while a newer build than the one it names
# is on the channel; a failure below only leaves latest.json or old builds behind.
POINTED=$ID
ATTEMPTS=0
mkdir "$SCRATCH/latest"
while :; do
  list_channel || die "$ID is published and live, but the release's assets cannot be listed"
  NEWEST=$(printf '%s\n' "$ASSETS" | sed -n 's/^codex-build-\(.*\)\.json$/\1/p' | newest)
  [ "$NEWEST" = "$POINTED" ] && break
  ATTEMPTS=$((ATTEMPTS + 1))
  [ "$ATTEMPTS" -le 5 ] ||
    die "$ID is published, but latest.json names $POINTED while $NEWEST is the channel's newest build, and it would not settle"
  echo "channel-publish: $NEWEST reached the channel while $ID was published; pointing latest.json at $NEWEST" >&2
  if fetch "codex-build-$NEWEST.json" "$SCRATCH/latest/latest.json" &&
    fetch "codex-build-$NEWEST.json.sig" "$SCRATCH/latest/latest.json.sig" &&
    one_line "$SCRATCH/latest/latest.json.sig"; then
    [ -z "$VERIFY_WITH" ] || verify_sig "$SCRATCH/latest" latest.json
    gh release upload "$TAG" -R "$REPO" --clobber "$SCRATCH/latest/latest.json" "$SCRATCH/latest/latest.json.sig"
    POINTED=$NEWEST
  else
    echo "channel-publish: $NEWEST's JSON and signature are not both there yet; trying again" >&2
  fi
  sleep "${CODEX_CHANNEL_SETTLE_SECONDS:-10}"
done
DOOMED=$(printf '%s\n' "$ASSETS" |
  sed -n 's/^codex-build-\(.*\)\.json$/\1/p' |
  sh "$HERE/channel-prune.sh" --keep-newest "$KEEP_NEWEST" --keep-minors "$KEEP_MINORS") ||
  die "$ID is published and live, but the retention rule failed"

# each build's JSON goes last, so a build whose earlier delete failed is still named next run
FAILED=0
for doomed in $DOOMED; do
  [ "$doomed" = "$ID" ] && continue
  for name in "$PREFIX$doomed.tar.gz" "codex-build-$doomed.json.sig" "codex-build-$doomed.json"; do
    printf '%s\n' "$ASSETS" | grep -Fxq "$name" || continue
    if ! gh release delete-asset "$TAG" "$name" -R "$REPO" --yes; then
      echo "channel-publish: could not delete $name" >&2
      FAILED=1
      break
    fi
  done
done
if [ "$FAILED" -ne 0 ]; then
  die "$ID is published and live, but some old builds could not be deleted"
fi
