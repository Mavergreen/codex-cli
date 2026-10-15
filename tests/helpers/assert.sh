# platform: host-agnostic
_a_n=0
_a_tmps=""
_a_fail() { echo "not ok $_a_n - $1" >&2; exit 1; }
a_eq() {
  _a_n=$((_a_n + 1))
  [ "$1" = "$2" ] || _a_fail "$3 (expected '$1', got '$2')"
}
a_contains() {
  _a_n=$((_a_n + 1))
  case "$1" in *"$2"*) ;; *) _a_fail "$3 ('$2' not in '$1')" ;; esac
}
a_fails() {
  _a_n=$((_a_n + 1))
  _a_msg="$1"; shift
  if "$@" >/dev/null 2>&1; then _a_fail "$_a_msg (command succeeded)"; fi
}
a_file_exists() { _a_n=$((_a_n + 1)); [ -e "$2" ] || _a_fail "$1 ($2 missing)"; }
a_no_file() { _a_n=$((_a_n + 1)); [ ! -e "$2" ] || _a_fail "$1 ($2 exists)"; }
a_done() { echo "ok $_a_n"; }
_a_cleanup() { [ -z "$_a_tmps" ] || rm -rf $_a_tmps; }
trap _a_cleanup EXIT
t_tmp() {
  [ $# -eq 1 ] || { echo "t_tmp: usage: t_tmp VAR  (sets VAR to a fresh dir removed at exit; never call it in \$(...))" >&2; exit 2; }
  _t_d="$(mktemp -d "${TMPDIR:-/tmp}/codex-cli-test.XXXXXX")" || return 1
  _a_tmps="$_a_tmps $_t_d"
  eval "$1=\$_t_d"
}
