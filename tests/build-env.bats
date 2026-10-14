#!/usr/bin/env bats
# platform: macOS-only -- the stand-in libcxx22 dylibs are compiled with cc

# build-codex.sh runs in a scratch copy of the product whose fetch scripts are stand-ins, against a
# scratch shipyard whose mode and SDK are the test's. Its cargo is a stand-in that records the
# environment it was given and writes empty binaries, so each test sees what the real cargo would.
setup() {
  export PRODUCT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export SHIPYARD_SCRIPTS="${SHIPYARD_SCRIPTS:-/home/schmonz/Documents/trees/mavergreen-shipyard/scripts}"
  export MAVERICKS_BUILD_ROOT="$BATS_TEST_TMPDIR/local-build"
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
  export SHIPYARD_SCRIPTS="$shipyard"

  source_dir="$BATS_TEST_TMPDIR/codex-src"
  mkdir -p "$source_dir/codex-rs"
  printf '[toolchain]\nchannel = "1.95.0"\n' > "$source_dir/codex-rs/rust-toolchain.toml"
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

  # clang22 and clang22-cross get compilers and an SDKs/ for build-codex.sh to link the SDK into;
  # libcxx22 gets the two dylibs the native cargo runs with inserted.
  for product_name in clang22 clang22-cross libcxx22; do
    mkdir -p "$BATS_TEST_TMPDIR/clang/$product_name/bin" "$BATS_TEST_TMPDIR/clang/$product_name/SDKs" \
      "$BATS_TEST_TMPDIR/clang/$product_name/lib"
    printf '#!/bin/sh\n' > "$BATS_TEST_TMPDIR/clang/$product_name/bin/clang"
    printf '#!/bin/sh\n' > "$BATS_TEST_TMPDIR/clang/$product_name/bin/clang++"
    chmod +x "$BATS_TEST_TMPDIR/clang/$product_name/bin/clang" "$BATS_TEST_TMPDIR/clang/$product_name/bin/clang++"
  done
  # platform: DYLD_LIBRARY_PATH matches by leaf name, so the inserted libc++ also answers for 10.9's
  #           /usr/lib/libc++.1.dylib and must be a real one: 10.9's own, copied. A modern Mac keeps
  #           its libc++ only in the dyld shared cache, but SIP strips DYLD_* from the protected
  #           /usr/bin/env there, so a stand-in compiled by cc is never loaded.
  printf 'void stand_in(void) {}\n' > "$BATS_TEST_TMPDIR/empty.c"
  for pair in libc++abi.dylib:libc++abi.1.dylib libc++.1.dylib:libc++.1.dylib; do
    cp "/usr/lib/${pair%%:*}" "$BATS_TEST_TMPDIR/clang/libcxx22/lib/${pair#*:}" 2>/dev/null ||
      cc -dynamiclib -o "$BATS_TEST_TMPDIR/clang/libcxx22/lib/${pair#*:}" "$BATS_TEST_TMPDIR/empty.c"
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

build() {
  MODE_FOR_TEST=$1 PATH="$stand_ins/bin:$PATH" sh "$product/build/build-codex.sh" "$1"
}

@test "a cross build hands the SDK to the target's links alone, and no SDKROOT to cargo" {
  SDKROOT=/elsewhere RUSTFLAGS=-Cfoo CARGO_ENCODED_RUSTFLAGS=-Cbar run build cross
  [ "$status" -eq 0 ]
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
  [ "$status" -eq 0 ]
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
