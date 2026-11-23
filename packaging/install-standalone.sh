#!/bin/sh
# platform: macOS-only -- runs with Mac OS X 10.9's curl, tar, shasum and perl, as the user, no sudo
#   usage: curl -fsSL https://github.com/Mavergreen/codex-cli/releases/latest/download/install-standalone.sh | sh
#          Installs or updates Codex CLI for Mavericks from its standalone archive, the latest release's
#          codex-cli-<version>-macos-x86_64.tar.gz, checked against that release's SHA256SUMS. It is
#          unpacked into ~/.local/share/codex-cli/codex-cli-<version>, current points at it, and
#          ~/.local/bin/codex at current's launcher, which downloads Codex on first run. The older
#          release is removed. Nothing outside the home directory changes. AquaTransport is not a
#          Mavergreen product: it checks for it first, and without a new enough one says where to get
#          it and installs nothing. MAVERGREEN_RELEASES overrides the base URL that holds
#          codex-cli/releases/latest/download/.

note() { printf 'Codex CLI for Mavericks: %s\n' "$*"; }
die() { printf 'Codex CLI for Mavericks: ERROR: %s\n' "$*" >&2; exit 1; }

main() {
  set -eu
  base="${MAVERGREEN_RELEASES:-https://github.com/Mavergreen}"
  # spec: components/aquatransport/min-version; tests/curl-install-test.sh keeps install.sh's identical
  aqmin=2026.10.25
  aqurl=https://mavericksforever.com/downloads/AquaTransport.dmg
  case "${HOME-}" in /*[!/.]*) ;; *) die "HOME must be an absolute path other than / (it is '${HOME-}')" ;; esac
  share="$HOME/.local/share/codex-cli"
  link="$HOME/.local/bin/codex"

  case "$(uname -s)" in Darwin) ;; *) die "only macOS is supported" ;; esac
  case "$(uname -m)" in x86_64|amd64) ;; *) die "unsupported arch: $(uname -m)" ;; esac

  # spec: tree/libexec/codex-cli/lib.sh cx_require_aquatransport -- the launcher refuses the same way
  aqhave="$(PATH="$PATH:/usr/sbin" pkgutil --pkg-info Wowfunhappy.AquaTransport 2>/dev/null | sed -n 's/^version: *//p' | head -n 1)"
  aqneed="Codex needs AquaTransport $aqmin or newer for TLS on this Mac: get it from $aqurl, install it, then run this again"
  [ -n "$aqhave" ] || die "AquaTransport is not installed. $aqneed"
  case "$aqhave" in
    [0-9][0-9][0-9][0-9].[0-9][0-9].[0-9][0-9]) ;;
    *) die "AquaTransport version '$aqhave' is not YYYY.MM.DD. $aqneed" ;;
  esac
  [ "$(printf %s "$aqhave" | tr -d .)" -ge "$(printf %s "$aqmin" | tr -d .)" ] ||
    die "AquaTransport $aqhave is too old. $aqneed"

  mkdir -p "$share" "$(dirname "$link")"
  tmp="$(mktemp -d "$share/.install.XXXXXX")" || die "could not create a temporary directory in $share"
  trap 'rm -rf "$tmp"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  url="$base/codex-cli/releases/latest/download"
  curl -fsSL --proto-redir =https -o "$tmp/SHA256SUMS" "$url/SHA256SUMS" || die "could not fetch $url/SHA256SUMS"
  awk '
    { n = $2; sub(/^\*/, "", n) }
    NF == 2 && $1 ~ /^[0-9a-f]+$/ && length($1) == 64 && n ~ /^codex-cli-[0-9][0-9A-Za-z.+-]*-macos-x86_64\.tar\.gz$/ { print $1, n }
  ' "$tmp/SHA256SUMS" > "$tmp/match"
  count="$(wc -l < "$tmp/match" | tr -d ' ')"
  [ "$count" -eq 1 ] || die "the latest release lists $count codex-cli-<version>-macos-x86_64.tar.gz in SHA256SUMS, not one"
  read -r want asset < "$tmp/match"
  ver="${asset#codex-cli-}"; ver="${ver%-macos-x86_64.tar.gz}"
  dir="codex-cli-$ver"

  if [ "$(readlink "$share/current" 2>/dev/null || :)" = "$dir" ] && [ -x "$share/$dir/bin/codex" ]; then
    note "$ver is already installed"
  else
    note "downloading $asset"
    curl -fL --proto-redir =https --progress-bar -o "$tmp/$asset" "$url/$asset" || die "could not download $url/$asset"
    got="$(shasum -a 256 "$tmp/$asset" | cut -d' ' -f1)"
    [ -n "$got" ] && [ "$got" = "$want" ] || die "$asset does not match $url/SHA256SUMS (wanted $want, got ${got:-nothing})"
    mkdir "$tmp/x"
    tar -xzf "$tmp/$asset" -C "$tmp/x" || die "could not unpack $asset"
    [ -x "$tmp/x/$dir/bin/codex" ] || die "$asset holds no $dir/bin/codex"
    rm -rf "$share/$dir"
    mv "$tmp/x/$dir" "$share/$dir"
    ln -s "$dir" "$tmp/current"
    # platform: 10.9's mv has neither -T nor -h, so perl's rename(2) swaps the link in one step
    perl -e 'rename($ARGV[0], $ARGV[1]) or die "$!\n"' "$tmp/current" "$share/current" || die "could not point $share/current at $dir"
    for old in "$share"/codex-cli-*; do
      [ "$old" = "$share/$dir" ] || rm -rf "$old"
    done
    note "installed $ver in $share/$dir"
  fi

  if [ -L "$link" ] || [ ! -e "$link" ]; then
    ln -s "$share/current/bin/codex" "$tmp/link"
    perl -e 'rename($ARGV[0], $ARGV[1]) or die "$!\n"' "$tmp/link" "$link" || die "could not link $link"
  else
    note "$link is not a link this installer made, so it is left alone; run $share/current/bin/codex"
  fi
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) note "done. Run codex; its first run downloads Codex." ;;
    *) note "done. Add ~/.local/bin to your PATH, or run $link; its first run downloads Codex." ;;
  esac
}

main "$@"
