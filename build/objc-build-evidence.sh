#!/bin/sh
# platform: macOS-only -- shipyard's Objective-C helpers build against the host SDK; perl's core JSON::PP merges evidence
#   usage: objc-build-evidence.sh native|cross
#          objc-build-evidence.sh --check native|cross
#          Binds shipyard's Objective-C proof to the exact bytes build-codex.sh MODE left in
#          BUILD_ROOT/codex-MODE, and writes it under BUILD_ROOT/objc-MODE/ (beside linkmaps/codex.map,
#          which the link wrote), never into the artifact directory or the package:
#            evidence/codex.generated.json  scripts/objc-build-evidence.sh's evidence for codex: its final
#                                           and prestrip bytes (strip = false: they are one file), the link
#                                           map, the reference set, the prepared source tree and where the
#                                           provider's archive members landed
#            evidence/codex.json            that evidence plus the source identity (pinned revision, the
#                                           patch series' SHA-256, the cargo command) and the reviewed
#                                           sections of objc/HOST/codex-reviewed-evidence.json (crates, type map,
#                                           R2 and R3 evidence, binding receipt, guards), when that file exists
#            evidence/codex-code-mode-host{.generated,}.json
#                                           the same for the code-mode host, which links no provider (no link
#                                           map, no mapping), with objc/HOST/codex-code-mode-host-reviewed-evidence.json
#            reports/codex.objc-compat.json, reports/codex-code-mode-host.objc-compat.json
#                                           scripts/objc-compat.sh --mode strict for each binary on its own
#                                           evidence; codex with the provider it linked and its receipt
#            reports/codex.status, reports/codex-code-mode-host.status
#                                           each strict run's exit, which build/objc-publication-check.sh
#                                           requires to be 0 before anything is packaged or signed
#            identity                       SHA-256 of every input and output above, the manifest and the
#                                           provider's archive and declaration
#          HOST is build/objc-reviewed-dir.sh's answer for this build host: rows bind its symbols.
#          Nothing here classifies an API: every verdict is shipyard's. Every run starts from an empty
#          evidence/ and reports/ (shipyard never replaces a report), so nothing stale survives it.
#          --check rehashes everything identity names and fails if any byte moved since: run it
#          immediately before the proof is used (build/compat-guard.sh does).
#          The provider is re-resolved by build/fetch-recaulk-objc.sh and must be the one the manifest
#          recorded. A guard record is effective only once reviewed (review status, reviewer, reason):
#          nothing here reviews one.
#          Exit 0 both binaries strict-clean (or --check: unchanged), 1 a blocking finding or a moved
#          byte, 2 usage, 4 cannot measure or a missing input.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MAVERICKS_BUILD_DIR=$HERE
export MAVERICKS_BUILD_DIR
. "$HERE/lib.sh"

usage() { echo "usage: objc-build-evidence.sh [--check] native|cross" >&2; exit 2; }
CHECK=no
[ "${1:-}" != --check ] || { CHECK=yes; shift; }
[ $# -eq 1 ] || usage
MODE=$1
case "$MODE" in native|cross) ;; *) usage ;; esac
fail() { echo "objc-build-evidence: $*" >&2; exit 4; }
sha() { shasum -a 256 "$1" | cut -c1-64; }

BUILD_ROOT=$(mavericks_build_root)
ART="$BUILD_ROOT/codex-$MODE"
OBJC="$BUILD_ROOT/objc-$MODE"
SOURCE="$BUILD_ROOT/codex-src"
MAP="$OBJC/linkmaps/codex.map"
REFS=$(CDPATH= cd -- "$SHIPYARD_SCRIPTS/../reference/objc" 2>/dev/null && pwd) || fail "shipyard at $SHIPYARD_SCRIPTS has no reference/objc"
# spec: build/objc-reviewed-dir.sh -- the rows for binaries built on this host
RDIR=$(sh "$HERE/objc-reviewed-dir.sh") || fail "no reviewed rows for a build on this host"
REVIEWED="$RDIR/codex-reviewed-evidence.json"
REVIEWED_HOST="$RDIR/codex-code-mode-host-reviewed-evidence.json"

