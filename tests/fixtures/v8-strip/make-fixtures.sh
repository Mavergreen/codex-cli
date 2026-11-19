#!/bin/sh
# platform: host-agnostic -- clang22 and llvm-ar only; regenerates the committed fixture archives
#   usage: [CLANG=<clang22>] [AR=<llvm-ar>] make-fixtures.sh
#          Writes good.a, missing.a, extra.a and twice.a beside itself: stand-ins for OpenAI's rusty_v8
#          archive whose libc++abi members each define one C++ runtime symbol, plus v8code.pic.o.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CLANG=${CLANG:-/usr/local/mavergreen/clang22/bin/clang}
AR=${AR:-/usr/local/mavergreen/clang22/bin/llvm-ar}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/v8-strip.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

member() {
  printf '%s\n' "$2" > "$WORK/$1.c"
  "$CLANG" --no-default-config --target=x86_64-apple-macos10.9 -c -o "$WORK/$1.pic.o" "$WORK/$1.c"
}

ABI="abort_message cxa_aux_runtime cxa_default_handlers cxa_demangle cxa_exception cxa_exception_storage
cxa_guard cxa_handlers cxa_personality cxa_vector cxa_virtual fallback_malloc private_typeinfo
stdlib_exception stdlib_stdexcept stdlib_typeinfo"
for m in $ABI; do
  member "$m" "void __cxa_fixture_$m(void) {}"
done
member v8code 'void v8_fixture_entry(void) {}'
member cxa_thread_atexit 'void __cxa_thread_atexit(void) {}'

cd "$WORK"
pic() { for m in "$@"; do printf '%s.pic.o ' "$m"; done; }
build() { out=$1; shift; rm -f "$HERE/$out"; "$AR" rcsD "$HERE/$out" "$@"; }
# shellcheck disable=SC2046
build good.a $(pic $ABI v8code)
# shellcheck disable=SC2046
build missing.a $(pic $(printf '%s\n' $ABI | grep -v '^cxa_guard$') v8code)
# shellcheck disable=SC2046
build extra.a $(pic $ABI v8code cxa_thread_atexit)
# shellcheck disable=SC2046
build twice.a $(pic $ABI v8code cxa_vector)
