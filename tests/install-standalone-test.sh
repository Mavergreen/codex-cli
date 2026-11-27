#!/bin/sh
# platform: macOS-only -- drives packaging/install-standalone.sh with 10.9's curl, tar and shasum
#   usage: sh tests/install-standalone-test.sh
#          The standalone one-liner: from a file:// release tree it fetches the latest archive, checks it
#          against SHA256SUMS, unpacks it under ~/.local/share/codex-cli, points current at it and
#          ~/.local/bin/codex at current's launcher, with no sudo. A newer release replaces the older,
#          a mismatched archive changes nothing, and a ~/.local/bin/codex of someone else's is left alone.
set -eu
. "$(dirname "$0")/lib/harness.sh"
h_setup
I="$H_REPO/packaging/install-standalone.sh"
REL="$H/rel"
DL="$REL/codex-cli/releases/latest/download"
MAVERGREEN_RELEASES="file://$(printf %s "$REL" | sed "s/%/%25/g; s/ /%20/g; s/#/%23/g; s/?/%3F/g")"
PATH="$H/bin:$PATH"
H_RECEIPT=2026.10.25
export MAVERGREEN_RELEASES PATH H_RECEIPT
SHARE="$HOME/.local/share/codex-cli"
LINK="$HOME/.local/bin/codex"

printf '#!/bin/sh\necho "sudo $*" >> "$H/run.log"\nexit 1\n' > "$H/bin/sudo"
printf '#!/bin/sh\nprintf "%%s\\n" "${H_OSVER-10.9.5}"\n' > "$H/bin/sw_vers"
cat > "$H/bin/pkgutil" <<'PU'
#!/bin/sh
[ -n "${H_RECEIPT-}" ] || exit 1
printf 'package-id: Wowfunhappy.AquaTransport\nversion: %s\n' "$H_RECEIPT"
PU
# platform: the installer takes only an x86_64 Mac; CI's macOS runners are arm64
cat > "$H/bin/uname" <<'UN'
#!/bin/sh
case "$1" in -m) echo x86_64 ;; -s) echo Darwin ;; *) exec /usr/bin/uname "$@" ;; esac
UN
chmod +x "$H/bin/sudo" "$H/bin/sw_vers" "$H/bin/pkgutil" "$H/bin/uname"

release() {
  rm -rf "$DL" "$H/stage"
  mkdir -p "$DL" "$H/stage/codex-cli-$1/bin"
  printf '#!/bin/sh\necho "launcher %s $*"\n' "$1" > "$H/stage/codex-cli-$1/bin/codex"
  chmod +x "$H/stage/codex-cli-$1/bin/codex"
  ( cd "$H/stage" && tar -czf "$DL/codex-cli-$1-macos-x86_64.tar.gz" "codex-cli-$1" ) || return 1
  ( cd "$DL" && shasum -a 256 "codex-cli-$1-macos-x86_64.tar.gz" > SHA256SUMS &&
    printf '%s  codex-cli-%s.pkg\n' 0000000000000000000000000000000000000000000000000000000000000000 "$1" >> SHA256SUMS ) || return 1
}
run() { sh "$I" >"$H/out" 2>&1 && rc=0 || rc=$?; }

release 20261123.1
run
h_assert_eq 0 "$rc" "installs ($(cat "$H/out"))"
h_assert_eq "codex-cli-20261123.1" "$(readlink "$SHARE/current")" "current names the release"
h_assert_eq "$SHARE/current/bin/codex" "$(readlink "$LINK")" "~/.local/bin/codex links to current's launcher"
h_assert_eq "launcher 20261123.1 --version" "$("$LINK" --version)" "the link runs the archive's launcher"
h_assert_absent "$H/run.log" "no sudo"

release 20261124.1
run
h_assert_eq 0 "$rc" "upgrades ($(cat "$H/out"))"
h_assert_eq "codex-cli-20261124.1" "$(readlink "$SHARE/current")" "current names the newer release"
h_assert_absent "$SHARE/codex-cli-20261123.1" "the older release is removed"

run
h_assert_eq 0 "$rc" "a rerun succeeds"
h_assert_contains "$(cat "$H/out")" "20261124.1 is already installed" "and says it is current"

release 20261125.1
printf 'x' >> "$DL/codex-cli-20261125.1-macos-x86_64.tar.gz"
run
h_assert_eq 1 "$rc" "a mismatched archive is refused"
h_assert_contains "$(cat "$H/out")" "does not match" "and says so"
h_assert_eq "codex-cli-20261124.1" "$(readlink "$SHARE/current")" "the installed release is untouched"

release 20261126.1
rm "$LINK"
printf 'someone else\n' > "$LINK"
run
h_assert_eq 0 "$rc" "installs beside a foreign ~/.local/bin/codex"
h_assert_eq "someone else" "$(cat "$LINK")" "the foreign file is left alone"
h_assert_contains "$(cat "$H/out")" "$LINK is not a link this installer made" "and says so"

H_RECEIPT=""
run
h_assert_eq 1 "$rc" "no AquaTransport, no install"
h_assert_contains "$(cat "$H/out")" "AquaTransport is not installed" "and says why"

h_done
