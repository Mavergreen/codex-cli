#!/bin/sh
# platform: macOS-only -- the launcher exists to run Codex on Mac OS X 10.9

cx_die() { echo "codex: $*" >&2; exit 1; }
cx_note() { echo "codex: $*" >&2; }

cx_resolve() {
  _cx_rp="$1"
  _cx_hops=0
  while [ -L "$_cx_rp" ]; do
    _cx_hops=$((_cx_hops+1))
    [ "$_cx_hops" -le 40 ] || cx_die "too many symlinks: $1"
    _cx_rt="$(readlink "$_cx_rp")"
    case "$_cx_rt" in
      /*) _cx_rp="$_cx_rt" ;;
      *) _cx_rp="$(dirname "$_cx_rp")/$_cx_rt" ;;
    esac
  done
  _cx_rd="$(CDPATH= cd -P "$(dirname "$_cx_rp")" 2>/dev/null && pwd -P)" || return 1
  printf '%s/%s\n' "$_cx_rd" "$(basename "$_cx_rp")"
}

cx_init() {
  case "${HOME-}" in /*[!/.]*) ;; *) cx_die "HOME must be an absolute path other than / (it is '${HOME-}')" ;; esac
  _cx_p="$(cx_resolve "$1")" || exit 1
  _cx_d="$(dirname "$_cx_p")"
  CX_TREE="$(dirname "$_cx_d")"
  CX_MG="$(dirname "$CX_TREE")"
  CX_HOME="${CODEX_HOME:-$HOME/.codex}"
  case "$CX_HOME" in
    /*) ;;
    *) cx_die "CODEX_HOME must be an absolute path (it is '$CX_HOME')" ;;
  esac
  while :; do case "$CX_HOME" in ?*/) CX_HOME="${CX_HOME%/}" ;; *) break ;; esac; done
  CX_ROOT="$CX_HOME/packages/standalone"
  CX_STATE="$HOME/Library/Application Support/dev.mavergreen.codex-cli"
}

# prints the user's Codex only when its current release is a Mavergreen build; OpenAI's own build
# under the same root would not run on this system
cx_runnable() {
  [ -f "$CX_ROOT/current/bin/codex" ] && [ -x "$CX_ROOT/current/bin/codex" ] || return 1
  grep -q '"mavergreenBuild"' "$CX_ROOT/current/codex-package.json" 2>/dev/null || return 1
  printf '%s\n' "$CX_ROOT/current/bin/codex"
}

# the installer takes its own lock, so launches that seed together serialize and the later ones find the build in place;
# a first run never opens the package's updater (CODEX_INSTALL_NO_UPDATER): it was not what the user asked for
cx_seed() {
  cx_note "installing Codex (first run; this downloads Codex and can take a minute)"
  CODEX_PKG_ROOT="${CODEX_PKG_ROOT:-$CX_TREE}"
  export CODEX_PKG_ROOT
  _cx_out="$(CODEX_NON_INTERACTIVE=1 CODEX_INSTALL_NO_UPDATER=1 /bin/sh "$CX_TREE/libexec/codex-cli/install.sh" 2>&1 </dev/null)" || {
    cx_die "could not install Codex: $(printf '%s\n' "$_cx_out" | tail -n 1)"
  }
  [ -z "$_cx_out" ] || printf '%s\n' "$_cx_out" >&2
  return 0
}

# Codex's HTTPS on 10.9 is native-tls through Wowfunhappy's AquaTransport, and only a release at least
# as new as the pin has the TLS fixes native-tls needs. A pin of "unreleased" means this package was
# built before such a release existed. CODEX_AQUATRANSPORT_VERSION stands in
# for the receipt in tests (empty means no receipt); otherwise one pkgutil call reads it.
cx_require_aquatransport() {
  _cx_url=https://mavericksforever.com/downloads/AquaTransport.dmg
  _cx_pf="$CX_TREE/share/codex-cli/aquatransport-min-version"
  [ -f "$_cx_pf" ] || cx_die "missing $_cx_pf"
  _cx_min="$(tr -d '[:space:]' < "$_cx_pf")"
  [ "$_cx_min" != unreleased ] || cx_die "this codex-cli package needs an AquaTransport release that does not exist yet"
  cx_is_date "$_cx_min" || cx_die "the AquaTransport minimum '$_cx_min' in $_cx_pf is not YYYY.MM.DD or unreleased"
  if [ "${CODEX_AQUATRANSPORT_VERSION+set}" = set ]; then
    _cx_have="$CODEX_AQUATRANSPORT_VERSION"
  else
    _cx_have="$(pkgutil --pkg-info Wowfunhappy.AquaTransport 2>/dev/null | sed -n 's/^version: *//p' | head -n 1)"
  fi
  [ -n "$_cx_have" ] || cx_die "AquaTransport is not installed; Codex needs it for TLS on this Mac. Get it from $_cx_url"
  cx_is_date "$_cx_have" || cx_die "AquaTransport version '$_cx_have' is not YYYY.MM.DD"
  # YYYYMMDD with the dots dropped orders the same as the fields compared one by one
  if [ "$(printf %s "$_cx_have" | tr -d .)" -lt "$(printf %s "$_cx_min" | tr -d .)" ]; then
    cx_die "AquaTransport $_cx_have is too old; Codex needs $_cx_min or newer. Get it from $_cx_url"
  fi
}

cx_is_date() {
  case "$1" in
    [0-9][0-9][0-9][0-9].[0-9][0-9].[0-9][0-9]) return 0 ;;
    *) return 1 ;;
  esac
}
