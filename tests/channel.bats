#!/usr/bin/env bats
# platform: host-agnostic -- fixtures, fake gh and fake signer; runs on ultimate-hat and modern macOS

# The channel scripts build, prune and publish the builds channel. gh and the signer are fakes on
# PATH, so no test touches the network or holds a real key. Publishing is two steps: sign, which
# holds the key and only reads the channel, then upload, which every test runs without the key.
setup() {
  export PRODUCT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  build="$PRODUCT_ROOT/build"
  work="$BATS_TEST_TMPDIR/work dir"
  mkdir -p "$work/bin" "$work/dir"
  export FAKE_STATE="$work/state"          # assets on the release, one name per line
  export FAKE_LOG="$work/gh.log"           # one line per gh call: its argv
  export FAKE_SIGNER_LOG="$work/signer.log"
  export FAKE_EXISTS="$work/release-exists"
  export FAKE_PUBLISHED="$work/published"  # the bytes of each asset on the release
  mkdir -p "$FAKE_PUBLISHED"
  export FAKE_LATEST_TAG=v20261017.1
  export SECRET_KEY="TOPSECRET-key-material-0123456789"
  export CODEX_CHANNEL_SETTLE_SECONDS=0
  : > "$FAKE_STATE"; : > "$FAKE_LOG"; : > "$FAKE_SIGNER_LOG"
  PATH="$work/bin:$PATH"
  cat > "$work/bin/gh" <<'FAKE'
#!/bin/sh
echo "$*" >> "$FAKE_LOG"
case "$1 $2" in
  "release view")
    case "$*" in
      *tagName*) echo "$FAKE_LATEST_TAG" ;;
      *) [ -n "${FAKE_VIEW_ERROR:-}" ] && { echo "$FAKE_VIEW_ERROR" >&2; exit 1; }
         [ -f "$FAKE_EXISTS" ] || { echo "release not found" >&2; exit 1; } ;;
    esac ;;
  "release create") : > "$FAKE_EXISTS" ;;
  "release upload")
    shift 2
    # another run publishes FAKE_RACE_DIR's build just before this run replaces latest.json
    case "$*" in
      *latest.json*)
        if [ -n "${FAKE_RACE_DIR:-}" ] && [ ! -f "$FAKE_RACE_DIR.done" ]; then
          : > "$FAKE_RACE_DIR.done"
          for f in "$FAKE_RACE_DIR"/*; do basename "$f" >> "$FAKE_STATE"; cp "$f" "$FAKE_PUBLISHED/"; done
        fi ;;
    esac
    for arg in "$@"; do
      [ -f "$arg" ] && { basename "$arg" >> "$FAKE_STATE"; cp "$arg" "$FAKE_PUBLISHED/"; }
    done
    sort -u "$FAKE_STATE" > "$FAKE_STATE.new"; mv "$FAKE_STATE.new" "$FAKE_STATE" ;;
  "release delete-asset")
    case " ${FAKE_FAIL_DELETE:-} " in *" $4 "*) exit 1 ;; esac
    grep -Fxv "$4" "$FAKE_STATE" > "$FAKE_STATE.new"; mv "$FAKE_STATE.new" "$FAKE_STATE" ;;
  "api repos"*|"api --paginate")
    case "$*" in
      *"/assets?per_page=100"*'.id'*)
        # an asset's id is the cksum of its name: numeric, and stable across calls
        while IFS= read -r n; do
          [ -n "$n" ] && printf '%s %s\n' "$(printf '%s' "$n" | cksum | cut -d' ' -f1)" "$n"
        done < "$FAKE_STATE" ;;
      *"/assets?per_page=100"*) cat "$FAKE_STATE" ;;
      *"/releases/tags/"*) echo 42 ;;
      *) exit 1 ;;
    esac ;;
  "api -H")
    case "$3" in "Accept: application/octet-stream") ;; *) exit 1 ;; esac
    want=${4##*/}
    while IFS= read -r n; do
      if [ "$(printf '%s' "$n" | cksum | cut -d' ' -f1)" = "$want" ]; then
        [ -f "$FAKE_PUBLISHED/$n" ] || exit 1
        cat "$FAKE_PUBLISHED/$n"; exit 0
      fi
    done < "$FAKE_STATE"
    echo "HTTP 404: Not Found" >&2; exit 1 ;;
  *) exit 1 ;;
esac
FAKE
  cat > "$work/bin/fake-signer" <<'FAKE'
#!/bin/sh
echo "$*" >> "$FAKE_SIGNER_LOG"
key=$(cat)
[ "$key" = "$SECRET_KEY" ] || exit 1
echo "fakesig-$(shasum -a 256 < "$3" | cut -c1-16)"
FAKE
  chmod +x "$work/bin/gh" "$work/bin/fake-signer"
}

# ---- the JSON ----

state_hex() { printf 'ab%.0s' $(seq 1 32); }

make_json() {
  printf 'tarball bytes\n' > "$work/dir/codex-package-x86_64-apple-darwin-0.200.1-mavericks.3.tar.gz"
  sh "$build/channel-json.sh" --id 0.200.1-mavericks.3 --codex-version 0.200.1 \
    --tarball "$work/dir/codex-package-x86_64-apple-darwin-0.200.1-mavericks.3.tar.gz" \
    --min-pkg "${1-20261017.1}" --state "$(state_hex)"
}

# Source just parse_release_metadata: the installer runs its whole job when sourced, so extract it.
parse() {
  sed -n '/^parse_release_metadata() {/,/^}/p' "$PRODUCT_ROOT/tree/libexec/codex-cli/install.sh" > "$work/parse.sh"
  . "$work/parse.sh"
  parse_release_metadata
}

