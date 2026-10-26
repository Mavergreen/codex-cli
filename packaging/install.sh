#!/bin/sh
# platform: macOS-only -- installs .pkg products with /usr/sbin/installer on Mac OS X 10.9
#   usage: curl -fsSL https://github.com/Mavergreen/codex-cli/releases/latest/download/install.sh | sh
#          Installs or updates rg, ed25519 and Codex CLI for Mavericks, in that order, each from its
#          repo's latest release. AquaTransport is not a Mavergreen product: it checks for it first,
#          and without a new enough one says where to get it and installs nothing. MAVERGREEN_RELEASES
#          overrides the base URL that holds <repo>/releases/latest/download/; MAVERGREEN_INSTALL_ROOT
#          prefixes /usr/local/mavergreen when reading what is already installed.

note() { printf 'Codex CLI for Mavericks: %s\n' "$*"; }
die() { printf 'Codex CLI for Mavericks: ERROR: %s\n' "$*" >&2; exit 1; }

main() {
  set -eu
  base="${MAVERGREEN_RELEASES:-https://github.com/Mavergreen}"
  root="${MAVERGREEN_INSTALL_ROOT-}"
  # spec: components/aquatransport/min-version; tests/curl-install-test.sh keeps the two identical
  aqmin=2026.10.25
  aqurl=https://mavericksforever.com/downloads/AquaTransport.dmg

  case "$(uname -s)" in Darwin) ;; *) die "only macOS is supported" ;; esac
  osver="$(sw_vers -productVersion 2>/dev/null || :)"
  case "$osver" in
    10.9.[5-9]|10.9.[1-9][0-9]*) ;;
    *) die "Mac OS X 10.9.5 is required; this Mac runs ${osver:-an unknown version}" ;;
  esac
  case "$(uname -m)" in x86_64|amd64) ;; *) die "unsupported arch: $(uname -m)" ;; esac

  # spec: tree/libexec/codex-cli/lib.sh cx_require_aquatransport -- the launcher refuses the same way
  aqhave="$(PATH="$PATH:/usr/sbin" pkgutil --pkg-info Wowfunhappy.AquaTransport 2>/dev/null | sed -n 's/^version: *//p' | head -n 1)"
  aqneed="Codex needs AquaTransport $aqmin or newer for TLS on this Mac: get it from $aqurl, install it, then run this again"
  [ -n "$aqhave" ] || die "AquaTransport is not installed. $aqneed"
  case "$aqhave" in
    [0-9][0-9][0-9][0-9].[0-9][0-9].[0-9][0-9]) ;;
    *) die "AquaTransport version '$aqhave' is not YYYY.MM.DD. $aqneed" ;;
  esac
  # YYYYMMDD with the dots dropped orders the same as the fields compared one by one
  [ "$(printf %s "$aqhave" | tr -d .)" -ge "$(printf %s "$aqmin" | tr -d .)" ] ||
    die "AquaTransport $aqhave is too old. $aqneed"

  tmp="$(mktemp -d "${TMPDIR:-/tmp}/mavergreen-install.XXXXXX")" || die "could not create a temporary directory"
  trap 'rm -rf "$tmp"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  plan=""
  for short in rg ed25519 codex-cli; do
    url="$base/$short/releases/latest/download"
    sums="$tmp/$short.SHA256SUMS"
    curl -fsSL --proto-redir =https -o "$sums" "$url/SHA256SUMS" || die "$short: could not fetch $url/SHA256SUMS"
    awk -v s="$short" '
      { n = $2; sub(/^\*/, "", n) }
      NF == 2 && $1 ~ /^[0-9a-f]+$/ && length($1) == 64 && n ~ ("^" s "-[0-9][0-9A-Za-z.+-]*\\.pkg$") { print $1, n }
    ' "$sums" > "$sums.match"
    count="$(wc -l < "$sums.match" | tr -d ' ')"
    [ "$count" -ne 0 ] || die "$short: its latest release lists no $short-<version>.pkg in SHA256SUMS"
    [ "$count" -eq 1 ] || die "$short: its latest release lists $count $short-<version>.pkg in SHA256SUMS, not one"
    read -r want asset < "$sums.match"
    ver="${asset#"$short"-}"; ver="${ver%.pkg}"
    plist="$root/usr/local/mavergreen/$short/mavergreen.plist"
    have=""
    if [ -f "$plist" ]; then
      have="$(/usr/libexec/PlistBuddy -c 'Print :version' "$plist" 2>/dev/null || :)"
    fi
    if [ "$have" = "$ver" ]; then
      note "$short $ver is already installed"
      continue
    fi
    note "downloading $asset"
    curl -fL --proto-redir =https --progress-bar -o "$tmp/$asset" "$url/$asset" || die "$short: could not download $url/$asset"
    got="$(shasum -a 256 "$tmp/$asset" | cut -d' ' -f1)"
    [ -n "$got" ] && [ "$got" = "$want" ] || die "$asset does not match $url/SHA256SUMS (wanted $want, got ${got:-nothing})"
    plan="$plan $asset"
  done

  if [ -n "$plan" ]; then
    # platform: sudo -v wants a tty even when every command needs no password (verifypw=all),
    #       so a passwordless or recently-validated sudo is asked first, non-interactively
    if ! sudo -n true 2>/dev/null; then
      note "installing needs an administrator's password"
      sudo -v || die "could not get administrator rights"
    fi
    for asset in $plan; do
      note "installing $asset"
      sudo /usr/sbin/installer -pkg "$tmp/$asset" -target / || die "installer failed on $asset"
    done
  else
    note "everything is up to date"
  fi

  note "done. Open a new Terminal window, then run codex."
}

main "$@"
