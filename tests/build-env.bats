#!/usr/bin/env bats
# platform: macOS-only -- the stand-in libcxx22 dylibs are compiled with cc

# build-codex.sh runs in a scratch copy of the product whose fetch scripts are stand-ins, against a
# scratch shipyard whose mode and SDK are the test's. Its cargo is a stand-in that records the
# environment it was given and writes empty binaries, so each test sees what the real cargo would.
# The Objective-C provider is a fixture prefix (tests/lib/objc-provider-fixture.sh) that a stand-in
# fetch_product_pkg.sh answers for the release pinned in components/recaulk/version; shipyard's own
# provider helpers run for real, with the caller's PATH and build root, outside the stand-ins.
. "$BATS_TEST_DIRNAME/lib/objc-provider-fixture.sh"

setup() {
  export PRODUCT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export SHIPYARD_SCRIPTS="${SHIPYARD_SCRIPTS:-/home/schmonz/Documents/trees/mavergreen-shipyard/scripts}"
  real_shipyard=$SHIPYARD_SCRIPTS
  outer_root=${MAVERICKS_BUILD_ROOT:-${TMPDIR:-/tmp}/mm-build}
  outer_path=$PATH
  export MAVERICKS_BUILD_ROOT="$BATS_TEST_TMPDIR/local-build"
  unset CODEX_DEV_RECAULK_PREFIX MAVERICKS_OBJC_LINK_ARGS_FILE MAVERICKS_OBJC_PROVIDER_ARCHIVE_SHA256
  export MAVERICKS_TAGS=""
  stand_ins="$BATS_TEST_TMPDIR/stand-ins"
  product="$BATS_TEST_TMPDIR/product"
  shipyard="$BATS_TEST_TMPDIR/shipyard"
  sdk="$BATS_TEST_TMPDIR/sdk/MacOSX10.9.sdk"
  cargo_env="$BATS_TEST_TMPDIR/cargo-env"
  mkdir -p "$stand_ins" "$product" "$shipyard" "$sdk/usr/include"
  cp -R "$PRODUCT_ROOT/build" "$PRODUCT_ROOT/components" "$PRODUCT_ROOT/UPSTREAM_VERSION" "$product/"
  for script in "$SHIPYARD_SCRIPTS"/*; do ln -s "$script" "$shipyard/"; done
  rm "$shipyard/mavericks_mode.sh" "$shipyard/fetch_sdk.sh"
  printf '#!/bin/sh\necho "$MODE_FOR_TEST"\n' > "$shipyard/mavericks_mode.sh"
  printf '#!/bin/sh\necho "%s"\n' "$sdk" > "$shipyard/fetch_sdk.sh"
  for helper in objc-provider-link-args.sh objc-build-evidence.sh objc-compat.sh; do
    rm "$shipyard/$helper"
    printf '#!/bin/sh\nPATH="%s" MAVERICKS_BUILD_ROOT="%s" exec sh "%s" "$@"\n' "$outer_path" "$outer_root" "$real_shipyard/$helper" \
      > "$shipyard/$helper"
  done
  rm "$shipyard/fetch_product_pkg.sh"
  provider="$BATS_TEST_TMPDIR/recaulk-release"
  objc_fixture_prefix "$provider" "$(sh "$real_shipyard/fetch_sdk.sh" --arch x86_64)"
  printf '#!/bin/sh\n[ "$1" = recaulk ] || exit 9\necho "$*" >> "%s"\necho "%s"\n' "$BATS_TEST_TMPDIR/recaulk-fetches" "$provider" \
    > "$shipyard/fetch_product_pkg.sh"
  mkdir -p "$product/components/recaulk"
  echo 20261201.1 > "$product/components/recaulk/version"
  export SHIPYARD_SCRIPTS="$shipyard"

  source_dir="$BATS_TEST_TMPDIR/codex-src"
  mkdir -p "$source_dir/codex-rs"
  printf '[toolchain]\nchannel = "1.95.0"\n' > "$source_dir/codex-rs/rust-toolchain.toml"
  echo "Apache License" > "$source_dir/LICENSE"
  echo "Copyright OpenAI" > "$source_dir/NOTICE"
  printf '#!/bin/sh\necho "%s"\n' "$source_dir" > "$product/build/fetch-codex.sh"

  rust="$BATS_TEST_TMPDIR/rust"
  mkdir -p "$rust/bin"
  cat > "$rust/bin/cargo" <<EOF
#!/bin/sh
env > "$cargo_env"
mkdir -p "\$CARGO_TARGET_DIR/x86_64-apple-darwin/release"
: > "\$CARGO_TARGET_DIR/x86_64-apple-darwin/release/codex"
: > "\$CARGO_TARGET_DIR/x86_64-apple-darwin/release/codex-code-mode-host"
EOF
  printf '#!/bin/sh\n' > "$rust/bin/rustc"
  chmod +x "$rust/bin/cargo" "$rust/bin/rustc"
  printf '#!/bin/sh\necho "%s"\n' "$rust" > "$product/build/fetch-rust.sh"

  # clang22 and clang22-cross get compilers and, as their pkgs carry it, an SDKs that links to a
  # ../sdk109/SDKs nothing extracted, for build-codex.sh to link the SDK into; libcxx22 gets the
  # two dylibs the native cargo runs with inserted.
  for product_name in clang22 clang22-cross libcxx22; do
    mkdir -p "$BATS_TEST_TMPDIR/clang/$product_name/bin" "$BATS_TEST_TMPDIR/clang/$product_name/lib"
    ln -s ../sdk109/SDKs "$BATS_TEST_TMPDIR/clang/$product_name/SDKs"
    printf '#!/bin/sh\n' > "$BATS_TEST_TMPDIR/clang/$product_name/bin/clang"
    printf '#!/bin/sh\n' > "$BATS_TEST_TMPDIR/clang/$product_name/bin/clang++"
    chmod +x "$BATS_TEST_TMPDIR/clang/$product_name/bin/clang" "$BATS_TEST_TMPDIR/clang/$product_name/bin/clang++"
  done
  # platform: DYLD_LIBRARY_PATH matches by leaf name, so the inserted libc++ also answers for 10.9's
  #           /usr/lib/libc++.1.dylib and must be a real one: 10.9's own, copied. A modern Mac keeps
  #           its libc++ only in the dyld shared cache, so the stand-in is compiled by cc. Where SIP
  #           is on, dyld ignores DYLD_* in the protected /usr/bin/env and it is never loaded; on
  #           GitHub's macOS runners SIP is off, and it is inserted into env and mkdir, which are
  #           arm64e, and into any arm64 tool, so it carries both slices.
  printf 'void stand_in(void) {}\n' > "$BATS_TEST_TMPDIR/empty.c"
  for pair in libc++abi.dylib:libc++abi.1.dylib libc++.1.dylib:libc++.1.dylib; do
    cp "/usr/lib/${pair%%:*}" "$BATS_TEST_TMPDIR/clang/libcxx22/lib/${pair#*:}" 2>/dev/null ||
      cc -dynamiclib -arch arm64 -arch arm64e -o "$BATS_TEST_TMPDIR/clang/libcxx22/lib/${pair#*:}" "$BATS_TEST_TMPDIR/empty.c"
  done
  printf '#!/bin/sh\necho "%s/$1"\n' "$BATS_TEST_TMPDIR/clang" > "$product/build/fetch-clang-22.sh"

  v8="$BATS_TEST_TMPDIR/v8/rusty-v8-150.4.0"
  mkdir -p "$v8"
  : > "$v8/librusty_v8.a.gz"
  : > "$v8/src_binding.rs"
  printf '#!/bin/sh\nprintf "%%s\\n%%s\\n" "%s" "%s"\n' "$v8/librusty_v8.a.gz" "$v8/src_binding.rs" \
    > "$product/build/fetch-rusty-v8.sh"

  # uname -m answers arm64, as a cross host would; everything else is the host's own uname.
  mkdir -p "$stand_ins/bin"
  printf '#!/bin/sh\n[ "$1" = -m ] && { echo arm64; exit 0; }\nexec /usr/bin/uname "$@"\n' \
    > "$stand_ins/bin/uname"
  chmod +x "$stand_ins/bin/uname"
}

# cargo_lacks VAR: the stand-in cargo ran without VAR. A bare `! grep` cannot fail a bats test:
# set -e ignores a pipeline that starts with !.
cargo_lacks() { ! grep -q "^$1=" "$cargo_env"; }

# succeeded: the build exited 0, or the test fails showing what it printed, which bats would not.
succeeded() { [ "$status" -eq 0 ] || { printf '%s\n' "$output"; false; }; }

build() {
  MODE_FOR_TEST=$1 PATH="$stand_ins/bin:$PATH" sh "$product/build/build-codex.sh" "$1"
}

@test "a cross build hands the SDK to the target's links alone, and no SDKROOT to cargo" {
  SDKROOT=/elsewhere RUSTFLAGS=-Cfoo CARGO_ENCODED_RUSTFLAGS=-Cbar run build cross
  succeeded
  [ "${lines[${#lines[@]}-1]}" = "$(cd -P "$MAVERICKS_BUILD_ROOT" && pwd)/codex-cross" ]
  cargo_lacks SDKROOT
  cargo_lacks RUSTFLAGS
  cargo_lacks CARGO_ENCODED_RUSTFLAGS
  grep -qx "CARGO_TARGET_X86_64_APPLE_DARWIN_RUSTFLAGS=-C link-arg=-isysroot -C link-arg=$sdk" "$cargo_env"
  grep -qx "CC_x86_64_apple_darwin=$BATS_TEST_TMPDIR/clang/clang22-cross/bin/clang" "$cargo_env"
  [ "$(readlink "$BATS_TEST_TMPDIR/clang/clang22-cross/SDKs/MacOSX10.9.sdk")" = "$sdk" ]
}

@test "a native build keeps SDKROOT and sets no target rustflags" {
  SDKROOT=/elsewhere RUSTFLAGS=-Cfoo run build native
  succeeded
  grep -qx "SDKROOT=$sdk" "$cargo_env"
  cargo_lacks CARGO_TARGET_X86_64_APPLE_DARWIN_RUSTFLAGS
  cargo_lacks RUSTFLAGS
  grep -qx "CC_x86_64_apple_darwin=$BATS_TEST_TMPDIR/clang/clang22/bin/clang" "$cargo_env"
  grep -qx 'sdk=MacOSX10.9.sdk' "$(cd -P "$MAVERICKS_BUILD_ROOT" && pwd)/codex-native/build-manifest"
}

@test "a cross build refuses an SDK path that cargo would split" {
  spaced="$BATS_TEST_TMPDIR/sp ace/MacOSX10.9.sdk"
  mkdir -p "$spaced/usr/include"
  printf '#!/bin/sh\necho "%s"\n' "$spaced" > "$shipyard/fetch_sdk.sh"
  run build cross
  [ "$status" -eq 1 ]
  [[ "$output" == *"build-codex: the SDK path $spaced contains whitespace"* ]] || false
  [ ! -e "$cargo_env" ]
}

@test "a build puts the source's LICENSE and NOTICE in the artifact" {
  run build native
  succeeded
  root="$(cd -P "$MAVERICKS_BUILD_ROOT" && pwd)/codex-native"
  cmp "$source_dir/LICENSE" "$root/LICENSE"
  cmp "$source_dir/NOTICE" "$root/NOTICE"
}

@test "a build refuses a source without NOTICE" {
  rm "$source_dir/NOTICE"
  run build native
  [ "$status" -eq 1 ]
  [[ "$output" == *"build-codex: no $source_dir/NOTICE"* ]] || false
  [ ! -e "$cargo_env" ]
}

@test "the build manifest carries the identity in BUILD_ID" {
  printf '0.161.0-mavericks.7\n' > "$product/BUILD_ID"
  run build cross
  succeeded
  grep -qx "version=0.161.0-mavericks.7" "$(cd -P "$MAVERICKS_BUILD_ROOT" && pwd)/codex-cross/build-manifest"
}

@test "BUILD_ID wins over the older VERSION file" {
  printf '0.161.0-mavericks.7\n' > "$product/BUILD_ID"
  printf '0.161.0-mavericks.2\n' > "$product/VERSION"
  run build cross
  succeeded
  grep -qx "version=0.161.0-mavericks.7" "$(cd -P "$MAVERICKS_BUILD_ROOT" && pwd)/codex-cross/build-manifest"
}

@test "without BUILD_ID or VERSION the manifest says -mavericks.0 and the build says it is a dev build" {
  run build cross
  succeeded
  [[ "$output" == *"a dev build"* ]] || false
  grep -qx "version=$(sh "$PRODUCT_ROOT/build/codex-pin.sh" version)-mavericks.0" \
    "$(cd -P "$MAVERICKS_BUILD_ROOT" && pwd)/codex-cross/build-manifest"
}

# ---- the Objective-C provider: build/fetch-recaulk-objc.sh, then shipyard's linker arguments ----
# spec: build/codex-build-env.sh codex_objc_provider -- cargo gets MAVERICKS_OBJC_LINK_ARGS_FILE (out of
#       the source and target trees) and the archive's digest, never the provider in any rustflags.

cargo_value() { sed -n "s/^$1=//p" "$cargo_env"; }

# provider_reaches_cargo MODE: cargo ran with the provider's arguments file for MODE, and nothing else
# carries them.
provider_reaches_cargo() {
  root=$(cd -P "$MAVERICKS_BUILD_ROOT" && pwd)
  file=$(cargo_value MAVERICKS_OBJC_LINK_ARGS_FILE)
  [ "$file" = "$root/objc-$1/link-args" ] || { echo "args file: $file"; false; }
  [ "$(sed -n 1p "$file")" = "$(cd -P "$provider" && pwd)/lib/librecaulk-objc.a" ]
  grep -qx -- -Wl,-u,___recaulk_objc_activate "$file"
  grep -qx -- "$root/objc-$1/linkmaps/codex.map" "$file"
  [ "$(cargo_value MAVERICKS_OBJC_PROVIDER_ARCHIVE_SHA256)" = "$(objc_fixture_sha "$provider/lib/librecaulk-objc.a")" ]
  case "$file" in "$source_dir"/*|"$root/codex-$1-target"/*) echo "args file inside the source or target tree"; false ;; esac
  if grep -E '^(RUSTFLAGS|CARGO_ENCODED_RUSTFLAGS|CARGO_TARGET_[A-Z0-9_]*_RUSTFLAGS|CARGO_BUILD_RUSTFLAGS)=.*(recaulk|AppKit|-map)' "$cargo_env"; then false; fi
}

@test "a native build hands cargo the provider's linker arguments in a file, and no rustflags carry them" {
  run build native
  succeeded
  provider_reaches_cargo native
  grep -qx "SDKROOT=$sdk" "$cargo_env"
  cargo_lacks CARGO_TARGET_X86_64_APPLE_DARWIN_RUSTFLAGS
  grep -qx "recaulk 20261201.1 $(cd -P "$MAVERICKS_BUILD_ROOT" && pwd)/recaulk-20261201.1" "$BATS_TEST_TMPDIR/recaulk-fetches"
}

@test "a cross build hands cargo the same arguments, and its target rustflags stay the SDK's alone" {
  run build cross
  succeeded
  provider_reaches_cargo cross
  grep -qx "CARGO_TARGET_X86_64_APPLE_DARWIN_RUSTFLAGS=-C link-arg=-isysroot -C link-arg=$sdk" "$cargo_env"
  cargo_lacks SDKROOT
}

@test "a build without a released or development provider fails before cargo runs" {
  rm "$product/components/recaulk/version"
  run build native
  [ "$status" -ne 0 ]
  [[ "$output" == *"CODEX_DEV_RECAULK_PREFIX"* ]] || false
  [ ! -e "$cargo_env" ]
}

@test "a provider the shared check refuses fails the build before cargo runs" {
  printf 'x' >> "$provider/lib/librecaulk-objc.a"
  run build native
  [ "$status" -ne 0 ]
  [[ "$output" == *"shipyard refused the provider declaration"* ]] || false
  [ ! -e "$cargo_env" ]
}

@test "the manifest records the provider's origin, version, archive and declaration" {
  printf '0.161.0-mavericks.7\n' > "$product/BUILD_ID"
  run build native
  succeeded
  m="$(cd -P "$MAVERICKS_BUILD_ROOT" && pwd)/codex-native/build-manifest"
  grep -qx "version=0.161.0-mavericks.7" "$m"
  grep -qx "recaulk_origin=released" "$m"
  grep -qx "recaulk_version=20261201.1" "$m"
  grep -qx "recaulk_archive_sha256=$(objc_fixture_sha "$provider/lib/librecaulk-objc.a")" "$m"
  grep -qx "recaulk_declaration_sha256=$(objc_fixture_sha "$provider/share/recaulk/objc-providers.json")" "$m"
}

@test "a development provider makes a dev build whatever BUILD_ID says, and fetches no release" {
  printf '0.161.0-mavericks.7\n' > "$product/BUILD_ID"
  staged="$BATS_TEST_TMPDIR/sp ace/staged"
  objc_fixture_prefix "$staged" "$(sh "$real_shipyard/fetch_sdk.sh" --arch x86_64)"
  CODEX_DEV_RECAULK_PREFIX="$staged" run build cross
  succeeded
  m="$(cd -P "$MAVERICKS_BUILD_ROOT" && pwd)/codex-cross/build-manifest"
  grep -qx "version=$(sh "$PRODUCT_ROOT/build/codex-pin.sh" version)-mavericks.0" "$m"
  grep -qx "recaulk_origin=development" "$m"
  grep -qx "recaulk_version=development" "$m"
  [[ "$output" == *"never publishable"* ]] || false
  [ "$(sed -n 1p "$(cargo_value MAVERICKS_OBJC_LINK_ARGS_FILE)")" = "$(cd -P "$staged" && pwd)/lib/librecaulk-objc.a" ]
  [ ! -e "$BATS_TEST_TMPDIR/recaulk-fetches" ]
}

@test "unchanged arguments keep the args file's mtime, so cargo does not relink for nothing" {
  run build native
  succeeded
  file="$(cd -P "$MAVERICKS_BUILD_ROOT" && pwd)/objc-native/link-args"
  touch -t 200001010000.00 "$file"
  run build native
  succeeded
  [ "$(stat -f %m "$file")" = "$(date -j -f %Y%m%d%H%M%S 20000101000000 +%s)" ]
}

@test "cargo-dev.sh runs cargo with the provider's arguments too" {
  mkdir -p "$MAVERICKS_BUILD_ROOT/codex-src/codex-rs"
  cp "$source_dir/codex-rs/rust-toolchain.toml" "$MAVERICKS_BUILD_ROOT/codex-src/codex-rs/"
  MODE_FOR_TEST=native run sh "$product/build/cargo-dev.sh" test -p codex-install-context
  succeeded
  root=$(cd -P "$MAVERICKS_BUILD_ROOT" && pwd)
  [ "$(cargo_value MAVERICKS_OBJC_LINK_ARGS_FILE)" = "$root/objc-dev/link-args" ]
  grep -qx -- "$root/objc-dev/linkmaps/codex.map" "$root/objc-dev/link-args"
}
