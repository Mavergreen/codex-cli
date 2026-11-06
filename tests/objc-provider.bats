#!/usr/bin/env bats
# platform: macOS-only -- plutil reads the provider declaration, and shipyard's provider helper builds against the host SDK
# spec: build/fetch-recaulk-objc.sh header -- the Recaulk Objective-C provider the codex binary links is
#       either the pinned release, fetched and verified through shipyard's fetch_product_pkg.sh, or a
#       staged prefix named explicitly by CODEX_DEV_RECAULK_PREFIX, which is development-only. Both are
#       validated by shipyard's own declaration check (objc-provider-link-args.sh) and then for the one
#       provider Codex needs. There is no fallback to an installed Recaulk.
# The product runs from a scratch copy whose shipyard is the real one but for a stand-in
# fetch_product_pkg.sh, the network boundary. The provider is a small archive built here and declared
# in the shape Recaulk's build/build-objc.sh declares its own (tests/lib/objc-provider-fixture.sh);
# CODEX_TEST_RECAULK_PREFIX, when set, is a real staged Recaulk prefix that must pass too.
. "$BATS_TEST_DIRNAME/lib/objc-provider-fixture.sh"

setup() {
  export PRODUCT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  : "${SHIPYARD_SCRIPTS:?set SHIPYARD_SCRIPTS to the scripts of shipyard}"
  REAL_SHIPYARD=$SHIPYARD_SCRIPTS
  # platform: the build root stays the caller's: shipyard's helpers build and cache their analyzer
  #           there, and the stand-in fetch below writes nothing into it.
  product="$BATS_TEST_TMPDIR/product"
  shipyard="$BATS_TEST_TMPDIR/shipyard/scripts"
  calls="$BATS_TEST_TMPDIR/fetch-calls"
  mkdir -p "$product" "$shipyard"
  cp -R "$PRODUCT_ROOT/build" "$PRODUCT_ROOT/components" "$PRODUCT_ROOT/packaging" "$PRODUCT_ROOT/UPSTREAM_VERSION" "$product/"
  rm -f "$product/components/recaulk/version"
  # shipyard's helpers find their tools, pins and references beside scripts/, so the scratch
  # shipyard links every other top-level entry of the real one.
  for entry in "$REAL_SHIPYARD"/../*; do
    [ "$(basename "$entry")" = scripts ] || ln -s "$(cd "$entry" 2>/dev/null && pwd || echo "$entry")" "$shipyard/../"
  done
  for script in "$REAL_SHIPYARD"/*; do ln -s "$script" "$shipyard/"; done
  rm "$shipyard/fetch_product_pkg.sh"
  # The stand-in passes any other product (the analyzer's pinned toolchain) to the real script. For
  # recaulk it records its arguments and answers with FETCH_ANSWER (a prefix), or fails as a
  # release with no listed asset does.
  cat > "$shipyard/fetch_product_pkg.sh" <<EOF
#!/bin/sh
case "\$*" in recaulk\ *) ;; *) exec sh "$REAL_SHIPYARD/fetch_product_pkg.sh" "\$@" ;; esac
printf '%s\n' "\$*" >> "$calls"
[ -n "\${FETCH_ANSWER:-}" ] || { echo "fetch_product_pkg: recaulk-\$2.pkg is not listed (once) in SHA256SUMS" >&2; exit 1; }
printf '%s\n' "\$FETCH_ANSWER"
EOF
  chmod +x "$shipyard/fetch_product_pkg.sh"
  export SHIPYARD_SCRIPTS="$shipyard"
  unset CODEX_DEV_RECAULK_PREFIX FETCH_ANSWER
  sdk=$(sh "$REAL_SHIPYARD/fetch_sdk.sh" --arch x86_64)
}

fixture_prefix() { objc_fixture_prefix "$1" "$sdk"; }
mutate() { objc_fixture_mutate "$1" "$2"; }

fetch() { run sh "$product/build/fetch-recaulk-objc.sh"; }
# refused [WHY]: the helper itself refused (not a missing script or a shell error), saying WHY.
refused() {
  [ "$status" -ne 0 ] && [ "$status" -ne 127 ] && [[ "$output" == *"fetch-recaulk-objc: ${1:-}"* ]] && [[ "$output" != *"did not build"* ]] ||
    { echo "not refused for ${1:-any reason}: status $status: $output"; false; }
}

@test "an explicit development prefix is verified and printed with development origin" {
  fixture_prefix "$BATS_TEST_TMPDIR/staged"
  CODEX_DEV_RECAULK_PREFIX="$BATS_TEST_TMPDIR/staged" fetch
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # stdout is exactly the three lines a caller reads; everything else goes to stderr
  stdout=$(CODEX_DEV_RECAULK_PREFIX="$BATS_TEST_TMPDIR/staged" sh "$product/build/fetch-recaulk-objc.sh" 2>/dev/null)
  [ "$stdout" = "$BATS_TEST_TMPDIR/staged
development
development" ] || { echo "stdout: $stdout"; false; }
  [ ! -e "$calls" ]
}

@test "a development prefix stays development with a production pin and a BUILD_ID" {
  fixture_prefix "$BATS_TEST_TMPDIR/staged"
  mkdir -p "$product/components/recaulk"
  echo 20261201.1 > "$product/components/recaulk/version"
  echo 0.165.0-mavericks.7 > "$product/BUILD_ID"
  CODEX_DEV_RECAULK_PREFIX="$BATS_TEST_TMPDIR/staged" fetch
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | tail -2 | sed -n 1p)" = development ]
  [ ! -e "$calls" ]
}

@test "without a production pin or a development prefix nothing is fetched or borrowed from an installed Recaulk" {
  fetch
  refused "no components/recaulk/version"
  [[ "$output" == *"CODEX_DEV_RECAULK_PREFIX"* ]] || false
  [[ "$output" != *"/usr/local/mavergreen"* ]] || false
  [ ! -e "$calls" ]
}

@test "a pinned release is fetched through shipyard's verified product fetch and marked released" {
  fixture_prefix "$BATS_TEST_TMPDIR/released"
  mkdir -p "$product/components/recaulk"
  echo 20261201.1 > "$product/components/recaulk/version"
  FETCH_ANSWER="$BATS_TEST_TMPDIR/released" fetch
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  stdout=$(FETCH_ANSWER="$BATS_TEST_TMPDIR/released" sh "$product/build/fetch-recaulk-objc.sh" 2>/dev/null)
  [ "$stdout" = "$BATS_TEST_TMPDIR/released
released
20261201.1" ] || { echo "stdout: $stdout"; false; }
  grep -qx "recaulk 20261201.1 $(sh "$product/build/resolve-build-root.sh")/recaulk-20261201.1" "$calls"
}

@test "a release whose asset or checksum is missing fails" {
  mkdir -p "$product/components/recaulk"
  echo 20261201.1 > "$product/components/recaulk/version"
  fetch
  refused "could not fetch and verify Recaulk 20261201.1"
  [[ "$output" == *"not listed"* ]] || false
}

@test "a malformed production pin is refused before any fetch" {
  mkdir -p "$product/components/recaulk"
  echo 'latest' > "$product/components/recaulk/version"
  fetch
  refused "components/recaulk/version holds"
  [ ! -e "$calls" ]
}

@test "an archive whose bytes differ from the declared digest is refused" {
  fixture_prefix "$BATS_TEST_TMPDIR/staged"
  printf 'x' >> "$BATS_TEST_TMPDIR/staged/lib/librecaulk-objc.a"
  CODEX_DEV_RECAULK_PREFIX="$BATS_TEST_TMPDIR/staged" fetch
  refused "shipyard refused the provider declaration"
}

@test "a declaration digest that names other bytes is refused" {
  fixture_prefix "$BATS_TEST_TMPDIR/staged"
  mutate "$BATS_TEST_TMPDIR/staged" 's/"archive_sha256" : "[0-9a-f]*"/"archive_sha256" : "0000000000000000000000000000000000000000000000000000000000000000"/'
  CODEX_DEV_RECAULK_PREFIX="$BATS_TEST_TMPDIR/staged" fetch
  refused "shipyard refused the provider declaration"
}

@test "a native-test slice is refused" {
  fixture_prefix "$BATS_TEST_TMPDIR/staged"
  mutate "$BATS_TEST_TMPDIR/staged" 's/"artifact_role" : "shipping"/"artifact_role" : "native-test-only"/'
  CODEX_DEV_RECAULK_PREFIX="$BATS_TEST_TMPDIR/staged" fetch
  refused "shipyard refused the provider declaration"
}

@test "another architecture is refused" {
  fixture_prefix "$BATS_TEST_TMPDIR/staged"
  mutate "$BATS_TEST_TMPDIR/staged" 's/"architecture" : "x86_64"/"architecture" : "arm64"/'
  CODEX_DEV_RECAULK_PREFIX="$BATS_TEST_TMPDIR/staged" fetch
  refused "shipyard refused the provider declaration"
}

@test "another provider ID is refused" {
  fixture_prefix "$BATS_TEST_TMPDIR/staged"
  mutate "$BATS_TEST_TMPDIR/staged" 's/recaulk.nsworkspace.open-urls.v1/recaulk.nsworkspace.open-urls.v2/'
  CODEX_DEV_RECAULK_PREFIX="$BATS_TEST_TMPDIR/staged" fetch
  refused
  [[ "$output" == *"recaulk.nsworkspace.open-urls.v1"* ]] || false
}

@test "a wrong ABI is refused" {
  fixture_prefix "$BATS_TEST_TMPDIR/staged"
  mutate "$BATS_TEST_TMPDIR/staged" 's/"@56@0:8@16@24Q32@40^@48"/"@56@0:8@16@24I32@40^@48"/'
  CODEX_DEV_RECAULK_PREFIX="$BATS_TEST_TMPDIR/staged" fetch
  refused
}

@test "another selector, method kind or class is refused" {
  for expr in 's/"selector" : "openURLs:/"selector" : "openURL:/' \
              's/"method_kind" : "-"/"method_kind" : "+"/' \
              's/"class" : "NSWorkspace"/"class" : "NSApplication"/'; do
    rm -rf "$BATS_TEST_TMPDIR/staged" "$BATS_TEST_TMPDIR/staged.objects"
    fixture_prefix "$BATS_TEST_TMPDIR/staged"
    mutate "$BATS_TEST_TMPDIR/staged" "$expr"
    CODEX_DEV_RECAULK_PREFIX="$BATS_TEST_TMPDIR/staged" fetch
    refused || { echo "accepted after $expr"; false; }
  done
}

@test "a missing activation root is refused" {
  fixture_prefix "$BATS_TEST_TMPDIR/staged"
  mutate "$BATS_TEST_TMPDIR/staged" '/"activation_root"/d'
  CODEX_DEV_RECAULK_PREFIX="$BATS_TEST_TMPDIR/staged" fetch
  refused "shipyard refused the provider declaration"
}

@test "an old Recaulk without the provider declaration is refused, released or staged" {
  mkdir -p "$BATS_TEST_TMPDIR/old/lib"
  : > "$BATS_TEST_TMPDIR/old/lib/librecaulk.a"
  CODEX_DEV_RECAULK_PREFIX="$BATS_TEST_TMPDIR/old" fetch
  refused
  [[ "$output" == *"objc-providers.json"* ]] || false
  mkdir -p "$product/components/recaulk"
  echo 20261012.1 > "$product/components/recaulk/version"
  FETCH_ANSWER="$BATS_TEST_TMPDIR/old" fetch
  refused
  [[ "$output" == *"objc-providers.json"* ]] || false
}

@test "a relative or multi-line development prefix is refused" {
  fixture_prefix "$BATS_TEST_TMPDIR/staged"
  (cd "$BATS_TEST_TMPDIR" && CODEX_DEV_RECAULK_PREFIX=staged run sh "$product/build/fetch-recaulk-objc.sh"; refused "the Recaulk prefix must be an absolute path")
  CODEX_DEV_RECAULK_PREFIX="$BATS_TEST_TMPDIR/staged
/elsewhere" fetch
  refused "the Recaulk prefix holds a line break"
}

@test "a shipyard without the Objective-C provider interfaces is refused" {
  fixture_prefix "$BATS_TEST_TMPDIR/staged"
  for helper in objc-provider-link-args.sh objc-build-evidence.sh objc-compat.sh; do
    rm -rf "$shipyard.$helper"; cp -R "$shipyard" "$shipyard.$helper"; rm "$shipyard.$helper/$helper"
    SHIPYARD_SCRIPTS="$shipyard.$helper" CODEX_DEV_RECAULK_PREFIX="$BATS_TEST_TMPDIR/staged" fetch
    refused || { echo "accepted without $helper"; false; }
    [[ "$output" == *"$helper"* ]] || false
  done
}

@test "packaging refuses a build linked with a development provider, whatever its BUILD-ID" {
  out="$BATS_TEST_TMPDIR/codex-out"
  mkdir -p "$out"
  for f in codex codex-code-mode-host LICENSE NOTICE; do echo "$f" > "$out/$f"; done
  ver=$(sh "$product/build/codex-pin.sh" version)
  printf 'version=%s-mavericks.3\nmode=native\nrecaulk_origin=development\n' "$ver" > "$out/build-manifest"
  run sh "$product/packaging/build-codex-package.sh" "$out" "$ver-mavericks.3" "$BATS_TEST_TMPDIR/pkg"
  [ "$status" -ne 0 ]
  [[ "$output" == *"development"* ]] || false
  [ ! -e "$BATS_TEST_TMPDIR/pkg" ]
  printf 'version=%s-mavericks.3\nmode=native\n' "$ver" > "$out/build-manifest"
  run sh "$product/packaging/build-codex-package.sh" "$out" "$ver-mavericks.3" "$BATS_TEST_TMPDIR/pkg"
  [ "$status" -ne 0 ]
  [[ "$output" == *"recaulk_origin"* ]] || false
  printf 'version=%s-mavericks.3\nmode=native\nrecaulk_origin=released\n' "$ver" > "$out/build-manifest"
  run sh "$product/packaging/build-codex-package.sh" "$out" "$ver-mavericks.3" "$BATS_TEST_TMPDIR/pkg"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "a real staged Recaulk prefix passes" {
  [ -n "${CODEX_TEST_RECAULK_PREFIX:-}" ] || skip "CODEX_TEST_RECAULK_PREFIX names no staged Recaulk (Recaulk's build/build-objc.sh STAGE WORK)"
  CODEX_DEV_RECAULK_PREFIX="$CODEX_TEST_RECAULK_PREFIX" fetch
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | tail -2 | sed -n 1p)" = development ]
}

# ---- the build hook: patches/0014-explicit-recaulk-objc-linkage.patch on codex-rs/cli/build.rs ----
# spec: patches/README.md "0014" -- the provider's arguments reach the codex binary's link alone, and
#       only for an x86_64 macOS target; the hook is real Rust, compiled with the pinned toolchain.

# hook_source DIR: codex-rs/cli/build.rs as the pinned Codex has it, with 0014 applied, under DIR.
hook_source() {
  mkdir -p "$1/codex-rs/cli"
  printf '%s\n' 'fn main() {' \
    '    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("macos") {' \
    '        println!("cargo:rustc-link-arg=-ObjC");' \
    '    }' '}' > "$1/codex-rs/cli/build.rs"
  (cd "$1" && git apply "$PRODUCT_ROOT/patches/0014-explicit-recaulk-objc-linkage.patch")
}

# hook_args: the staged fixture provider under a path with a space, and shipyard's linker arguments
# for it in $args (MAVERICKS_OBJC_LINK_ARGS_FILE), its link map beside it.
hook_args() {
  spaced="$BATS_TEST_TMPDIR/sp ace"
  fixture_prefix "$spaced/staged"
  args="$spaced/link-args"
  sh "$SHIPYARD_SCRIPTS/objc-provider-link-args.sh" --prefix "$spaced/staged" --link-map "$spaced/codex.map" > "$args"
  [ "$(sed -n 1p "$args")" = "$(cd -P "$spaced/staged" && pwd)/lib/librecaulk-objc.a" ]
}

rust_toolchain() { rust=${CODEX_TEST_RUST_PREFIX:-$(sh "$product/build/fetch-rust.sh")}; [ -x "$rust/bin/cargo" ]; }

# hook_workspace: a Cargo workspace shaped as codex-rs where it matters: codex-cli (the hook, the
# codex and logs_client binaries, a proc-macro dependency) and codex-code-mode-host. Its x86_64
# linker records each link's arguments in $links/NAME.args (and a line per link in $links/calls)
# and writes an empty output; host links (build scripts, the proc macro) go on to cc.
hook_workspace() {
  ws="$BATS_TEST_TMPDIR/ws"
  hook_source "$ws"
  mkdir -p "$ws/codex-rs/cli/src/bin" "$ws/codex-rs/code-mode-host/src" "$ws/codex-rs/pm/src"
  printf '[workspace]\nmembers = ["cli", "code-mode-host", "pm"]\nresolver = "2"\n' > "$ws/codex-rs/Cargo.toml"
  printf '[package]\nname = "codex-cli"\nversion = "0.0.0"\nedition = "2024"\nbuild = "build.rs"\n\n[[bin]]\nname = "codex"\npath = "src/main.rs"\n\n[[bin]]\nname = "logs_client"\npath = "src/bin/logs_client.rs"\n\n[dependencies]\npm = { path = "../pm" }\n' > "$ws/codex-rs/cli/Cargo.toml"
  printf 'pm::noop!();\nfn main() {}\n' > "$ws/codex-rs/cli/src/main.rs"
  printf 'fn main() {}\n' > "$ws/codex-rs/cli/src/bin/logs_client.rs"
  printf '[package]\nname = "codex-code-mode-host"\nversion = "0.0.0"\nedition = "2024"\n' > "$ws/codex-rs/code-mode-host/Cargo.toml"
  printf 'fn main() {}\n' > "$ws/codex-rs/code-mode-host/src/main.rs"
  printf '[package]\nname = "pm"\nversion = "0.0.0"\nedition = "2024"\n\n[lib]\nproc-macro = true\n' > "$ws/codex-rs/pm/Cargo.toml"
  printf 'use proc_macro::TokenStream;\n#[proc_macro]\npub fn noop(_: TokenStream) -> TokenStream { TokenStream::new() }\n' > "$ws/codex-rs/pm/src/lib.rs"
  links="$BATS_TEST_TMPDIR/links"
  mkdir -p "$links"
  # platform: named *-cc, not *-ld: rustc picks the linker flavor from the name.
  cat > "$BATS_TEST_TMPDIR/record-cc" <<EOF
#!/bin/sh
out=; prev=
for a in "\$@"; do [ "\$prev" != -o ] || out=\$a; prev=\$a; done
name=\$(basename "\$out")
case "\${name##*-}" in ????????????????) name=\${name%-*} ;; esac
printf '%s\n' "\$@" > "$links/\$name.args"
printf '%s\n' "\$name" >> "$links/calls"
case "\$out" in
  */x86_64-apple-darwin/*) : > "\$out"; chmod +x "\$out" ;;
  *) exec cc "\$@" ;;
esac
EOF
  chmod +x "$BATS_TEST_TMPDIR/record-cc"
}

cargo_build() {
  (cd "$ws/codex-rs" && PATH="$rust/bin:$PATH" CARGO_TARGET_X86_64_APPLE_DARWIN_LINKER="$BATS_TEST_TMPDIR/record-cc" \
    CARGO_TARGET_DIR="$ws/target" CARGO_HOME="$BATS_TEST_TMPDIR/cargo-home" CARGO_NET_OFFLINE=true \
    CARGO_PROFILE_RELEASE_DEBUG=false MACOSX_DEPLOYMENT_TARGET=10.9 \
    "$rust/bin/cargo" build --release --target x86_64-apple-darwin --workspace)
}
links_of() { grep -cx "$1" "$links/calls" || true; }

@test "the hook gives the provider's arguments to the codex binary's link alone, in order, beside -ObjC" {
  rust_toolchain
  hook_args
  hook_workspace
  MAVERICKS_OBJC_LINK_ARGS_FILE="$args" run cargo_build
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$(cat "$links/codex.args")" == *"$(cat "$args")"* ]] || { cat "$links/codex.args"; false; }
  grep -qx -- -ObjC "$links/codex.args"
  grep -qx -- -ObjC "$links/logs_client.args"
  for f in "$links"/*.args; do
    [ "$f" = "$links/codex.args" ] && continue
    ! grep -qF "librecaulk-objc.a" "$f" || { echo "$f has the provider"; false; }
    ! grep -qF "___recaulk_objc_activate" "$f" || { echo "$f has the root"; false; }
  done
  [ -f "$links/codex_code_mode_host.args" ]
}

@test "an unchanged rebuild does not relink codex; a changed archive or archive digest does" {
  rust_toolchain
  hook_args
  hook_workspace
  export MAVERICKS_OBJC_LINK_ARGS_FILE="$args" MAVERICKS_OBJC_PROVIDER_ARCHIVE_SHA256=one
  run cargo_build; [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(links_of codex)" -eq 1 ]
  run cargo_build; [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(links_of codex)" -eq 1 ]
  sleep 1
  printf 'x' >> "$spaced/staged/lib/librecaulk-objc.a"
  run cargo_build; [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(links_of codex)" -eq 2 ]
  MAVERICKS_OBJC_PROVIDER_ARCHIVE_SHA256=two run cargo_build; [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(links_of codex)" -eq 3 ]
  [ "$(links_of codex_code_mode_host)" -eq 1 ]
}

@test "an x86_64 macOS build without the args file fails and names the official wrappers" {
  rust_toolchain
  hook_workspace
  unset MAVERICKS_OBJC_LINK_ARGS_FILE
  run cargo_build
  [ "$status" -ne 0 ]
  [[ "$output" == *"MAVERICKS_OBJC_LINK_ARGS_FILE is not set"* ]] || false
  [[ "$output" == *"build/build-codex.sh"* ]] || false
  [[ "$output" == *"build/cargo-dev.sh"* ]] || false
  [ ! -e "$links/codex.args" ]
}

# hook_binary: the patched build.rs compiled for this host, to run with chosen Cargo variables.
hook_binary() {
  hook_source "$BATS_TEST_TMPDIR/hook"
  "$rust/bin/rustc" --edition 2024 -o "$BATS_TEST_TMPDIR/hook/build-script" "$BATS_TEST_TMPDIR/hook/codex-rs/cli/build.rs"
}

@test "the hook decides by the target, not the host: no provider arguments for another target" {
  rust_toolchain
  hook_binary
  for target in macos:aarch64 linux:x86_64 ios:x86_64; do
    CARGO_CFG_TARGET_OS=${target%:*} CARGO_CFG_TARGET_ARCH=${target#*:} MAVERICKS_OBJC_LINK_ARGS_FILE=/nonexistent \
      run "$BATS_TEST_TMPDIR/hook/build-script"
    [ "$status" -eq 0 ] || { echo "$target: $output"; false; }
    [[ "$output" != *"rustc-link-arg-bin"* ]] || { echo "$target: $output"; false; }
  done
  CARGO_CFG_TARGET_OS=macos CARGO_CFG_TARGET_ARCH=aarch64 run "$BATS_TEST_TMPDIR/hook/build-script"
  [[ "$output" == *"cargo:rustc-link-arg=-ObjC"* ]] || false
}

@test "the hook refuses an args file that does not start with an existing archive, or holds an empty line" {
  rust_toolchain
  hook_binary
  hook_args
  for bad in "$BATS_TEST_TMPDIR/sp ace/staged/lib/missing.a" "relative/librecaulk-objc.a" "-Wl,-u,___recaulk_objc_activate"; do
    { printf '%s\n' "$bad"; sed 1d "$args"; } > "$BATS_TEST_TMPDIR/bad-args"
    CARGO_CFG_TARGET_OS=macos CARGO_CFG_TARGET_ARCH=x86_64 MAVERICKS_OBJC_LINK_ARGS_FILE="$BATS_TEST_TMPDIR/bad-args" \
      run "$BATS_TEST_TMPDIR/hook/build-script"
    [ "$status" -ne 0 ] || { echo "accepted $bad"; false; }
    [[ "$output" != *"rustc-link-arg-bin"* ]] || false
  done
  { cat "$args"; echo; echo -ObjC; } > "$BATS_TEST_TMPDIR/bad-args"
  CARGO_CFG_TARGET_OS=macos CARGO_CFG_TARGET_ARCH=x86_64 MAVERICKS_OBJC_LINK_ARGS_FILE="$BATS_TEST_TMPDIR/bad-args" \
    run "$BATS_TEST_TMPDIR/hook/build-script"
  [ "$status" -ne 0 ]
}

@test "the provider stays rooted through -dead_strip and consumer LTO" {
  hook_args
  set --
  while IFS= read -r line; do set -- "$@" "$line"; done < "$args"
  printf 'int main(void) { return 0; }\n' > "$BATS_TEST_TMPDIR/consumer.c"
  for flags in "-O2" "-O2 -Wl,-dead_strip" "-O2 -flto -Wl,-dead_strip"; do
    env -i PATH=/usr/bin:/bin /usr/bin/clang -arch x86_64 -isysroot "$sdk" -mmacosx-version-min=10.9 $flags \
      "$BATS_TEST_TMPDIR/consumer.c" "$@" -o "$BATS_TEST_TMPDIR/consumer"
    nm "$BATS_TEST_TMPDIR/consumer" | grep -q ' T ___recaulk_objc_activate$' || { echo "$flags lost the root"; false; }
    nm "$BATS_TEST_TMPDIR/consumer" | grep -q ' T ___recaulk_objc_workspace_open_urls$' || { echo "$flags lost the implementation"; false; }
    otool -L "$BATS_TEST_TMPDIR/consumer" | grep -q '/AppKit.framework/' || { echo "$flags lost AppKit"; false; }
    [ -s "$spaced/codex.map" ]
  done
}
