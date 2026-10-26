#!/bin/sh
# platform: macOS-only -- drives packaging/install.sh, which reads plists with 10.9's /usr/libexec/PlistBuddy
#   usage: sh tests/curl-install-test.sh
#          The README's one-liner: refuses without a new enough AquaTransport before it fetches anything,
#          then installs rg, ed25519 and codex-cli from a file:// release tree, skipping what is current.
set -eu
. "$(dirname "$0")/lib/harness.sh"
[ -x /usr/libexec/PlistBuddy ] || exit 77
h_setup
I="$H_REPO/packaging/install.sh"
REL="$H/rel"
mkdir -p "$H/tmp"
MAVERGREEN_RELEASES="file://$(printf %s "$REL" | sed "s/%/%25/g; s/ /%20/g; s/#/%23/g; s/?/%3F/g")"
MAVERGREEN_INSTALL_ROOT="$H/root"
TMPDIR="$H/tmp/"
PATH="$H/bin:$PATH"
H_RECEIPT=2026.10.25
export MAVERGREEN_RELEASES MAVERGREEN_INSTALL_ROOT TMPDIR PATH H_RECEIPT

cat > "$H/bin/sudo" <<'SUDO'
#!/bin/sh
if [ "$*" = "-n true" ]; then [ -n "${H_NOPASSWD-}" ] || exit 1; echo "sudo -n true" >> "$H/run.log"; exit 0; fi
if [ "$*" = "-v" ]; then
  [ -z "${H_NOPASSWD-}" ] || { echo "sudo -v without a tty" >> "$H/run.log"; exit 1; }
  echo "sudo -v" >> "$H/run.log"; exit 0
fi
if [ "$1" = /usr/sbin/installer ] && [ "$2" = -pkg ] && [ "$4" = -target ] && [ "$5" = / ] && [ $# -eq 5 ]; then
  [ -f "$3" ] || { echo "missing $3" >> "$H/run.log"; exit 1; }
  case "$3" in "$H/tmp/"*) ;; *) echo "outside the temp dir: $3" >> "$H/run.log"; exit 1 ;; esac
  echo "install $(basename "$3") $(cat "$3")" >> "$H/run.log"
  exit 0
fi
echo "unexpected sudo $*" >> "$H/run.log"
exit 1
SUDO
cat > "$H/bin/sw_vers" <<'SW'
#!/bin/sh
[ "$*" = "-productVersion" ] || exit 1
printf '%s\n' "${H_OSVER-10.9.5}"
SW
cat > "$H/bin/uname" <<'UN'
#!/bin/sh
case "$*" in
  -s) printf '%s\n' "${H_KERNEL-Darwin}" ;;
  -m) printf '%s\n' "${H_ARCH-x86_64}" ;;
  *) exec /usr/bin/uname "$@" ;;
esac
UN
cat > "$H/bin/installer" <<'INS'
#!/bin/sh
echo "installer reached without sudo: $*" >> "$H/run.log"
exit 1
INS
cat > "$H/bin/pkgutil" <<'PU'
#!/bin/sh
[ "$*" = "--pkg-info Wowfunhappy.AquaTransport" ] || { echo "unexpected pkgutil $*" >> "$H/run.log"; exit 1; }
[ -n "${H_RECEIPT-}" ] || { echo "No receipt for 'Wowfunhappy.AquaTransport' found at '/'." >&2; exit 1; }
printf 'package-id: Wowfunhappy.AquaTransport\nversion: %s\nvolume: /\nlocation: /\ninstall-time: 1\n' "$H_RECEIPT"
PU
cat > "$H/bin/curl" <<'CURL'
#!/bin/sh
echo "$*" >> "$H/curl.log"
exec /usr/bin/curl "$@"
CURL
chmod +x "$H/bin/sudo" "$H/bin/sw_vers" "$H/bin/uname" "$H/bin/installer" "$H/bin/pkgutil" "$H/bin/curl"
hash -r

