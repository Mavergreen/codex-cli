#!/bin/sh
# platform: macOS-only -- the launcher exists to run Codex on Mac OS X 10.9

cx_claim_link() {
  CX_LINK="$HOME/.local/bin/codex"
  _cx_want="$CX_MG/bin/codex"
  if [ -L "$CX_LINK" ]; then
    _cx_a="$(cx_resolve "$CX_LINK" 2>/dev/null)" || _cx_a=""
    _cx_b="$(cx_resolve "$_cx_want" 2>/dev/null)" || _cx_b=""
    if [ -n "$_cx_a" ] && [ "$_cx_a" = "$_cx_b" ]; then
      return 0
    fi
    case "$(readlink "$CX_LINK")" in
      */packages/standalone/*) ;;
      *) cx_foreign_link; return 0 ;;
    esac
  elif [ -e "$CX_LINK" ]; then
    cx_foreign_link
    return 0
  fi
  mkdir -p "$(dirname "$CX_LINK")"
  _cx_tmp="$(mktemp -u "$(dirname "$CX_LINK")/.codex-link.XXXXXX")"
  ln -s "$_cx_want" "$_cx_tmp"
  if ! perl -e 'rename($ARGV[0],$ARGV[1]) or die "$!\n"' "$_cx_tmp" "$CX_LINK"; then
    rm -f "$_cx_tmp"
    return 1
  fi
}

cx_foreign_link() {
  [ -f "$CX_STATE/foreign-link" ] && return 0
  cx_note "$CX_LINK is not this launcher's and is left alone"
  mkdir -p "$CX_STATE"
  : > "$CX_STATE/foreign-link"
}