@test "the build JSON is one line the installer's parser reads" {
  json=$(make_json)
  [ "$(printf '%s\n' "$json" | wc -l | tr -d ' ')" -eq 1 ]
  digest=$(printf 'tarball bytes\n' | shasum -a 256 | awk '{print $1}')
  out=$(printf '%s\n' "$json" | parse)
  [ "$out" = "tag_name	rust-v0.200.1-mavericks.3
min_pkg	20261017.1
asset	codex-package-x86_64-apple-darwin-0.200.1-mavericks.3.tar.gz	sha256:$digest" ]
}

@test "the JSON has the contract's exact shape, and an empty min-pkg stays empty" {
  json=$(make_json "")
  digest=$(printf 'tarball bytes\n' | shasum -a 256 | awk '{print $1}')
  [ "$json" = '{"tag_name":"rust-v0.200.1-mavericks.3","mavergreen_build":"0.200.1-mavericks.3","mavergreen_codex_version":"0.200.1","mavergreen_min_pkg":"","mavergreen_state":"'"$(state_hex)"'","assets":[{"name":"codex-package-x86_64-apple-darwin-0.200.1-mavericks.3.tar.gz","digest":"sha256:'"$digest"'"}]}' ]
}

@test "the JSON refuses a bad identity, state or min-pkg" {
  : > "$work/codex-package-x86_64-apple-darwin-0.200.1-mavericks.1.tar.gz"
  run sh "$build/channel-json.sh" --id 0.200.1-mavericks.0 --codex-version 0.200.1 --tarball "$work/codex-package-x86_64-apple-darwin-0.200.1-mavericks.1.tar.gz" --min-pkg "" --state "$(state_hex)"
  [ "$status" -eq 1 ]
  run sh "$build/channel-json.sh" --id 0.200.1-mavericks.1 --codex-version 0.200.1 --tarball "$work/codex-package-x86_64-apple-darwin-0.200.1-mavericks.1.tar.gz" --min-pkg "" --state abc
  [ "$status" -eq 1 ]
  run sh "$build/channel-json.sh" --id 0.200.1-mavericks.1 --codex-version 0.200.1 --tarball "$work/codex-package-x86_64-apple-darwin-0.200.1-mavericks.1.tar.gz" --min-pkg 2026.1 --state "$(state_hex)"
  [ "$status" -eq 1 ]
  [[ "$output" == channel-json:* ]] || false
}

@test "the JSON refuses leading zeros and a tarball that is not the contract name for the id" {
  : > "$work/codex-package-x86_64-apple-darwin-0.200.1-mavericks.1.tar.gz"
  run sh "$build/channel-json.sh" --id 0.200.01-mavericks.1 --codex-version 0.200.01 --tarball "$work/codex-package-x86_64-apple-darwin-0.200.1-mavericks.1.tar.gz" --min-pkg "" --state "$(state_hex)"
  [ "$status" -eq 1 ]
  : > "$work/t.tgz"
  run sh "$build/channel-json.sh" --id 0.200.1-mavericks.1 --codex-version 0.200.1 --tarball "$work/t.tgz" --min-pkg "" --state "$(state_hex)"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not codex-package-x86_64-apple-darwin-0.200.1-mavericks.1.tar.gz"* ]] || false
  : > "$work/codex-package-x86_64-apple-darwin-0.200.1-mavericks.2.tar.gz"
  run sh "$build/channel-json.sh" --id 0.200.1-mavericks.1 --codex-version 0.200.1 --tarball "$work/codex-package-x86_64-apple-darwin-0.200.1-mavericks.2.tar.gz" --min-pkg "" --state "$(state_hex)"
  [ "$status" -eq 1 ]
}

# ---- pruning ----

# history X.Y MAXPATCH... : one build N=1 of each patch, plus the lines given
prune() { sh "$build/channel-prune.sh" "$@"; }

@test "12 builds of one minor: the two oldest go; the minor's last build stays" {
  for n in 1 2 3 4 5 6 7 8 9 10 11 12; do echo "1.5.0-mavericks.$n"; done > "$work/h"
  run prune < "$work/h"
  [ "$status" -eq 0 ]
  [ "$output" = "1.5.0-mavericks.2
1.5.0-mavericks.1" ]
}

@test "the newest 10 are always kept, whatever they are" {
  for p in 1 2 3 4 5 6 7 8 9 10 11 12; do echo "1.$p.0-mavericks.1"; done > "$work/h"
  run prune --keep-minors 0 < "$work/h"
  [ "$status" -eq 0 ]
  # 1.12 .. 1.3 are the newest ten; 1.2 and 1.1 are not, and 1.1.0 is the last of major 1 only if newest
  [ "$output" = "1.2.0-mavericks.1
1.1.0-mavericks.1" ]
}

@test "ordering is numeric: 0.9 is older than 0.10, build 9 older than build 10" {
  printf '%s\n' 0.9.0-mavericks.1 0.10.0-mavericks.2 0.10.0-mavericks.10 0.10.0-mavericks.9 > "$work/h"
  run prune --keep-newest 1 --keep-minors 0 < "$work/h"
  # newest is 0.10.0-mavericks.10 (kept); 0.10.0-mavericks.2/.9 lose; 0.9.0 is not major's last; 0.10.0 .10 is the major's last
  [ "$output" = "0.10.0-mavericks.9
0.10.0-mavericks.2
0.9.0-mavericks.1" ]
}

@test "45 minors: outside the newest 30 only the multiples of ten survive" {
  # two builds of each minor 1.1 .. 1.45, to prove only the last build of a minor is kept
  for m in $(seq 1 45); do echo "1.$m.0-mavericks.1"; echo "1.$m.0-mavericks.2"; done > "$work/h"
  run prune < "$work/h"
  [ "$status" -eq 0 ]
  # each minor's first build is dropped unless it is among the newest ten (1.45 .. 1.41 have two each)
  kept_last=0
  for m in $(seq 1 45); do
    if printf '%s\n' "$output" | grep -Fxq "1.$m.0-mavericks.2"; then
      # a deleted last build: must be outside the newest 30 (m <= 15), not a multiple of 10, not minor 1.1's... major 1's last is 1.45
      [ "$m" -le 15 ]
      [ $((m % 10)) -ne 0 ]
    fi
  done
  printf '%s\n' "$output" | grep -Fxq "1.5.0-mavericks.2"
  printf '%s\n' "$output" | grep -Fxq "1.15.0-mavericks.2"
  ! printf '%s\n' "$output" | grep -Fxq "1.10.0-mavericks.2" || false
  ! printf '%s\n' "$output" | grep -Fxq "1.20.0-mavericks.2" || false
  ! printf '%s\n' "$output" | grep -Fxq "1.16.0-mavericks.2" || false
  ! printf '%s\n' "$output" | grep -Fxq "1.45.0-mavericks.2" || false
  # newest first: the newest ten end at 1.41.0-mavericks.1, so 1.40.0-mavericks.1 is the newest to go
  [ "$(printf '%s\n' "$output" | head -n 1)" = "1.40.0-mavericks.1" ]
}

@test "0.160.x's last build survives any history" {
  { echo 0.160.0-mavericks.1; echo 0.160.4-mavericks.2; echo 0.160.4-mavericks.1
    for m in $(seq 161 260); do echo "0.$m.0-mavericks.1"; done; } > "$work/h"
  run prune < "$work/h"
  [ "$status" -eq 0 ]
  ! printf '%s\n' "$output" | grep -Fxq "0.160.4-mavericks.2" || false
  printf '%s\n' "$output" | grep -Fxq "0.160.4-mavericks.1"
  printf '%s\n' "$output" | grep -Fxq "0.160.0-mavericks.1"
}

@test "the last build of every major survives" {
  { echo 1.0.0-mavericks.1; echo 2.0.0-mavericks.1
    for m in $(seq 1 60); do echo "3.$m.0-mavericks.1"; done; } > "$work/h"
  run prune < "$work/h"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -Fxq "3.1.0-mavericks.1"
  ! printf '%s\n' "$output" | grep -Fxq "1.0.0-mavericks.1" || false
  ! printf '%s\n' "$output" | grep -Fxq "2.0.0-mavericks.1" || false
}

@test "a deleted ID is never kept again by a later run over a longer history" {
  : > "$work/h"
  deleted=" "
  for round in $(seq 1 70); do
    echo "0.$((round / 2)).$((round % 3))-mavericks.$((round % 4 + 1))" >> "$work/h"
    sort -u "$work/h" > "$work/h2"; mv "$work/h2" "$work/h"
    out=$(prune < "$work/h")
    for id in $deleted; do
      # a deleted id that is still in the history (it is: nothing here removes it) must be deleted again
      printf '%s\n' "$out" | grep -Fxq "$id"
    done
    for id in $out; do case "$deleted" in *" $id "*) ;; *) deleted="$deleted$id " ;; esac; done
  done
}

@test "lines that are not identities are ignored with a warning on stderr" {
  printf '%s\n' 1.0.0-mavericks.1 garbage 1.0.0-mavericks.0 v1.0.0-mavericks.2 '' 1.0.0-mavericks.3 > "$work/h"
  sh "$build/channel-prune.sh" --keep-newest 1 --keep-minors 0 < "$work/h" > "$work/out" 2> "$work/err"
  [ "$(cat "$work/out")" = "1.0.0-mavericks.1" ]
  grep -Fq "ignoring a line that is not a build identity: garbage" "$work/err"
  grep -Fq "1.0.0-mavericks.0" "$work/err"
  grep -Fq "v1.0.0-mavericks.2" "$work/err"
}

@test "an empty history prunes nothing" {
  run prune < /dev/null
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ---- publishing ----

NEW=0.200.1-mavericks.3

stage() { # stage ID MIN_PKG: the tarball and the build JSON the build step would leave in the dir
  tarball="$work/dir/codex-package-x86_64-apple-darwin-$1.tar.gz"
  printf 'tarball of %s\n' "$1" > "$tarball"
  sh "$build/channel-json.sh" --id "$1" --codex-version "${1%%-*}" --tarball "$tarball" \
    --min-pkg "$2" --state "$(state_hex)" > "$work/dir/codex-build-$1.json"
}

seed() { # seed ID...: the channel already holds these builds
  : > "$FAKE_EXISTS"
  for id in "$@"; do
    printf 'codex-package-x86_64-apple-darwin-%s.tar.gz\ncodex-build-%s.json\ncodex-build-%s.json.sig\n' "$id" "$id" "$id" >> "$FAKE_STATE"
    printf '{"seeded":"%s"}\n' "$id" > "$FAKE_PUBLISHED/codex-build-$id.json"
  done
}

sign() {
  sh "$build/channel-publish.sh" sign --repo Mavergreen/codex-cli --tag codex-builds --dir "$work/dir" \
    --id "$1" --key-env SECRET_KEY --signer "$work/bin/fake-signer"
}

# upload runs with the key unset: it must never need it
upload() {
  env -u SECRET_KEY sh "$build/channel-publish.sh" upload --repo Mavergreen/codex-cli --tag codex-builds \
    --dir "$work/dir" --id "$1"
}

publish() {
  sign "$1" && upload "$1"
}

@test "publishing uploads, then latest, then deletes" {
  for n in 1 2 3 4 5 6 7 8 9 10 11 12; do seed "1.5.0-mavericks.$n"; done
  stage 1.5.0-mavericks.13 ""
  run publish 1.5.0-mavericks.13
  [ "$status" -eq 0 ]
  # the two uploads, then only deletes; the uploads' own order is checked below
  [ "$(grep -v "^api" "$FAKE_LOG" | awk '{print $1, $2}' | uniq | tr '\n' ,)" = "release view,release upload,release delete-asset," ]
  [ "$(grep -c '^release upload' "$FAKE_LOG")" -eq 2 ]
  uploads=$(grep '^release upload' "$FAKE_LOG")
  [ "$(printf '%s\n' "$uploads" | sed -n 1p | grep -c 'codex-package-x86_64-apple-darwin-1.5.0-mavericks.13.tar.gz.*codex-build-1.5.0-mavericks.13.json.*codex-build-1.5.0-mavericks.13.json.sig')" -eq 1 ]
  [ "$(printf '%s\n' "$uploads" | sed -n 2p | grep -c 'latest.json.*latest.json.sig')" -eq 1 ]
  printf '%s\n' "$uploads" | grep -q -- '--clobber'
  # three builds go (1, 2, 3), nine assets
  [ "$(grep -c '^release delete-asset' "$FAKE_LOG")" -eq 9 ]
  grep -Fq "release delete-asset codex-builds codex-build-1.5.0-mavericks.1.json " "$FAKE_LOG"
  # a build's JSON is deleted after its tarball and signature
  [ "$(grep -n 'delete-asset' "$FAKE_LOG" | grep 'mavericks.1[. ]' | sed 's/.*delete-asset codex-builds \([^ ]*\) .*/\1/' | tr '\n' ' ')" = "codex-package-x86_64-apple-darwin-1.5.0-mavericks.1.tar.gz codex-build-1.5.0-mavericks.1.json.sig codex-build-1.5.0-mavericks.1.json " ]
  ! grep -q 'delete-asset.*mavericks.13' "$FAKE_LOG" || false
  ! grep -q 'delete-asset.*mavericks.4\.' "$FAKE_LOG" || false
  # latest.json is a byte copy of the build JSON, and so is its signature
  cmp "$work/dir/latest.json" "$work/dir/codex-build-1.5.0-mavericks.13.json"
  cmp "$work/dir/latest.json.sig" "$work/dir/codex-build-1.5.0-mavericks.13.json.sig"
  [ "$(wc -l < "$work/dir/latest.json.sig" | tr -d ' ')" -eq 1 ]
}

@test "the release is created, with the contract's flags and title, when absent" {
  stage "$NEW" ""
  run publish "$NEW"
  [ "$status" -eq 0 ]
  grep -Fq -- "release create codex-builds -R Mavergreen/codex-cli --latest=false --title Codex builds (fetched by codex update)" "$FAKE_LOG"
  [ "$(grep -v '^api' "$FAKE_LOG" | awk '{print $1, $2}' | uniq | tr '\n' ,)" = "release view,release create,release upload," ]
}

@test "the release is not created again when it exists" {
  : > "$FAKE_EXISTS"
  stage "$NEW" ""
  run publish "$NEW"
  [ "$status" -eq 0 ]
  ! grep -q '^release create' "$FAKE_LOG" || false
  grep -q '^release upload' "$FAKE_LOG"
}

@test "a build that needs a newer package is refused before anything is changed" {
  stage "$NEW" 20261018.1
  run publish "$NEW"
  [ "$status" -eq 1 ]
  [[ "$output" == *"channel-publish:"* ]] || false
  ! grep -q -e '^release upload' -e '^release create' -e '^release delete' "$FAKE_LOG" || false
  [ ! -s "$FAKE_SIGNER_LOG" ]
}

@test "the min-pkg comparison is numeric, date first and then N, and accepts a bare tag" {
  stage "$NEW" 20261017.10
  FAKE_LATEST_TAG=20261017.9 run publish "$NEW"
  [ "$status" -eq 1 ]
  FAKE_LATEST_TAG=v20261017.10 run publish "$NEW"
  [ "$status" -eq 0 ]
  # a fresh channel: the same id staged again is a different build, which the channel would refuse
  : > "$FAKE_STATE"; rm -f "$FAKE_EXISTS" "$FAKE_PUBLISHED"/*
  stage "$NEW" 20261017.2
  FAKE_LATEST_TAG=20261101.1 run publish "$NEW"
  [ "$status" -eq 0 ]
}

@test "a Latest tag that is not a package version is refused clearly" {
  stage "$NEW" 20261017.1
  FAKE_LATEST_TAG=rust-v1.2.3 run publish "$NEW"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not [v]YYYYMMDD.N"* ]] || false
  ! grep -q '^release upload' "$FAKE_LOG" || false
}

@test "an empty min-pkg never asks for the Latest release" {
  stage "$NEW" ""
  run publish "$NEW"
  [ "$status" -eq 0 ]
  ! grep -q 'tagName' "$FAKE_LOG" || false
}

@test "the private key never reaches argv, logs or trace output" {
  stage "$NEW" ""
  run sh -x "$build/channel-publish.sh" sign --repo Mavergreen/codex-cli --tag codex-builds --dir "$work/dir" \
    --id "$NEW" --key-env SECRET_KEY --signer "$work/bin/fake-signer"
  [ "$status" -eq 0 ]
  ! printf '%s\n' "$output" | grep -Fq "$SECRET_KEY" || false
  ! grep -Fq "$SECRET_KEY" "$FAKE_LOG" || false
  ! grep -Fq "$SECRET_KEY" "$FAKE_SIGNER_LOG" || false
  ! grep -rFq "$SECRET_KEY" "$work/dir" || false
  # the signer was in fact run, with the key on stdin
  [ "$(cat "$FAKE_SIGNER_LOG")" = "-f - $work/dir/codex-build-$NEW.json" ]
  grep -q '^fakesig-' "$work/dir/codex-build-$NEW.json.sig"
}

@test "an unset key variable is refused before anything is changed" {
  stage "$NEW" ""
  run env -u SECRET_KEY sh "$build/channel-publish.sh" sign --repo R --tag T --dir "$work/dir" \
    --id "$NEW" --key-env SECRET_KEY --signer "$work/bin/fake-signer"
  [ "$status" -eq 1 ]
  [ ! -s "$FAKE_LOG" ]
}

@test "the delete loop never deletes the published id, even if the pruner names it" {
  # a scratch copy of build/ whose pruner names the published id as well as an old build
  cp -R "$build" "$work/build"
  printf '#!/bin/sh\ncat >/dev/null\necho 1.5.0-mavericks.4\necho 1.5.0-mavericks.1\n' > "$work/build/channel-prune.sh"
  for n in 1 2 3; do seed "1.5.0-mavericks.$n"; done
  stage 1.5.0-mavericks.4 ""
  sh "$work/build/channel-publish.sh" sign --repo Mavergreen/codex-cli --tag codex-builds --dir "$work/dir" \
    --id 1.5.0-mavericks.4 --key-env SECRET_KEY --signer "$work/bin/fake-signer"
  run sh "$work/build/channel-publish.sh" upload --repo Mavergreen/codex-cli --tag codex-builds --dir "$work/dir" \
    --id 1.5.0-mavericks.4
  [ "$status" -eq 0 ]
  grep -q 'delete-asset.*mavericks\.1[. ]' "$FAKE_LOG"
  ! grep -q 'delete-asset.*mavericks\.4[. ]' "$FAKE_LOG" || false
  grep -Fxq codex-build-1.5.0-mavericks.4.json "$FAKE_STATE"
}

@test "a release gh reports as not found is a first publish" {
  stage "$NEW" ""
  run publish "$NEW"
  [ "$status" -eq 0 ]
  grep -q '^release create' "$FAKE_LOG"
}

@test "any other failure to look up the release stops before signing or uploading" {
  seed 0.200.1-mavericks.4
  stage "$NEW" ""
  FAKE_VIEW_ERROR="HTTP 401: Bad credentials" run publish "$NEW"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot tell whether"* ]] || false
  ! grep -q -e '^release upload' -e '^release create' -e '^release delete' "$FAKE_LOG" || false
  [ ! -s "$FAKE_SIGNER_LOG" ]
}

@test "a failed delete is reported, says the build is live, and fails the run" {
  for n in 1 2 3 4 5 6 7 8 9 10 11 12; do seed "1.5.0-mavericks.$n"; done
  stage 1.5.0-mavericks.13 ""
  FAKE_FAIL_DELETE="codex-build-1.5.0-mavericks.1.json" run publish 1.5.0-mavericks.13
  [ "$status" -eq 1 ]
  [[ "$output" == *"could not delete codex-build-1.5.0-mavericks.1.json"* ]] || false
  [[ "$output" == *"published and live"* ]] || false
  # the other deletes were still tried
  grep -q 'delete-asset.*mavericks.3.tar.gz' "$FAKE_LOG"
}

@test "a signer failure leaves the channel untouched, even the release" {
  stage "$NEW" ""
  printf '#!/bin/sh\ncat >/dev/null\nexit 1\n' > "$work/bin/bad-signer"; chmod +x "$work/bin/bad-signer"
  run sh "$build/channel-publish.sh" sign --repo R --tag T --dir "$work/dir" --id "$NEW" --key-env SECRET_KEY --signer "$work/bin/bad-signer"
  [ "$status" -eq 1 ]
  ! grep -q -e '^release upload' -e '^release create' "$FAKE_LOG" || false
}

@test "a signer that prints two lines, or none, is refused" {
  stage "$NEW" ""
  printf '#!/bin/sh\ncat >/dev/null\nprintf "a\\nb\\n"\n' > "$work/bin/bad-signer"; chmod +x "$work/bin/bad-signer"
  run sh "$build/channel-publish.sh" sign --repo R --tag T --dir "$work/dir" --id "$NEW" --key-env SECRET_KEY --signer "$work/bin/bad-signer"
  [ "$status" -eq 1 ]
  [[ "$output" == *"more than one line"* ]] || false
  printf '#!/bin/sh\ncat >/dev/null\n' > "$work/bin/bad-signer"
  run sh "$build/channel-publish.sh" sign --repo R --tag T --dir "$work/dir" --id "$NEW" --key-env SECRET_KEY --signer "$work/bin/bad-signer"
  [ "$status" -eq 1 ]
  ! grep -q '^release upload' "$FAKE_LOG" || false
}

@test "a newer build already on the channel refuses a stale id before any upload" {
  seed 0.200.1-mavericks.4
  stage "$NEW" ""
  run publish "$NEW"
  [ "$status" -eq 1 ]
  [[ "$output" == *"0.200.1-mavericks.4 is already on the channel"* ]] || false
  ! grep -q -e '^release upload' -e '^release create' -e '^release delete' "$FAKE_LOG" || false
  [ ! -s "$FAKE_SIGNER_LOG" ]
}

@test "staleness is numeric: 0.10.0 is newer than 0.9.0" {
  seed 0.10.0-mavericks.1
  stage 0.9.0-mavericks.5 ""
  run publish 0.9.0-mavericks.5
  [ "$status" -eq 1 ]
}

@test "the same id is a retry and an older channel is no obstacle" {
  seed "$NEW"
  stage "$NEW" ""
  cp "$work/dir/codex-build-$NEW.json" "$FAKE_PUBLISHED/"
  run publish "$NEW"
  [ "$status" -eq 0 ]
  seed 0.200.1-mavericks.2 0.199.9-mavericks.9
  run publish "$NEW"
  [ "$status" -eq 0 ]
  grep -q '^release upload' "$FAKE_LOG"
}

@test "a staged JSON that does not match the id or its tarball is refused before anything is changed" {
  stage "$NEW" ""
  sed 's/rust-v0.200.1-mavericks.3/rust-v0.200.1-mavericks.9/' "$work/dir/codex-build-$NEW.json" > "$work/x"; cp "$work/x" "$work/dir/codex-build-$NEW.json"
  run publish "$NEW"
  [ "$status" -eq 1 ]
  stage "$NEW" ""
  printf 'changed after the JSON was made\n' > "$work/dir/codex-package-x86_64-apple-darwin-$NEW.tar.gz"
  run publish "$NEW"
  [ "$status" -eq 1 ]
  [[ "$output" == *"digest"* ]] || false
  stage "$NEW" ""
  sed 's/"mavergreen_build":"[^"]*"/"mavergreen_build":"0.200.1-mavericks.9"/' "$work/dir/codex-build-$NEW.json" > "$work/x"; cp "$work/x" "$work/dir/codex-build-$NEW.json"
  run publish "$NEW"
  [ "$status" -eq 1 ]
  [ ! -s "$FAKE_LOG" ]
}

@test "a failed tarball delete keeps that build's JSON for the next run" {
  for n in 1 2 3 4 5 6 7 8 9 10 11 12; do seed "1.5.0-mavericks.$n"; done
  stage 1.5.0-mavericks.13 ""
  FAKE_FAIL_DELETE="codex-package-x86_64-apple-darwin-1.5.0-mavericks.1.tar.gz" run publish 1.5.0-mavericks.13
  [ "$status" -eq 1 ]
  ! grep -q 'delete-asset.*codex-build-1.5.0-mavericks.1.json' "$FAKE_LOG" || false
}

@test "an identity with leading zeros is not a build" {
  stage "$NEW" ""
  run publish 0.200.01-mavericks.3
  [ "$status" -eq 1 ]
  printf '%s\n' 1.05.0-mavericks.1 1.5.0-mavericks.1 > "$work/h"
  sh "$build/channel-prune.sh" --keep-newest 0 --keep-minors 0 < "$work/h" > "$work/out" 2> "$work/err"
  grep -Fq "1.05.0-mavericks.1" "$work/err"
}

@test "assets are listed through the paginated assets endpoint" {
  stage "$NEW" ""
  run publish "$NEW"
  grep -Fq "api --paginate repos/Mavergreen/codex-cli/releases/42/assets?per_page=100" "$FAKE_LOG"
}

# ---- the two steps ----

@test "signing reads the channel, writes the signature and both copies, and changes nothing" {
  seed 0.200.1-mavericks.2
  stage "$NEW" ""
  run sign "$NEW"
  [ "$status" -eq 0 ]
  ! grep -q -e '^release upload' -e '^release create' -e '^release delete' "$FAKE_LOG" || false
  grep -q '^release view codex-builds' "$FAKE_LOG"
  [ "$(wc -l < "$FAKE_SIGNER_LOG" | tr -d ' ')" -eq 1 ]
  grep -q '^fakesig-' "$work/dir/codex-build-$NEW.json.sig"
  cmp "$work/dir/latest.json" "$work/dir/codex-build-$NEW.json"
  cmp "$work/dir/latest.json.sig" "$work/dir/codex-build-$NEW.json.sig"
}

@test "upload publishes a signed directory without the key or the signer" {
  stage "$NEW" ""
  sign "$NEW"
  : > "$FAKE_SIGNER_LOG"
  run upload "$NEW"
  [ "$status" -eq 0 ]
  [ ! -s "$FAKE_SIGNER_LOG" ]
  grep -Fxq "codex-build-$NEW.json.sig" "$FAKE_STATE"
  grep -Fxq latest.json.sig "$FAKE_STATE"
}

@test "upload refuses a key or a signer" {
  stage "$NEW" ""
  sign "$NEW"
  : > "$FAKE_LOG"
  run sh "$build/channel-publish.sh" upload --repo R --tag T --dir "$work/dir" --id "$NEW" --key-env SECRET_KEY
  [ "$status" -eq 2 ]
  [[ "$output" == *"upload takes no key"* ]] || false
  run sh "$build/channel-publish.sh" upload --repo R --tag T --dir "$work/dir" --id "$NEW" --signer "$work/bin/fake-signer"
  [ "$status" -eq 2 ]
  [ ! -s "$FAKE_LOG" ]
}

@test "upload refuses an unsigned or inconsistent directory before anything is changed" {
  stage "$NEW" ""
  run upload "$NEW"
  [ "$status" -eq 1 ]
  [[ "$output" == *"sign the directory first"* ]] || false
  [ ! -s "$FAKE_LOG" ]
  sign "$NEW"
  printf 'x\n' >> "$work/dir/latest.json.sig"
  run upload "$NEW"
  [ "$status" -eq 1 ]
  [[ "$output" == *"latest.json.sig is not a byte copy"* ]] || false
  sign "$NEW"
  printf '{}\n' > "$work/dir/latest.json"
  run upload "$NEW"
  [ "$status" -eq 1 ]
  [[ "$output" == *"latest.json is not a byte copy"* ]] || false
  sign "$NEW"
  printf 'a\nb\n' > "$work/dir/codex-build-$NEW.json.sig"; cp "$work/dir/codex-build-$NEW.json.sig" "$work/dir/latest.json.sig"
  run upload "$NEW"
  [ "$status" -eq 1 ]
  ! grep -q -e '^release upload' -e '^release create' -e '^release delete' "$FAKE_LOG" || false
}

@test "upload checks staleness again: a newer build that arrived after signing refuses it" {
  stage "$NEW" ""
  sign "$NEW"
  seed 0.200.1-mavericks.4
  run upload "$NEW"
  [ "$status" -eq 1 ]
  [[ "$output" == *"0.200.1-mavericks.4 is already on the channel"* ]] || false
  ! grep -q -e '^release upload' -e '^release create' -e '^release delete' "$FAKE_LOG" || false
}

@test "upload checks the package requirement again" {
  stage "$NEW" 20261017.5
  FAKE_LATEST_TAG=v20261017.5 sign "$NEW"
  FAKE_LATEST_TAG=v20261017.4 run upload "$NEW"
  [ "$status" -eq 1 ]
  [[ "$output" == *"release the package first"* ]] || false
  ! grep -q '^release upload' "$FAKE_LOG" || false
}

@test "a missing or unknown step is refused" {
  stage "$NEW" ""
  run sh "$build/channel-publish.sh" --repo R --tag T --dir "$work/dir" --id "$NEW" --key-env SECRET_KEY --signer "$work/bin/fake-signer"
  [ "$status" -eq 2 ]
  run sh "$build/channel-publish.sh" publish --repo R --tag T --dir "$work/dir" --id "$NEW"
  [ "$status" -eq 2 ]
  [ ! -s "$FAKE_LOG" ]
}

# ---- two runs, one build number ----

@test "a byte-identical retry of an id already on the channel is allowed" {
  stage "$NEW" ""
  publish "$NEW"
  : > "$FAKE_LOG"
  run publish "$NEW"
  [ "$status" -eq 0 ]
  # fetched exactly, by the id the paginated listing gave it
  id=$(printf '%s' "codex-build-$NEW.json" | cksum | cut -d' ' -f1)
  grep -Fq "api -H Accept: application/octet-stream repos/Mavergreen/codex-cli/releases/assets/$id" "$FAKE_LOG"
  grep -q '^release upload' "$FAKE_LOG"
}

@test "an id already on the channel as a different build is refused, before signing and uploading" {
  seed "$NEW"
  stage "$NEW" ""
  run sign "$NEW"
  [ "$status" -eq 1 ]
  [[ "$output" == *"$NEW is already on the channel as a different build"* ]] || false
  [ ! -s "$FAKE_SIGNER_LOG" ]
  # the other run published while this one was signing: upload refuses too
  : > "$FAKE_STATE"; rm -f "$FAKE_PUBLISHED"/*
  sign "$NEW"
  seed "$NEW"
  run upload "$NEW"
  [ "$status" -eq 1 ]
  [[ "$output" == *"another run published this build number first"* ]] || false
  ! grep -q -e '^release upload' -e '^release create' -e '^release delete' "$FAKE_LOG" || false
}

@test "an id on the channel whose JSON cannot be fetched is refused" {
  seed "$NEW"
  rm "$FAKE_PUBLISHED/codex-build-$NEW.json"
  stage "$NEW" ""
  run sign "$NEW"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot be fetched to compare"* ]] || false
}

# ---- signatures, verified on upload ----

# have_ed25519_openssl: openssl on PATH can make and check Ed25519 signatures (OpenSSL 3; 10.9's
# own /usr/bin/openssl is 0.9.8 and cannot)
have_ed25519_openssl() {
  openssl genpkey -algorithm ed25519 -out "$work/probe.pem" > /dev/null 2>&1
}

# real_sign ID: sign the staged JSON with a fresh Ed25519 key, as the family signer would, leaving
# the raw base64 public key in $work/key.pub
real_sign() {
  openssl genpkey -algorithm ed25519 -out "$work/key.pem"
  openssl pkey -in "$work/key.pem" -pubout -outform DER | tail -c 32 | openssl base64 -A > "$work/key.pub"
  openssl pkeyutl -sign -inkey "$work/key.pem" -rawin -in "$work/dir/codex-build-$1.json" |
    openssl base64 -A > "$work/dir/codex-build-$1.json.sig"
  printf '\n' >> "$work/dir/codex-build-$1.json.sig"
  cp "$work/dir/codex-build-$1.json" "$work/dir/latest.json"
  cp "$work/dir/codex-build-$1.json.sig" "$work/dir/latest.json.sig"
}

verified_upload() {
  env -u SECRET_KEY sh "$build/channel-publish.sh" upload --repo Mavergreen/codex-cli --tag codex-builds \
    --dir "$work/dir" --id "$1" --verify-with "$work/key.pub"
}

@test "upload with --verify-with publishes a genuine signature, checked with OpenSSL" {
  have_ed25519_openssl || skip "no OpenSSL 3 with Ed25519 on PATH"
  stage "$NEW" ""
  real_sign "$NEW"
  run verified_upload "$NEW"
  [ "$status" -eq 0 ]
  grep -Fxq latest.json.sig "$FAKE_STATE"
}

@test "upload with --verify-with refuses a signature by another key, or over other bytes, before any change" {
  have_ed25519_openssl || skip "no OpenSSL 3 with Ed25519 on PATH"
  stage "$NEW" ""
  real_sign "$NEW"
  cp "$work/key.pub" "$work/right.pub"
  # another key's signature
  real_sign "$NEW"
  cp "$work/right.pub" "$work/key.pub"
  run verified_upload "$NEW"
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not verify against"* ]] || false
  # the right key, but a signature over other bytes
  real_sign "$NEW"
  printf '{"other":"bytes"}\n' > "$work/other.json"
  openssl pkeyutl -sign -inkey "$work/key.pem" -rawin -in "$work/other.json" | openssl base64 -A > "$work/dir/codex-build-$NEW.json.sig"
  printf '\n' >> "$work/dir/codex-build-$NEW.json.sig"
  cp "$work/dir/codex-build-$NEW.json.sig" "$work/dir/latest.json.sig"
  run verified_upload "$NEW"
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not verify against"* ]] || false
  # a public key that is not 32 raw bytes
  printf 'c2hvcnQ=\n' > "$work/key.pub"
  run verified_upload "$NEW"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a base64 raw Ed25519 public key"* ]] || false
  [ ! -s "$FAKE_LOG" ]
}

@test "the fake signer's output never passes --verify-with" {
  have_ed25519_openssl || skip "no OpenSSL 3 with Ed25519 on PATH"
  stage "$NEW" ""
  real_sign "$NEW"
  sign "$NEW"
  : > "$FAKE_LOG"
  run verified_upload "$NEW"
  [ "$status" -eq 1 ]
  ! grep -q '^release upload' "$FAKE_LOG" || false
}

@test "--verify-with belongs to upload, not sign" {
  stage "$NEW" ""
  : > "$work/key.pub"
  run sh "$build/channel-publish.sh" sign --repo R --tag T --dir "$work/dir" --id "$NEW" \
    --key-env SECRET_KEY --signer "$work/bin/fake-signer" --verify-with "$work/key.pub"
  [ "$status" -eq 2 ]
}

# ---- the lister ----

@test "the lister prints names, or ids and names, from the paginated endpoint" {
  seed "$NEW"
  run sh "$build/channel-assets.sh" Mavergreen/codex-cli codex-builds
  [ "$status" -eq 0 ]
  [ "$output" = "$(cat "$FAKE_STATE")" ]
  run sh "$build/channel-assets.sh" --ids Mavergreen/codex-cli codex-builds
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | sed -n 2p)" = "$(printf '%s' "codex-build-$NEW.json" | cksum | cut -d' ' -f1) codex-build-$NEW.json" ]
  run sh "$build/channel-assets.sh" --ids Mavergreen/codex-cli
  [ "$status" -eq 2 ]
}

# ---- latest.json after a race ----

# race_build ID [nosig]: a build another run publishes between this run's staleness check and its
# replace of latest.json (the fake gh adds it then)
race_build() {
  r="$work/race"
  mkdir -p "$r"
  printf 'tarball of %s\n' "$1" > "$r/codex-package-x86_64-apple-darwin-$1.tar.gz"
  sh "$build/channel-json.sh" --id "$1" --codex-version "${1%%-*}" \
    --tarball "$r/codex-package-x86_64-apple-darwin-$1.tar.gz" --min-pkg "" --state "$(state_hex)" > "$r/codex-build-$1.json"
  cp "$r/codex-build-$1.json" "$r/latest.json"
  if [ "${2:-}" != nosig ]; then
    echo "fakesig-race-$1" > "$r/codex-build-$1.json.sig"
    cp "$r/codex-build-$1.json.sig" "$r/latest.json.sig"
  fi
  export FAKE_RACE_DIR="$r"
}

@test "a newer build published during this upload gets latest.json back" {
  stage "$NEW" ""
  race_build 0.200.1-mavericks.4
  run publish "$NEW"
  [ "$status" -eq 0 ]
  [[ "$output" == *"0.200.1-mavericks.4 reached the channel while $NEW was published"* ]] || false
  cmp "$FAKE_PUBLISHED/latest.json" "$work/race/codex-build-0.200.1-mavericks.4.json"
  cmp "$FAKE_PUBLISHED/latest.json.sig" "$work/race/codex-build-0.200.1-mavericks.4.json.sig"
  # this run's build is still there; the newer one's assets were fetched by id
  grep -Fxq "codex-build-$NEW.json" "$FAKE_STATE"
  grep -q "releases/assets/$(printf '%s' codex-build-0.200.1-mavericks.4.json | cksum | cut -d' ' -f1)\$" "$FAKE_LOG"
}

@test "without a race latest.json stays this build's, and nothing is uploaded twice" {
  stage "$NEW" ""
  run publish "$NEW"
  [ "$status" -eq 0 ]
  cmp "$FAKE_PUBLISHED/latest.json" "$work/dir/codex-build-$NEW.json"
  [ "$(grep -c '^release upload' "$FAKE_LOG")" -eq 2 ]
}

@test "a newer build whose signature never arrives fails the run after a few attempts, saying so" {
  stage "$NEW" ""
  race_build 0.200.1-mavericks.4 nosig
  run publish "$NEW"
  [ "$status" -eq 1 ]
  [[ "$output" == *"latest.json names $NEW while 0.200.1-mavericks.4 is the channel's newest build"* ]] || false
  [ "$(printf '%s\n' "$output" | grep -c 'trying again')" -eq 5 ]
  # pruning never ran on an unsettled channel
  ! grep -q '^release delete-asset' "$FAKE_LOG" || false
}

@test "with --verify-with, the newer build's signature is checked before latest.json is pointed at it" {
  have_ed25519_openssl || skip "no OpenSSL 3 with Ed25519 on PATH"
  stage "$NEW" ""
  real_sign "$NEW"
  cp "$work/key.pem" "$work/right.pem"; cp "$work/key.pub" "$work/right.pub"
  # the racing build is signed by another key: refused, and latest.json is not pointed at it
  race_build 0.200.1-mavericks.4
  openssl genpkey -algorithm ed25519 -out "$work/other.pem"
  openssl pkeyutl -sign -inkey "$work/other.pem" -rawin -in "$work/race/codex-build-0.200.1-mavericks.4.json" |
    openssl base64 -A > "$work/race/codex-build-0.200.1-mavericks.4.json.sig"
  printf '\n' >> "$work/race/codex-build-0.200.1-mavericks.4.json.sig"
  run verified_upload "$NEW"
  [ "$status" -eq 1 ]
  [[ "$output" == *"latest.json.sig does not verify against"* ]] || false
  cmp "$FAKE_PUBLISHED/latest.json" "$work/dir/codex-build-$NEW.json"
  # signed by the right key: latest.json follows it
  : > "$FAKE_STATE"; rm -f "$FAKE_EXISTS" "$FAKE_PUBLISHED"/* "$work/race.done"
  openssl pkeyutl -sign -inkey "$work/right.pem" -rawin -in "$work/race/codex-build-0.200.1-mavericks.4.json" |
    openssl base64 -A > "$work/race/codex-build-0.200.1-mavericks.4.json.sig"
  printf '\n' >> "$work/race/codex-build-0.200.1-mavericks.4.json.sig"
  run verified_upload "$NEW"
  [ "$status" -eq 0 ]
  cmp "$FAKE_PUBLISHED/latest.json" "$work/race/codex-build-0.200.1-mavericks.4.json"
}
