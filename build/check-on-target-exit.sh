#!/bin/sh
# platform: host-agnostic -- CI runs it; with --version it fetches nothing
#   usage: check-on-target-exit.sh [--version v0.YYYYMMDD.N]
#          INGREDIENTS.md's on-target deviation lasts until mavericks-vm@v1 carries
#          packer-plugin-macosx v0.20261005.9, the first with Aqua Transport 2026.10.25. Reads that
#          pin from mavericks-vm@v1 (or takes it from --version) and fails once it is there, so the
#          deviation cannot outlive its reason. Exit 0 while it is older, 1 once it is not, 2 on a
#          malformed version.
set -eu
EXIT=v0.20261005.9
case "$#:${1-}" in
  2:--version) v=$2 ;;
  0:) v=$(curl -fsSL --proto-redir =https --connect-timeout 20 --max-time 60 \
            https://raw.githubusercontent.com/Mavergreen/mavericks-vm/v1/components/packer-plugin-macosx/version | tr -d '[:space:]') ;;
  *) echo "usage: check-on-target-exit.sh [--version v0.YYYYMMDD.N]" >&2; exit 2 ;;
esac
# key VERSION: prints YYYYMMDD and N, or fails on anything but v0.YYYYMMDD.N
key() {
  case "$1" in
    v0.[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9].[0-9]*) ;;
    *) return 1 ;;
  esac
  _n=${1#v0.????????.}
  case "$_n" in *[!0-9]*) return 1 ;; esac
  _d=${1#v0.}; _d=${_d%%.*}
  echo "$_d $_n"
}
k=$(key "$v") || { echo "check-on-target-exit: '$v' is not v0.YYYYMMDD.N"; exit 2; }
set -- $k $(key "$EXIT")
if [ "$1" -lt "$3" ] || { [ "$1" -eq "$3" ] && [ "$2" -lt "$4" ]; }; then
  echo "check-on-target-exit: mavericks-vm@v1 has packer-plugin-macosx $v, older than $EXIT; publish still does not need on-mavericks"
  exit 0
fi
echo "check-on-target-exit: mavericks-vm@v1 has packer-plugin-macosx $v, which carries Aqua Transport 2026.10.25: make publish need on-mavericks and builds-on-mavericks again, require them on main, and remove this check and INGREDIENTS.md's on-target deviation"
exit 1
