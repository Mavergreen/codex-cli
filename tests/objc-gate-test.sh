#!/bin/sh
# platform: macOS-only -- shipyard's strict Objective-C analyzer builds against the host SDK and reads real Codex binaries as bytes
# spec: build/compat-guard.sh and build/objc-build-evidence.sh headers -- the gate a Codex binary must
#       pass. Nothing here runs a Codex binary; each is read as bytes.
#   Inputs, each optional; with neither the test is skipped (exit 77):
#     MAVERICKS_OBJC_CODEX_ARTIFACT  the original Codex 0.165.0 binary (SHA-256 1d056b0d...6c40), whose
#                                    `codex login` crashed on 10.9. It must fail the gate for its
#                                    unguarded -[NSWorkspace openURLs:...] send; its two accessibility
#                                    sends must stay unresolved until their guard records are reviewed,
#                                    and its three unknown-class sends unresolved.
#     CODEX_GATE_MODE                native or cross: a build in the build root, with the proof
#                                    build/objc-build-evidence.sh MODE wrote. Its openURLs send must be
#                                    provided; the gate passes only when every one of the six sends the
#                                    original left open is closed; and each mutation below must take away
#                                    exactly the proof it touches.
#     CODEX_TEST_RECAULK_PREFIX      the provider prefix the build linked (else build/fetch-recaulk-objc.sh's)
#   Prints a line per send of the six for the rebuilt binary, and BLOCKED with the open ones when the
#   gate refuses it: that is the gate working, not a test failure.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/.." && pwd)
: "${SHIPYARD_SCRIPTS:?set SHIPYARD_SCRIPTS}"
ORIGINAL_SHA=1d056b0d4ada3d74b4c0f4c5450bc06856bfdbc504320fa430a4249f640f6c40
SEL_OPEN='openURLs:withApplicationAtURL:options:configuration:error:'
if [ -z "${MAVERICKS_OBJC_CODEX_ARTIFACT:-}" ] && [ -z "${CODEX_GATE_MODE:-}" ]; then
  echo "SKIP: objc-gate-test: neither MAVERICKS_OBJC_CODEX_ARTIFACT nor CODEX_GATE_MODE names a binary"; exit 77
