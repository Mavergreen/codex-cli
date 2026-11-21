#!/bin/sh
# platform: host-agnostic -- plain sh over the repo's own files
# spec: build/objc-reviewed-dir.sh header -- each build host has its directory of reviewed rows and the
#       proof takes the build host's; the rows are schema 2, so the two hold the same rows.
#   usage: sh tests/objc-reviewed-host-test.sh
set -eu
. "$(dirname "$0")/lib/harness.sh"
h_setup
D="$H_REPO/build/objc-reviewed-dir.sh"
h_assert_eq "$H_REPO/objc/x86_64-apple-darwin" "$(sh "$D" x86_64)" "an x86_64 host (10.9 native, or an Intel Mac's cross) takes the x86_64-apple-darwin rows"
h_assert_eq "$H_REPO/objc/aarch64-apple-darwin" "$(sh "$D" arm64)" "Apple Silicon (rust-cross, as CI) takes the aarch64-apple-darwin rows"
rc=0; sh "$D" i386 >/dev/null 2>&1 || rc=$?
h_assert_eq 1 "$rc" "no Mavergreen rust runs on any other host, so it has no rows"
h_assert_eq "$(sh "$D" "$(uname -m)")" "$(sh "$D")" "with no argument, the host it runs on"
for f in codex-reviewed-evidence.json codex-code-mode-host-reviewed-evidence.json; do
  h_assert_ok test -f "$H_REPO/objc/x86_64-apple-darwin/$f"
  h_assert_absent "$H_REPO/objc/$f" "no host-less $f is left to be taken by mistake"
done
# spec: Drydock's content-keyed reviews (schema 2) -- reviewed rows name functions by path and the files
#       they rest on by hash; drydock-objc resolve fills symbols and crate disambiguators from the artifact
#       on every build, so nothing host-bound is committed and both hosts' rows are the same.
for f in codex-reviewed-evidence.json codex-code-mode-host-reviewed-evidence.json; do
  X="$H_REPO/objc/x86_64-apple-darwin/$f"; A="$H_REPO/objc/aarch64-apple-darwin/$f"
  h_assert_ok cmp -s "$X" "$A"
  h_assert_eq "" "$(perl -MJSON::PP -e '
    local $/; open my $h, "<", $ARGV[0] or die; my $e = JSON::PP->new->decode(<$h>); my @bad;
    push @bad, "schema" unless ($e->{schema} // 0) == 2 && ($e->{kind} // "") eq "objc-build-evidence";
    for my $k (qw(guards type_evidence position_evidence)) {
      for my $r (@{$e->{$k} || []}) {
        push @bad, "$k $r->{id}: committed symbol" if exists $r->{symbol} || exists $r->{symbols};
        push @bad, "$k $r->{id}: no path" unless length($r->{path} // "");
        push @bad, "$k $r->{id}: no sources" unless @{$r->{sources} || []};
        push @bad, "$k $r->{id}: cite $_->{cite}" for grep { $_->{cite} !~ m{^(tree|crate|sdk):[^/.][^\s]*$} || $_->{sha256} !~ /^[0-9a-f]{64}$/ } @{$r->{sources} || []};
      }
    }
    for my $g (@{$e->{guards} || []}) { push @bad, "guard $g->{id}: no covers" unless @{$g->{covers} || []} }
    push @bad, "crate $_->{name}: committed disambiguator" for grep { exists $_->{disambiguator} } @{$e->{crates} || []};
    print join("; ", @bad)' "$X")" "$f is schema 2: rows by path with hashed sources, guards with covers, no symbols or disambiguators"
done
h_assert_contains "$(cat "$H_REPO/build/objc-build-evidence.sh")" 'objc-reviewed-dir.sh' "the proof takes its rows from the build host's directory"
h_done