pub() {
  _d="$REL/$1/releases/latest/download"
  mkdir -p "$_d"
  shift
  for _a in "$@"; do printf 'payload %s\n' "$_a" > "$_d/$_a"; done
  (cd "$_d" && shasum -a 256 "$@" > SHA256SUMS)
}
release_all() {
  rm -rf "$REL"
  pub rg rg-15.2.0-mavericks.8.pkg rg.xml build-info-native.txt
  pub ed25519 ed25519-20221003-mavericks.7.pkg
  pub codex-cli codex-cli-0.164.0-mavericks.1.pkg codex-cli.xml install.sh
}
installed() {
  _p="$MAVERGREEN_INSTALL_ROOT/usr/local/mavergreen/$1/mavergreen.plist"
  mkdir -p "$(dirname "$_p")"
  rm -f "$_p"
  /usr/libexec/PlistBuddy -c "Add :version string $2" "$_p" >/dev/null
}
fresh() {
  rm -rf "$MAVERGREEN_INSTALL_ROOT/usr/local/mavergreen" "$H/run.log" "$H/curl.log"
  : > "$H/run.log"; : > "$H/curl.log"
  release_all
}
run() { rc=0; out="$(sh "$I" 2>&1)" || rc=$?; log="$(cat "$H/run.log")"; last="$(printf '%s\n' "$out" | tail -n 1)"; }
DONE="Codex CLI for Mavericks: done. Open a new Terminal window, then run codex."
URL=https://mavericksforever.com/downloads/AquaTransport.dmg
tmp_left() { ls -A "$H/tmp"; }

ALL="sudo -v
install rg-15.2.0-mavericks.8.pkg payload rg-15.2.0-mavericks.8.pkg
install ed25519-20221003-mavericks.7.pkg payload ed25519-20221003-mavericks.7.pkg
install codex-cli-0.164.0-mavericks.1.pkg payload codex-cli-0.164.0-mavericks.1.pkg"

fresh; run
h_assert_eq 0 "$rc" "a fresh install succeeds: $out"
h_assert_eq "$ALL" "$log" "installs all three, in order, after one sudo -v"
h_assert_eq "$DONE" "$last" "ends saying to open a new Terminal window, then run codex"
h_assert_eq "" "$(tmp_left)" "the temp dir is removed after success"

fresh; H_NOPASSWD=1; export H_NOPASSWD; run; unset H_NOPASSWD
h_assert_eq 0 "$rc" "an administrator whose sudo needs no password installs without a tty: $out"
h_assert_eq "sudo -n true
${ALL#sudo -v
}" "$log" "passwordless sudo installs all three without sudo -v, which wants a tty even then"

fresh; installed rg 15.2.0-mavericks.8; installed codex-cli 0.163.0-mavericks.2; run
h_assert_eq 0 "$rc" "an update succeeds: $out"
h_assert_eq "sudo -v
install ed25519-20221003-mavericks.7.pkg payload ed25519-20221003-mavericks.7.pkg
install codex-cli-0.164.0-mavericks.1.pkg payload codex-cli-0.164.0-mavericks.1.pkg" "$log" "skips the product whose manifest records the release's version"
h_assert_contains "$out" "rg 15.2.0-mavericks.8 is already installed" "names the product it skips"

fresh; installed rg 15.2.0-mavericks.8; installed ed25519 20221003-mavericks.7; installed codex-cli 0.164.0-mavericks.1; run
h_assert_eq 0 "$rc" "an up-to-date system succeeds: $out"
h_assert_eq "" "$log" "nothing to install asks for no password"
h_assert_eq "$DONE" "$last" "an up-to-date run still ends saying what to do next"

# AquaTransport: read from its receipt, never installed; refused before anything is fetched
fresh; H_RECEIPT=; run; H_RECEIPT=2026.10.25
h_assert_eq 1 "$rc" "no AquaTransport stops the install"
h_assert_eq "Codex CLI for Mavericks: ERROR: AquaTransport is not installed. Codex needs AquaTransport 2026.10.25 or newer for TLS on this Mac: get it from $URL, install it, then run this again" "$out" "no AquaTransport says where to get it"
h_assert_eq "" "$log" "no AquaTransport installs nothing"
h_assert_eq "" "$(cat "$H/curl.log")" "no AquaTransport fetches nothing"
h_assert_eq "" "$(tmp_left)" "no AquaTransport leaves no temp dir"

for _old in 2026.10.24 2026.09.30 2025.12.31; do
  fresh; H_RECEIPT=$_old; run; H_RECEIPT=2026.10.25
  h_assert_eq 1 "$rc" "AquaTransport $_old stops the install"
  h_assert_eq "Codex CLI for Mavericks: ERROR: AquaTransport $_old is too old. Codex needs AquaTransport 2026.10.25 or newer for TLS on this Mac: get it from $URL, install it, then run this again" "$out" "AquaTransport $_old says it is too old"
  h_assert_eq "" "$(cat "$H/curl.log")" "AquaTransport $_old fetches nothing"
done

fresh; H_RECEIPT=garbage; run; H_RECEIPT=2026.10.25
h_assert_eq 1 "$rc" "an unreadable AquaTransport version stops the install"
h_assert_contains "$out" "AquaTransport version 'garbage' is not YYYY.MM.DD" "names the unreadable version"

for _new in 2026.10.26 2026.11.01 2027.01.01; do
  fresh; H_RECEIPT=$_new; run; H_RECEIPT=2026.10.25
  h_assert_eq 0 "$rc" "AquaTransport $_new is new enough: $out"