fi
T=$(mktemp -d "${TMPDIR:-/tmp}/objc-gate-test.XXXXXX")
trap 'rm -rf "$T"' EXIT
fails=0
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }
sha() { shasum -a 256 "$1" | cut -c1-64; }
n=0
# guard BINARY [ENV...]: build/compat-guard.sh on BINARY; sets $rc, and $report (its kept report).
guard() {
  bin=$1; shift
  n=$((n + 1)); mkdir -p "$T/r$n"
  rc=0
  env "$@" CODEX_OBJC_REPORT_DIR="$T/r$n" sh "$ROOT/build/compat-guard.sh" "$bin" > "$T/r$n.log" 2>&1 || rc=$?
  report=$(ls "$T/r$n"/*.objc-compat.json 2>/dev/null | head -1)
}
# verdicts REPORT SELECTOR [FUNCTION-SUBSTRING]: the sorted verdicts of the findings for SELECTOR.
verdicts() {
  [ -n "$1" ] && [ -f "$1" ] || { echo none; return; }
  perl -MJSON::PP -e '
    my ($f, $sel, $fn) = @ARGV; local $/; open my $h, "<", $f or die; my $r = JSON::PP->new->decode(<$h>);
    my @v = sort map { $_->{verdict} } grep { $_->{selector} eq $sel && (!length($fn) || index($_->{function} // "", $fn) >= 0) } @{$r->{findings}};
    print @v ? join(",", @v) : "absent";' "$1" "$2" "${3:-}"
}
codes() { if [ -n "$1" ] && [ -f "$1" ]; then perl -MJSON::PP -e 'local $/; open my $h, "<", $ARGV[0]; my $r = JSON::PP->new->decode(<$h>); print join(",", map { $_->{code} } @{$r->{errors} || []})' "$1"; else echo none; fi; }
counts() { perl -MJSON::PP -e 'local $/; open my $h, "<", $ARGV[0]; my $r = JSON::PP->new->decode(<$h>); my %c; $c{$_->{verdict}}++ for @{$r->{findings}}; print join(" ", map { "$_=$c{$_}" } sort keys %c)' "$1"; }

# ---- the original binary ----
if [ -n "${MAVERICKS_OBJC_CODEX_ARTIFACT:-}" ]; then
  if [ "$(sha "$MAVERICKS_OBJC_CODEX_ARTIFACT")" != "$ORIGINAL_SHA" ]; then
    fail "MAVERICKS_OBJC_CODEX_ARTIFACT is not the original Codex 0.165.0 ($ORIGINAL_SHA)"
  else
    mkdir -p "$T/orig/codex"
    ln "$MAVERICKS_OBJC_CODEX_ARTIFACT" "$T/orig/codex/codex" 2>/dev/null || cp "$MAVERICKS_OBJC_CODEX_ARTIFACT" "$T/orig/codex/codex"
    # The build evidence shipyard recorded for this very binary: binding receipt, R2 rows, and the two
    # guard records, unreviewed.
    FXEV="$SHIPYARD_SCRIPTS/../tests/fixtures/objc-api/codex-0.165.0-build-evidence.json"
    guard "$T/orig/codex/codex" CODEX_OBJC_BUILD_EVIDENCE="$FXEV"
    [ "$rc" = 1 ] && pass "the gate refuses the original Codex 0.165.0 (exit 1)" || fail "the gate gave the original exit $rc, not 1: $(tail -3 "$T/r$n.log")"
    [ "$(verdicts "$report" "$SEL_OPEN")" = unsupported ] && pass "its -[NSWorkspace openURLs:...] send is unsupported" ||
      fail "its openURLs send is $(verdicts "$report" "$SEL_OPEN"), not unsupported"
    for s in accessibilityDisplayShouldReduceMotion isVoiceOverEnabled; do
      v=$(verdicts "$report" "$s")
      [ "$v" = unresolved ] && grep -q "$s.*guard record is not reviewed" "$T/r$n.log" &&
        pass "-[NSWorkspace $s] needs its reviewed guard record (a measured guard alone: unresolved)" ||
        fail "-[NSWorkspace $s] is $v without a reviewed guard record"
    done
    for pair in "countByEnumeratingWithState:objects:count:|FilterMap" "UTF8String|ProtocolObject" "lengthOfBytesUsingEncoding:|ProtocolObject"; do
      v=$(verdicts "$report" "${pair%%|*}" "${pair#*|}")
      [ "$v" = unresolved ] && pass "${pair%%|*} in *${pair#*|}*: no accepted evidence closes its receiver (unresolved)" ||
        fail "${pair%%|*} in *${pair#*|}* is $v"
    done
    # Without any build evidence the binary alone decides: still refused, for the same send.
    guard "$T/orig/codex/codex"
    case "$rc:$(verdicts "$report" "$SEL_OPEN")" in
      1:unsupported|1:unresolved) pass "with no build evidence the original is still refused, openURLs $(verdicts "$report" "$SEL_OPEN")" ;;
      *) fail "with no evidence: exit $rc, openURLs $(verdicts "$report" "$SEL_OPEN")" ;;
    esac
    rm -f "$T/orig/codex/codex"
  fi
fi

# ---- the rebuilt binary ----
if [ -n "${CODEX_GATE_MODE:-}" ]; then
  MODE=$CODEX_GATE_MODE
  BR=$(CDPATH= cd -- "$(sh "$ROOT/build/resolve-build-root.sh")" && pwd -P)
  ART="$BR/codex-$MODE"; OBJC="$BR/objc-$MODE"
  EV="$OBJC/evidence/codex.json"
  PFX=${CODEX_TEST_RECAULK_PREFIX:-$(sh "$ROOT/build/fetch-recaulk-objc.sh" 2>/dev/null | sed -n 1p)}
  guard "$ART/codex"
  rebuilt=$report rebuilt_rc=$rc
  if [ -z "$rebuilt" ]; then
    fail "the gate wrote no report for the rebuilt codex (exit $rc): $(tail -3 "$T/r$n.log")"
  else
    echo "rebuilt codex: gate exit $rebuilt_rc, $(counts "$rebuilt")"
    [ "$(verdicts "$rebuilt" "$SEL_OPEN")" = provided ] && pass "the rebuilt codex's openURLs send is provided by Recaulk" ||
      fail "the rebuilt codex's openURLs send is $(verdicts "$rebuilt" "$SEL_OPEN")"
    # The six sends the original left open (the openURLs defect and five unresolved). A positive verdict
    # needs every one closed: provided, guarded or floor-supported.
    open=
    for six in "$SEL_OPEN|" "accessibilityDisplayShouldReduceMotion|" "isVoiceOverEnabled|" \
               "countByEnumeratingWithState:objects:count:|FilterMap" "UTF8String|ProtocolObject" "lengthOfBytesUsingEncoding:|ProtocolObject"; do
      s=${six%%|*}; fn=${six#*|}
      v=$(verdicts "$rebuilt" "$s" "$fn")
      echo "  $s${fn:+ in *$fn*}: $v"
      case ",$v," in *,unresolved,*|*,unsupported,*|,none,) open="$open $s" ;; esac
    done
    # The provider body's own sends close through Recaulk's source receipt (share/recaulk/objc-source.receipt).
    body=$(perl -MJSON::PP -e 'local $/; open my $h, "<", $ARGV[0]; my $r = JSON::PP->new->decode(<$h>); print scalar grep { $_->{verdict} =~ /^(unresolved|unsupported)$/ && ($_->{function} // "") =~ /^_+recaulk_/ } @{$r->{findings}}' "$rebuilt")
    if [ -f "$PFX/share/recaulk/objc-source.receipt" ]; then
      [ "$body" = 0 ] && pass "the provider body's own sends close through its source receipt" ||
        fail "$body of the provider body's own sends stay open with its source receipt"
    else
      fail "the provider at $PFX carries no share/recaulk/objc-source.receipt"
    fi
    blocking=$(perl -MJSON::PP -e 'local $/; open my $h, "<", $ARGV[0]; my $r = JSON::PP->new->decode(<$h>); print scalar grep { $_->{verdict} =~ /^(unresolved|unsupported)$/ && !$_->{exception} } @{$r->{findings}}' "$rebuilt")
    # R3 rows (objc/codex-reviewed-evidence.json position_evidence) close the last three: the gate passes.
    [ "$rebuilt_rc" = 0 ] && [ -z "$open" ] && [ "$blocking" = 0 ] && pass "the gate passes the rebuilt codex with all six closed" ||
      fail "the gate gave the rebuilt codex exit $rebuilt_rc, open:$open ($blocking blocking findings)"
  fi
  guard "$ART/codex-code-mode-host"
  if [ -n "$report" ]; then
    echo "rebuilt codex-code-mode-host: gate exit $rc, $(counts "$report")"
    [ "$(verdicts "$report" "$SEL_OPEN")" = absent ] && pass "codex-code-mode-host has no openURLs send" ||
      fail "codex-code-mode-host has openURLs: $(verdicts "$report" "$SEL_OPEN")"
    # Its own build evidence (R2 rows for objc2's NSString, NSError and NSDictionary helpers, R3 for os_info)
    # closes every send it makes.
    hopen=$(perl -MJSON::PP -e 'local $/; open my $h, "<", $ARGV[0]; my $r = JSON::PP->new->decode(<$h>); print scalar grep { $_->{verdict} =~ /^(unresolved|unsupported)$/ } @{$r->{findings}}' "$report")
    [ "$rc" = 0 ] && [ "$hopen" = 0 ] && pass "the gate passes codex-code-mode-host on its own build evidence" ||
      fail "codex-code-mode-host: gate exit $rc, $hopen sends open"
  else fail "no report for codex-code-mode-host (exit $rc): $(tail -3 "$T/r$n.log")"; fi

  # -- mutations of the rebuilt binary's proof: each takes away what it touches --
  mkdir -p "$T/m/codex"
  cp "$ART/codex" "$T/m/codex/codex"
  mut() { perl -MJSON::PP -e 'my ($in, $out, $code) = @ARGV; local $/; open my $h, "<", $in or die; my $e = JSON::PP->new->decode(<$h>); eval $code; die $@ if $@; open my $o, ">", $out or die; print $o JSON::PP->new->canonical->encode($e)' "$EV" "$1" "$2"; }

  # R3 rows bind to what they say: a row for another function closes nothing (codex's receivers are not modelled,
  # so a row's stated position stands on its citation; shipyard's fixtures test the check where they are), and a
  # changed arboard revision is refused.
  mut "$T/r3-other.json" 'for (@{$e->{position_evidence}}) { $_->{symbol} =~ s/protocol_object/protocol_objekt/ }'
  guard "$T/m/codex/codex" CODEX_OBJC_BUILD_EVIDENCE="$T/r3-other.json" CODEX_OBJC_PROVIDER_PREFIX="$PFX"
  [ "$rc" != 0 ] && [ "$(verdicts "$report" UTF8String ProtocolObject)" != floor-supported ] &&
    pass "an R3 row for another function leaves ProtocolObject's sends open (exit $rc)" || fail "R3 row for another symbol: exit $rc"
  mut "$T/r3-arboard.json" 'for (@{$e->{crates}}) { $_->{disambiguator} = "aaaaaaaaaa" if $_->{name} eq "arboard" }'
  guard "$T/m/codex/codex" CODEX_OBJC_BUILD_EVIDENCE="$T/r3-arboard.json" CODEX_OBJC_PROVIDER_PREFIX="$PFX"
  [ "$rc" = 4 ] && pass "R3 evidence pinning another arboard revision is refused (exit 4: $(codes "$report"))" || fail "another arboard revision: exit $rc"
  mut "$T/no-providers.json" 'delete $e->{providers}'
  guard "$T/m/codex/codex" CODEX_OBJC_BUILD_EVIDENCE="$T/no-providers.json" CODEX_OBJC_PROVIDER_PREFIX="$PFX"
  case "$(verdicts "$report" "$SEL_OPEN")" in provided) fail "evidence without the provider mapping still provides openURLs" ;; *) pass "evidence stripped of the provider mapping: openURLs is $(verdicts "$report" "$SEL_OPEN") (exit $rc)" ;; esac

  guard "$T/m/codex/codex" CODEX_OBJC_PROVIDER_PREFIX="$PFX"
  case "$(verdicts "$report" "$SEL_OPEN")" in provided) fail "no build evidence still provides openURLs" ;; *) pass "no build evidence: openURLs is $(verdicts "$report" "$SEL_OPEN") (exit $rc)" ;; esac

  if grep -q '"guards"' "$EV"; then
    mut "$T/other-patches.json" '$e->{source}{patches_sha256} = "0" x 64'
    guard "$T/m/codex/codex" CODEX_OBJC_BUILD_EVIDENCE="$T/other-patches.json" CODEX_OBJC_PROVIDER_PREFIX="$PFX"
    [ "$rc" = 4 ] && pass "guard records reviewed under another patch series are refused (exit 4: $(codes "$report"))" ||
      fail "evidence claiming another patch series: exit $rc"
  else
    echo "note: the evidence carries no guard records yet, so a changed patch series has none to invalidate"
  fi

  printf '\001' | dd of="$T/m/codex/codex" bs=1 seek=4096 conv=notrunc 2>/dev/null
  guard "$T/m/codex/codex" CODEX_OBJC_BUILD_EVIDENCE="$EV" CODEX_OBJC_PROVIDER_PREFIX="$PFX"
  [ "$rc" = 4 ] && pass "a changed byte in codex makes its evidence stale (exit 4: $(codes "$report"))" || fail "a changed codex byte: exit $rc"
  cp "$ART/codex" "$T/m/codex/codex"

  if [ -n "${MAVERICKS_OBJC_CODEX_ARTIFACT:-}" ]; then
    mkdir -p "$T/o/codex"; cp "$MAVERICKS_OBJC_CODEX_ARTIFACT" "$T/o/codex/codex"
    guard "$T/o/codex/codex" CODEX_OBJC_BUILD_EVIDENCE="$EV" CODEX_OBJC_PROVIDER_PREFIX="$PFX"
    [ "$rc" = 4 ] && pass "the rebuilt binary's evidence does not transfer to the original (exit 4: $(codes "$report"))" || fail "rebuilt evidence on the original: exit $rc"
    rm -rf "$T/o"
  fi

  # the provider's declaration (wrong ABI) or archive bytes differ from what the build linked
  cp -R "$PFX" "$T/pfx-abi"
  sed 's/"@56@0:8@16@24Q32@40^@48"/"@56@0:8@16@24I32@40^@48"/' "$PFX/share/recaulk/objc-providers.json" > "$T/pfx-abi/share/recaulk/objc-providers.json"
  guard "$T/m/codex/codex" CODEX_OBJC_BUILD_EVIDENCE="$EV" CODEX_OBJC_PROVIDER_PREFIX="$T/pfx-abi"
  [ "$(verdicts "$report" "$SEL_OPEN")" != provided ] && [ "$rc" != 0 ] && pass "a provider declaring another ABI does not provide openURLs (exit $rc)" || fail "wrong ABI: exit $rc, openURLs $(verdicts "$report" "$SEL_OPEN")"
  cp -R "$PFX" "$T/pfx-noreceipt"; rm -f "$T/pfx-noreceipt/share/recaulk/objc-source.receipt"
  guard "$T/m/codex/codex" CODEX_OBJC_BUILD_EVIDENCE="$EV" CODEX_OBJC_PROVIDER_PREFIX="$T/pfx-noreceipt"
  case "$(verdicts "$report" countByEnumeratingWithState:objects:count: ___recaulk_)" in
    *unresolved*) pass "without its source receipt the provider body's sends stay open" ;;
    *) fail "without its source receipt the provider body's sends are $(verdicts "$report" countByEnumeratingWithState:objects:count: ___recaulk_)" ;;
  esac
  cp -R "$PFX" "$T/pfx-bytes"; printf 'x' >> "$T/pfx-bytes/lib/librecaulk-objc.a"
  guard "$T/m/codex/codex" CODEX_OBJC_BUILD_EVIDENCE="$EV" CODEX_OBJC_PROVIDER_PREFIX="$T/pfx-bytes"
  [ "$(verdicts "$report" "$SEL_OPEN")" != provided ] && [ "$rc" != 0 ] && pass "a provider archive with other bytes does not provide openURLs (exit $rc)" || fail "changed archive: exit $rc"
  rm -rf "$T/m"

  # a stale proof: once codex changes, --check and the gate refuse the old reports
  TB="$T/broot"; mkdir -p "$TB"
  cp -R "$ART" "$TB/codex-$MODE"; mkdir -p "$TB/objc-$MODE"; cp -R "$OBJC/linkmaps" "$TB/objc-$MODE/"
  ln -s "$BR/codex-src" "$TB/codex-src"
  ( MAVERICKS_BUILD_ROOT="$TB" CODEX_DEV_RECAULK_PREFIX="$PFX" sh "$ROOT/build/objc-build-evidence.sh" "$MODE" ) > "$T/stale-ev.log" 2>&1 || true
  if ( MAVERICKS_BUILD_ROOT="$TB" sh "$ROOT/build/objc-build-evidence.sh" --check "$MODE" ) > "$T/check1.log" 2>&1; then
    printf '\001' | dd of="$TB/codex-$MODE/codex" bs=1 seek=4096 conv=notrunc 2>/dev/null
    if ( MAVERICKS_BUILD_ROOT="$TB" sh "$ROOT/build/objc-build-evidence.sh" --check "$MODE" ) > "$T/check2.log" 2>&1; then
      fail "--check accepted a codex that changed after its proof"
    else pass "--check refuses a proof once codex changed: $(head -1 "$T/check2.log")"; fi
    printf '\001' | dd of="$TB/codex-$MODE/codex-code-mode-host" bs=1 seek=4096 conv=notrunc 2>/dev/null
    if ( MAVERICKS_BUILD_ROOT="$TB" sh "$ROOT/build/objc-build-evidence.sh" --check "$MODE" ) > "$T/check3.log" 2>&1 ||
       ! grep -q 'codex-code-mode-host changed since its proof' "$T/check3.log"; then
      fail "--check did not name a code-mode host that changed after its proof: $(head -2 "$T/check3.log")"
    else pass "--check refuses a proof once the code-mode host changed"; fi
    rc=0; MAVERICKS_BUILD_ROOT="$TB" CODEX_DEV_RECAULK_PREFIX="$PFX" sh "$ROOT/build/compat-guard.sh" "$TB/codex-$MODE/codex" > "$T/stale-guard.log" 2>&1 || rc=$?
    [ "$rc" = 1 ] && grep -q 'no current Objective-C proof' "$T/stale-guard.log" && pass "the gate will not reuse the stale reports" || fail "the gate with a stale proof: exit $rc"
  else
    fail "--check refused the proof it had just written: $(cat "$T/check1.log" "$T/stale-ev.log" | tail -5)"
  fi
  rm -rf "$TB"

  # link-level: a consumer of the same send, linked with the build's arguments minus one part
  SDK=$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" --arch x86_64)
  printf '%s\n' '#import <AppKit/AppKit.h>' '@interface NSWorkspace (Later)' \
    '- (id)openURLs:(NSArray *)u withApplicationAtURL:(NSURL *)a options:(NSUInteger)o configuration:(NSDictionary *)c error:(NSError **)e;' \
    '- (void)openApplicationAtURL:(NSURL *)a configuration:(id)c completionHandler:(id)h;' '@end' \
    'int main(int argc, char **argv) { (void)argv;' \
    '  if (argc > 99) return [[NSWorkspace sharedWorkspace] openURLs:nil withApplicationAtURL:nil options:0 configuration:nil error:NULL] != nil;' \
    '  return 0; }' > "$T/consumer.m"
  sed 's/^  return 0; }$/  if (argc > 98) [[NSWorkspace sharedWorkspace] openApplicationAtURL:nil configuration:nil completionHandler:nil];\
  return 0; }/' "$T/consumer.m" > "$T/consumer-newer.m"
  sh "$SHIPYARD_SCRIPTS/objc-provider-link-args.sh" --prefix "$PFX" --link-map "$T/consumer.map" > "$T/args"
  # link NAME AWK-FILTER: $T/c-NAME/bin/c from $SRC (default consumer.m) with the filtered arguments,
  # shipyard's evidence for it, and the gate.
  link() {
    mkdir -p "$T/c-$1/bin"; awk "$2" "$T/args" > "$T/args.$1"
    lname=$1
    set --; while IFS= read -r l; do set -- "$@" "$l"; done < "$T/args.$lname"
    env -i PATH=/usr/bin:/bin /usr/bin/clang -arch x86_64 -isysroot "$SDK" -mmacosx-version-min=10.9 -O1 "$T/${SRC:-consumer}.m" -framework AppKit "$@" -o "$T/c-$lname/bin/c" 2>"$T/link.log" ||
      { echo "link $lname failed: $(tail -2 "$T/link.log")"; return 1; }
    rm -f "$T/c-$lname.ev"
    sh "$SHIPYARD_SCRIPTS/objc-build-evidence.sh" --artifact "$T/c-$lname/bin/c" --prestrip "$T/c-$lname/bin/c" --source-root "$T/c-$lname" \
      --link-map "$T/consumer.map" --provider-prefix "$PFX" --references "$SHIPYARD_SCRIPTS/../reference/objc" --output "$T/c-$lname.ev" > /dev/null 2>&1 || true
    if [ -f "$T/c-$lname.ev" ]; then guard "$T/c-$lname/bin/c" CODEX_OBJC_BUILD_EVIDENCE="$T/c-$lname.ev" CODEX_OBJC_PROVIDER_PREFIX="$PFX"
    else guard "$T/c-$lname/bin/c" CODEX_OBJC_PROVIDER_PREFIX="$PFX"; fi
  }
  if link all '{print}'; then
    [ "$(verdicts "$report" "$SEL_OPEN")" = provided ] && [ "$rc" = 0 ] && pass "a consumer linked with every argument: openURLs provided, gate clean" ||
      fail "full link: openURLs $(verdicts "$report" "$SEL_OPEN") (exit $rc)"
  else fail "the consumer did not link with every argument"; fi
  # Carbon is declared but bound to by nothing (the provider reaches its functions through CoreServices and
  # ApplicationServices), so leaving it out, as lld does for codex, keeps openURLs provided. What the provider
  # does need loaded -- its imports' libraries and NSWorkspace's AppKit -- shipyard's provider test mutates.
  if link no-carbon '{a[NR]=$0} END {for (i = 1; i <= NR; i++) { if (a[i] == "-framework" && a[i+1] == "Carbon") { i++; continue }; print a[i] }}'; then
    [ "$(verdicts "$report" "$SEL_OPEN")" = provided ] && [ "$rc" = 0 ] && pass "no-carbon: openURLs still provided, as in codex's lld link" ||
      fail "no-carbon: openURLs $(verdicts "$report" "$SEL_OPEN") (exit $rc)"
  else fail "the consumer did not link without Carbon"; fi
  for m in 'no-archive|!/\.a$/ && !/^-Wl,-u,/' 'no-root|!/^-Wl,-u,/'; do
    if link "${m%%|*}" "${m#*|}"; then
      case "$(verdicts "$report" "$SEL_OPEN")" in provided) fail "${m%%|*}: openURLs still provided" ;; *) pass "${m%%|*}: openURLs is $(verdicts "$report" "$SEL_OPEN") (exit $rc)" ;; esac
    else pass "${m%%|*}: the link itself fails"; fi
  done
  if SRC=consumer-newer link newer '{print}'; then
    v=$(verdicts "$report" openApplicationAtURL:configuration:completionHandler:)
    [ "$v" = unsupported ] && [ "$rc" = 1 ] && pass "a newly added 10.15 API is refused from shipyard's reference catalog, with no Codex list" || fail "a newer API: $v (exit $rc)"
  else fail "the newer-API consumer did not link"; fi
fi

[ "$fails" = 0 ] || { echo "objc-gate-test: $fails failed"; exit 1; }
echo "objc-gate-test: all passed"
