#!/bin/sh
# platform: host-agnostic -- plain sh, awk and perl's core JSON::PP over fixtures
# spec: build/check-crate-pins.sh header -- a crate: citation is hashed in the crate sources by the
#       NAME-VERSION its reviewed crates[] entry names, so every registry crate a reviewed file pins
#       must be the one Cargo.lock locked: same name, version and checksum, from crates.io.
#   usage: sh tests/crate-pins-test.sh
set -eu
. "$(dirname "$0")/lib/harness.sh"
h_setup
C="$H_REPO/build/check-crate-pins.sh"
A=$(printf a%.0s $(seq 64)); B=$(printf b%.0s $(seq 64))
cat > "$H/Cargo.lock" <<EOF
version = 4

[[package]]
name = "objc2-foundation"
version = "0.3.2"
source = "registry+https://github.com/rust-lang/crates.io-index"
checksum = "$A"

[[package]]
name = "codex-tui"
version = "0.165.0"

[[package]]
name = "crossterm"
version = "0.28.1"
source = "git+https://github.com/nornagon/crossterm?branch=x#0123"
EOF
ev() { printf '{"schema": 2, "kind": "objc-build-evidence", "crates": [%s]}\n' "$1" > "$H/ev.json"; }
check() { rc=0; out=$(sh "$C" "$H/ev.json" "$H/Cargo.lock" 2>&1) || rc=$?; }

ev "{\"name\": \"objc2_foundation\", \"version\": \"0.3.2\", \"checksum\": \"$A\"}, {\"name\": \"codex_tui\", \"version\": \"0.165.0\"}"
check
h_assert_eq 0 "$rc" "a pin Cargo.lock locked, by its underscored crate name, passes; a workspace crate (no checksum) is not a registry pin ($out)"

ev "{\"name\": \"objc2_foundation\", \"version\": \"0.3.1\", \"checksum\": \"$A\"}"
check
h_assert_eq 1 "$rc" "a pinned version Cargo.lock did not lock is refused"
h_assert_contains "$out" "objc2_foundation 0.3.1" "it names the pin"

ev "{\"name\": \"objc2_foundation\", \"version\": \"0.3.2\", \"checksum\": \"$B\"}"
check
h_assert_eq 1 "$rc" "a pinned checksum Cargo.lock did not lock is refused"

ev "{\"name\": \"crossterm\", \"version\": \"0.28.1\", \"checksum\": \"$A\"}"
check
h_assert_eq 1 "$rc" "a pin of a crate Cargo.lock takes from git, not crates.io, is refused"

ev "{\"name\": \"objc2\", \"version\": \"0.6.3\", \"checksum\": \"$A\"}"
check
h_assert_eq 1 "$rc" "a pin of a crate Cargo.lock does not lock at all is refused"

h_assert_contains "$(cat "$H_REPO/build/objc-build-evidence.sh")" 'check-crate-pins.sh" "$r" "$SOURCE/codex-rs/Cargo.lock"' \
  "the proof checks every reviewed file's pins against the build's Cargo.lock"
rc=0; sh "$C" "$H/ev.json" >/dev/null 2>&1 || rc=$?
h_assert_eq 2 "$rc" "a missing argument is a usage error"
h_done