if [ "$CHECK" = yes ]; then
  [ -f "$OBJC/identity" ] || { echo "objc-build-evidence: no $OBJC/identity: run objc-build-evidence.sh $MODE" >&2; exit 1; }
  moved=0
  while read -r want path; do
    if [ ! -f "$path" ]; then echo "objc-build-evidence: $path is gone" >&2; moved=1
    elif [ "$(sha "$path")" != "$want" ]; then echo "objc-build-evidence: $path changed since its proof" >&2; moved=1
    fi
  done < "$OBJC/identity"
  # a reviewed-evidence file added since the proof was written is a change too
  for r in "$REVIEWED" "$REVIEWED_HOST"; do
    [ ! -f "$r" ] || grep -q " $r\$" "$OBJC/identity" || { echo "objc-build-evidence: $r is newer than the proof" >&2; moved=1; }
  done
  [ "$moved" = 0 ] || exit 1
  echo "objc-build-evidence: the $MODE proof still describes these bytes" >&2
  exit 0
fi

for f in "$ART/codex" "$ART/codex-code-mode-host" "$ART/build-manifest" "$MAP"; do
  [ -f "$f" ] || fail "no $f: run build/build-codex.sh $MODE"
done
[ -d "$SOURCE/codex-rs" ] || fail "no prepared source at $SOURCE"
# platform: a link map from another link is shipyard's to refuse: it checks the map lists exactly the
#           prestrip image's sections and that every provider atom sits where the map says.
field() { sed -n "s/^$1=//p" "$ART/build-manifest"; }

provider=$(sh "$HERE/fetch-recaulk-objc.sh") || fail "no verified Recaulk provider"
PREFIX=$(printf '%s\n' "$provider" | sed -n 1p)
DECL="$PREFIX/share/recaulk/objc-providers.json"
ARCHIVE="$PREFIX/$(plutil -extract build.archive_path xml1 -o - "$DECL" | sed -n 's:^<string>\(.*\)</string>$:\1:p')"
[ "$(sha "$ARCHIVE")" = "$(field recaulk_archive_sha256)" ] && [ "$(sha "$DECL")" = "$(field recaulk_declaration_sha256)" ] ||
  fail "the provider at $PREFIX is not the one $ART/build-manifest says codex linked"
# The provider body's source receipt, which Recaulk ships beside its declaration: shipyard closes the
# body's own sends only through it. A prefix without one leaves them open.
RECEIPT="$PREFIX/share/recaulk/objc-source.receipt"
[ -f "$RECEIPT" ] || RECEIPT=

rm -rf "$OBJC/evidence" "$OBJC/reports" "$OBJC/identity"
mkdir -p "$OBJC/evidence" "$OBJC/reports"
GEN="$OBJC/evidence/codex.generated.json"
EV="$OBJC/evidence/codex.json"
GENH="$OBJC/evidence/codex-code-mode-host.generated.json"
EVH="$OBJC/evidence/codex-code-mode-host.json"
sh "$SHIPYARD_SCRIPTS/objc-build-evidence.sh" --artifact "$ART/codex" --prestrip "$ART/codex" --source-root "$SOURCE" \
  --link-map "$MAP" --provider-prefix "$PREFIX" --references "$REFS" --output "$GEN" || fail "shipyard wrote no build evidence"
# the code-mode host links no provider: no link map and nothing to map
sh "$SHIPYARD_SCRIPTS/objc-build-evidence.sh" --artifact "$ART/codex-code-mode-host" --prestrip "$ART/codex-code-mode-host" \
  --source-root "$SOURCE" --references "$REFS" --output "$GENH" || fail "shipyard wrote no build evidence for codex-code-mode-host"