done

h_assert_eq "aqmin=$(tr -d '[:space:]' < "$H_REPO/components/aquatransport/min-version")" \
  "$(grep -E '^ *aqmin=' "$I" | tr -d ' ')" "install.sh carries the component's AquaTransport pin"

fresh; H_OSVER=10.8.5; H_RECEIPT=; export H_OSVER; run; unset H_OSVER; H_RECEIPT=2026.10.25
h_assert_eq 1 "$rc" "refuses 10.8"
h_assert_contains "$out" "Mac OS X 10.9.5 is required" "the OS is checked before AquaTransport"
h_assert_eq "" "$log" "refusing 10.8 runs nothing"

for _v in 10.9 10.9.4 10.10.5; do
  fresh; H_OSVER=$_v; export H_OSVER; run; unset H_OSVER
  h_assert_eq 1 "$rc" "refuses $_v"
  h_assert_eq "" "$log" "refusing $_v runs nothing"
done

fresh; H_KERNEL=Linux; export H_KERNEL; run; unset H_KERNEL
h_assert_eq 1 "$rc" "refuses a kernel other than Darwin"
h_assert_contains "$out" "only macOS is supported" "the kernel refusal keeps its wording"

fresh; H_ARCH=i386; export H_ARCH; run; unset H_ARCH
h_assert_eq 1 "$rc" "refuses a 32-bit Mac"
h_assert_contains "$out" "unsupported arch: i386" "the arch refusal keeps its wording"

fresh; run
_n="$(grep -c . "$H/curl.log" || :)"; _p="$(grep -c -F -e '--proto-redir =https' "$H/curl.log" || :)"
h_assert_ok test "$_n" -ge 6
h_assert_eq "$_n" "$_p" "every curl call restricts redirects to https"

fresh; printf 'tampered\n' > "$REL/ed25519/releases/latest/download/ed25519-20221003-mavericks.7.pkg"; run
h_assert_eq 1 "$rc" "a checksum mismatch fails"
h_assert_contains "$out" "ed25519-20221003-mavericks.7.pkg" "the mismatch names the pkg"
h_assert_eq "" "$log" "a checksum mismatch is found before anything is installed"
h_assert_eq "" "$(tmp_left)" "the temp dir is removed after a failure"

fresh
_d="$REL/codex-cli/releases/latest/download"
printf 'payload old\n' > "$_d/codex-cli-0.163.0-mavericks.2.pkg"
(cd "$_d" && shasum -a 256 codex-cli-0.163.0-mavericks.2.pkg >> SHA256SUMS)
run
h_assert_eq 1 "$rc" "a release with two matching pkgs fails"
h_assert_contains "$out" "codex-cli: its latest release lists 2" "the failure names the repo"
h_assert_eq "" "$log" "two matching pkgs install nothing"

fresh; rm "$REL/rg/releases/latest/download/SHA256SUMS"; run
h_assert_eq 1 "$rc" "a release without SHA256SUMS fails"
h_assert_contains "$out" "rg: could not fetch" "the failure names the repo"
h_assert_eq "" "$log" "a missing SHA256SUMS installs nothing"
h_assert_eq "" "$(tmp_left)" "the temp dir is removed after a fetch failure"

fresh
rc=0; out="$(cat "$I" | sh 2>&1)" || rc=$?; log="$(cat "$H/run.log")"; last="$(printf '%s\n' "$out" | tail -n 1)"
h_assert_eq 0 "$rc" "works when piped into sh: $out"
h_assert_eq "$ALL" "$log" "piped into sh, installs all three in order"
h_assert_eq "$DONE" "$last" "piped into sh, ends saying what to do next"

_rq="$(sed 's/ .*//' "$H_REPO/tree/share/codex-cli/requires" | tr '\n' ' ')codex-cli"
_is="$(sed -n 's/^ *for short in \(.*\); do$/\1/p' "$I")"
h_assert_eq "$_rq" "$_is" "install.sh installs exactly what the pkg requires, in the same order, then codex-cli"

W="$H_REPO/.github/workflows/release.yml"
_wc="$(grep -n -F 'cp packaging/install.sh "$BUILD/dist/install.sh"' "$W" | head -n 1 | cut -d: -f1)"
_wp="$(grep -n -F 'sh tests/package-test.sh "$PKG"' "$W" | head -n 1 | cut -d: -f1)"
_wn="$(grep -n -F -- '- name: Release notes' "$W" | head -n 1 | cut -d: -f1)"
h_assert_ok test "${_wp:-99}" -lt "${_wc:-0}"
h_assert_ok test "${_wc:-99}" -lt "${_wn:-0}"
h_done