REVISION=$(sh "$HERE/codex-pin.sh" revision)
PATCHES=$(cat "$MAVERICKS_ROOT/patches"/*.patch | shasum -a 256 | cut -c1-64)
# spec: build/build-codex.sh -- the cargo command both binaries come from.
FEATURES='cargo build --locked --release --target x86_64-apple-darwin -p codex-cli -p codex-code-mode-host'
[ -f "$REVIEWED" ] || REVIEWED=
[ -f "$REVIEWED_HOST" ] || REVIEWED_HOST=
# merge GENERATED REVIEWED OUT: the generated evidence, the source identity and the reviewed sections
merge() {
perl -MJSON::PP -e '
  my ($gen, $reviewed, $rev, $patches, $features, $out) = @ARGV;
  sub slurp { local $/; open my $f, "<", $_[0] or die "$_[0]: $!\n"; my $s = <$f>; JSON::PP->new->decode($s) }
  my $e = slurp($gen);
  $e->{source}{revision} = $rev; $e->{source}{patches_sha256} = $patches; $e->{source}{features} = $features;
  if ($reviewed ne "") {
    my $r = slurp($reviewed);
    for my $k (keys %$r) {
      die "$reviewed: unknown section $k\n" unless $k =~ /^(crates|type_map|type_evidence|position_evidence|binding_receipt|guards|notes)$/;
      next if $k eq "notes";
      $e->{$k} = $r->{$k};
    }
  }
  open my $o, ">", $out or die "$out: $!\n";
  print $o JSON::PP->new->canonical->pretty->encode($e);
  close $o or die "$out: $!\n";
' "$1" "$2" "$REVISION" "$PATCHES" "$FEATURES" "$3"
}
merge "$GEN" "$REVIEWED" "$EV" || fail "could not merge the build evidence"
merge "$GENH" "$REVIEWED_HOST" "$EVH" || fail "could not merge the code-mode host's build evidence"

# spec: shipyard scripts/objc-compat.sh -- each report names its binary relative to a shipped root.
status=0
for name in codex codex-code-mode-host; do
  set -- --artifact "$ART/$name" --root "$ART" --references "$REFS" --report "$OBJC/reports/$name.objc-compat.json" --mode strict
  if [ "$name" = codex ]; then set -- "$@" --build-evidence "$EV" --provider-prefix "$PREFIX"
  else set -- "$@" --build-evidence "$EVH"; fi
  [ "$name" != codex ] || [ -z "$RECEIPT" ] || set -- "$@" --source-receipt "$RECEIPT"
  rc=0
  sh "$SHIPYARD_SCRIPTS/objc-compat.sh" "$@" 2> "$OBJC/reports/$name.stderr" || rc=$?
  case "$rc" in
    0) echo "objc-build-evidence: $name: strict clean" >&2 ;;
    1) echo "objc-build-evidence: $name: strict blocking findings (reports/$name.objc-compat.json)" >&2; [ "$status" = 4 ] || status=1 ;;
    *) echo "objc-build-evidence: $name: cannot measure (exit $rc): $(tail -2 "$OBJC/reports/$name.stderr")" >&2; status=4 ;;
  esac
  # spec: build/objc-publication-check.sh -- the run's exit, which publication requires to be 0
  printf '%s\n' "$rc" > "$OBJC/reports/$name.status"
done

for f in "$ART/codex" "$ART/codex-code-mode-host" "$ART/build-manifest" "$MAP" "$ARCHIVE" "$DECL" "$GEN" "$EV" "$GENH" "$EVH" \
         "$OBJC/reports/codex.objc-compat.json" "$OBJC/reports/codex-code-mode-host.objc-compat.json" \
         "$OBJC/reports/codex.status" "$OBJC/reports/codex-code-mode-host.status" \
         ${REVIEWED:+"$REVIEWED"} ${REVIEWED_HOST:+"$REVIEWED_HOST"} ${RECEIPT:+"$RECEIPT"}; do
  [ ! -f "$f" ] || printf '%s %s\n' "$(sha "$f")" "$f"
done > "$OBJC/identity.tmp"
# written whole or not at all: build/objc-publication-check.sh requires every line
mv "$OBJC/identity.tmp" "$OBJC/identity"
exit "$status"
