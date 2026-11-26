#!/bin/sh
# platform: host-agnostic -- the native (10.9) and cross (x86_64 Linux or an arm64 modern Mac) build
#   environment, shared by build-codex.sh and cargo-dev.sh
# so a development cargo run cannot drift from the release build.
# Sourced after lib.sh. Prints errors as "build-codex:" in both callers.

# codex_check_host MODE: this host can build MODE.
codex_check_host() {
  MODE=$1
  ACTUAL_MODE=$(sh "$SHIPYARD_SCRIPTS/mavericks_mode.sh")
  [ "$MODE" = "$ACTUAL_MODE" ] || {
    echo "build-codex: requested $MODE build on a $ACTUAL_MODE host" >&2; exit 1;
  }
  case "$MODE:$(uname -s):$(uname -m)" in
    native:Darwin:*|cross:Darwin:arm64|cross:Linux:x86_64) ;;
    native:*) echo "build-codex: native builds run on Mac OS X 10.9" >&2; exit 1 ;;
    *) echo "build-codex: cross builds run on x86_64 Linux or an arm64 modern Mac" >&2; exit 1 ;;
  esac
}

# codex_build_env MODE SOURCE TARGET_DIR OBJC_DIR: export the build environment and set RUST_PREFIX,
#   RUST_PIN, SDK, CLANG_VERSION, PROTOC_RUNTIME, RUSTY_V8_VERSION, RUSTY_V8_REMOVED and the RECAULK_* provider identity.
#   codex_cargo then runs cargo in it. OBJC_DIR (outside SOURCE and TARGET_DIR) receives the provider's
#   linker arguments and, at link time, linkmaps/codex.map.
codex_build_env() {
  MODE=$1; SOURCE=$2; TARGET_DIR=$3; OBJC_DIR=$4
  BUILD_ROOT=$(mavericks_build_root)
  sh "$BUILD_DIR/check-rust-pin.sh" "$SOURCE"
  RUST_PIN=$(tr -d '[:space:]' < "$MAVERICKS_ROOT/components/rust/version")

  # spec: shipyard scripts/cargo-env.sh -- on Linux the pinned rust, clang22 and 10.9 SDK, and the cargo
  #       environment that targets 10.9 with them, are shipyard's. Its SDKROOT reaches only Apple
  #       targets there, so the Linux host's build scripts and proc macros never see it.
  if [ "$(uname -s)" = Linux ]; then
    linux_env=$(sh "$SHIPYARD_SCRIPTS/cargo-env.sh" --sh "$MAVERICKS_ROOT/components/rust" \
      "$MAVERICKS_ROOT/components/clang-22") || {
      echo "build-codex: shipyard's cargo-env.sh gave no Linux cargo environment" >&2; exit 1;
    }
    eval "$linux_env"
    RUST_PREFIX=${CARGO%/bin/cargo}
  else
    RUST_PREFIX=$(sh "$BUILD_DIR/fetch-rust.sh")
  fi
  [ -x "$RUST_PREFIX/bin/cargo" ] && [ -x "$RUST_PREFIX/bin/rustc" ] || {
    echo "build-codex: fetched Rust toolchain is incomplete at $RUST_PREFIX" >&2; exit 1;
  }

  # platform: both modes build against shipyard's pinned 10.9 SDK. The Mavergreen clang-22 product
  #           expects it at SDKs/MacOSX10.9.sdk beside its bin/, and its cfg passes -isysroot there
  #           for every target C and C++ compile; this host's xcrun --show-sdk-path prints nothing.
  if [ "$(uname -s)" = Linux ]; then SDK=$SDKROOT; else SDK=$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh"); fi
  # platform: cargo uses RUSTFLAGS or CARGO_ENCODED_RUSTFLAGS from the caller in place of the
  #           target rustflags that cross sets below, so neither reaches either mode.
  unset RUSTFLAGS CARGO_ENCODED_RUSTFLAGS
  case "$MODE:$(uname -s)" in
    # platform: natively host and target are both 10.9 x86_64, so SDKROOT may reach build scripts
    #           too. The 2026-10-14 native builds were measured with it set.
    native:*) export SDKROOT="$SDK" ;;
    # platform: in cross, SDKROOT would also reach the aarch64 build scripts and proc macros, which
    #           cannot link against the 10.9 SDK (as ../mavergreen-rg and ../mavergreen-fd's
    #           build/build.sh say). target.x86_64-apple-darwin rustflags reach only the target's
    #           links, and cargo splits them on whitespace. Not yet measured on an arm64 host.
    # platform: on Linux cargo-env.sh's SDKROOT reaches only Apple targets, so it stays and no target
    #           rustflags are needed.
    # spec: the family build-twice check -- the build root reaches the binary through Rust panic
    #       locations and C __FILE__ under CARGO_HOME, so both are written relative to fixed names;
    #       the debug map names ThinLTO objects and rustc's random temporary directories, all
    #       deleted once the link is done, so it is left out
    cross:Linux)
      case "$BUILD_ROOT" in *[[:space:]]*)
        echo "build-codex: the build root $BUILD_ROOT contains whitespace, which cargo would split inside its rustflags" >&2
        exit 1 ;;
      esac
      CARGO_TARGET_X86_64_APPLE_DARWIN_RUSTFLAGS="--remap-path-prefix=$BUILD_ROOT/cargo-home=/cargo-home --remap-path-prefix=$TARGET_DIR=/target -C link-arg=-Wl,-S"
      CFLAGS_x86_64_apple_darwin="-ffile-prefix-map=$BUILD_ROOT/cargo-home=/cargo-home -ffile-prefix-map=$TARGET_DIR=/target"
      CXXFLAGS_x86_64_apple_darwin=$CFLAGS_x86_64_apple_darwin
      export CARGO_TARGET_X86_64_APPLE_DARWIN_RUSTFLAGS CFLAGS_x86_64_apple_darwin CXXFLAGS_x86_64_apple_darwin ;;
    cross:*)
      case "$SDK" in *[[:space:]]*)
        echo "build-codex: the SDK path $SDK contains whitespace, which cargo would split inside its rustflags" >&2
        exit 1 ;;
      esac
      unset SDKROOT
      CARGO_TARGET_X86_64_APPLE_DARWIN_RUSTFLAGS="-C link-arg=-isysroot -C link-arg=$SDK"
      export CARGO_TARGET_X86_64_APPLE_DARWIN_RUSTFLAGS ;;
  esac

  # platform: 10.9's own clang 3.5 cannot assemble aws-lc's AVX-512 code and has no <stdatomic.h>,
  #           so C and C++ dependencies compile with Mavergreen/clang-22 (clang22 on 10.9,
  #           clang22-cross on Apple Silicon). The target-specific names keep a cross build's
  #           aarch64 build scripts on the host compiler.
  case "$MODE" in native) CLANG_PRODUCT=clang22 ;; cross) CLANG_PRODUCT=clang22-cross ;; esac
  CLANG_VERSION=$(tr -d '[:space:]' < "$MAVERICKS_ROOT/components/clang-22/version")
  # platform: on Linux, cargo-env.sh's clang22 is shipyard's install, whose SDKs already holds the SDK
  #           and which this user may not write.
  if [ "$(uname -s)" = Linux ]; then
    CLANG_PRODUCT=clang22
    CLANG_PREFIX=${CXX_x86_64_apple_darwin%/bin/clang++}
  else
    CLANG_PREFIX=$(sh "$BUILD_DIR/fetch-clang-22.sh" "$CLANG_PRODUCT")
    # platform: the product's SDKs is a link to a directory its pkg does not carry: ../sdk109/SDKs,
    #           which Longboat's sdk109 fills on an install (../var/$CLANG_PRODUCT/SDKs before
    #           22.1.8-mavericks.11). Extracted, not installed, it dangles until made here.
    if sdks=$(readlink "$CLANG_PREFIX/SDKs"); then
      case "$sdks" in /*) ;; *) sdks="$CLANG_PREFIX/$sdks" ;; esac
      mkdir -p "$sdks"
    fi
    ln -sfn "$SDK" "$CLANG_PREFIX/SDKs/MacOSX10.9.sdk"
  fi
  [ -x "$CLANG_PREFIX/bin/clang" ] && [ -x "$CLANG_PREFIX/bin/clang++" ] &&
    [ -d "$CLANG_PREFIX/SDKs/MacOSX10.9.sdk/usr/include" ] || {
    echo "build-codex: $CLANG_PRODUCT at $CLANG_PREFIX has no compilers or no SDK" >&2; exit 1;
  }
  export CC_x86_64_apple_darwin="$CLANG_PREFIX/bin/clang"
  export CXX_x86_64_apple_darwin="$CLANG_PREFIX/bin/clang++"
  # platform: 10.9's cc overflows posix_spawn's argv on codex-code-mode-host's ~1355 LTO objects, so
  #           the same clang++ links: it hands lld a response file. Its cfg links librecaulk.a, so
  #           Mavergreen/rust's rustc (from 1.99.0-mavericks.2) adds no back-fill of its own. The
  #           manifest needs no linker field: the linker follows clang_version, which both modes
  #           must match.
  export CARGO_TARGET_X86_64_APPLE_DARWIN_LINKER="$CLANG_PREFIX/bin/clang++"
  # platform: no host pkg-config answers for the 10.9 target. ultimate-hat's pkgsrc one made lzma-sys
  #           link /opt/pkg/lib/liblzma.5.dylib (and, through its -L, /opt/pkg's libiconv) into codex,
  #           and a modern Mac's Homebrew one would do the same. With every probe failing, lzma-sys
  #           and aws-lc-sys build their bundled sources with clang-22, as the other -sys crates do.
  export PKG_CONFIG_x86_64_apple_darwin=/usr/bin/false

  # platform: protoc-bin-vendored's macOS protoc needs libc++ symbols 10.9's /usr/lib/libc++ lacks,
  #           and Codex's build script runs it by a fixed path. On 10.9 the cargo process tree runs on
  #           the release's libcxx22, extracted under the build root: inserted, flat namespace, and
  #           found by leaf name so libc++'s own libc++abi dependency resolves there too. It is
  #           build-time only and never reaches the shipped binaries. A cross build's protoc is the
  #           aarch64 one on a modern libc++ and needs none of this.
  PROTOC_RUNTIME=host
  if [ "$MODE" = native ]; then
    LIBCXX_PREFIX=$(sh "$BUILD_DIR/fetch-clang-22.sh" libcxx22)
    PROTOC_RUNTIME="libcxx22-$CLANG_VERSION"
  fi

  codex_objc_provider "$OBJC_DIR"

  mkdir -p "$TARGET_DIR"
  V8_FILES=$(sh "$BUILD_DIR/fetch-rusty-v8.sh" "$SOURCE")
  # spec: build/fetch-rusty-v8.sh -- it stores the archive under rusty-v8-<Cargo.lock's v8 version>/.
  RUSTY_V8_ARCHIVE=$(printf '%s\n' "$V8_FILES" | sed -n 1p)
  RUSTY_V8_SRC_BINDING_PATH=$(printf '%s\n' "$V8_FILES" | sed -n 2p)
  [ -f "$RUSTY_V8_ARCHIVE" ] && [ -f "$RUSTY_V8_SRC_BINDING_PATH" ] || {
    echo "build-codex: fetch-rusty-v8.sh did not name an archive and a binding" >&2; exit 1;
  }
  RUSTY_V8_VERSION=$(printf '%s\n' "$RUSTY_V8_ARCHIVE" | sed -n 's,.*/rusty-v8-\([0-9][0-9.]*\)/.*,\1,p')
  [ -n "$RUSTY_V8_VERSION" ] || {
    echo "build-codex: no V8 version in $RUSTY_V8_ARCHIVE" >&2; exit 1;
  }
  # spec: build/strip-v8-cxxabi.sh header -- the host links V8 without V8's own libc++abi, so it has
  #       one C++ runtime: the system's libc++abi and Recaulk.
  # spec: v8's build.rs reruns only when RUSTY_V8_ARCHIVE's value changes, so the path names the
  #       strip script's digest: a changed strip relinks V8 in an incremental build.
  strip_digest=$(shasum -a 256 < "$BUILD_DIR/strip-v8-cxxabi.sh" | cut -c1-12)
  RUSTY_V8_ONE_RUNTIME="${RUSTY_V8_ARCHIVE%.a.gz}.one-runtime-$strip_digest.a"
  for stale in "${RUSTY_V8_ARCHIVE%.a.gz}".one-runtime*.a; do
    [ "$stale" = "$RUSTY_V8_ONE_RUNTIME" ] || rm -f "$stale"
  done
  removed=$(AR="$CLANG_PREFIX/bin/llvm-ar" NM="$CLANG_PREFIX/bin/llvm-nm" \
    sh "$BUILD_DIR/strip-v8-cxxabi.sh" "$RUSTY_V8_ARCHIVE" "$RUSTY_V8_ONE_RUNTIME") || exit 1
  RUSTY_V8_REMOVED=$(printf '%s\n' "$removed" | paste -s -d , -)
  [ -n "$RUSTY_V8_REMOVED" ] || { echo "build-codex: strip-v8-cxxabi.sh removed nothing" >&2; exit 1; }
  RUSTY_V8_ARCHIVE=$RUSTY_V8_ONE_RUNTIME
  export RUSTY_V8_ARCHIVE RUSTY_V8_SRC_BINDING_PATH RUSTY_V8_REMOVED
  export CARGO_TARGET_DIR="$TARGET_DIR"
  export CARGO_HOME="$BUILD_ROOT/cargo-home"
  export CARGO_NET_GIT_FETCH_WITH_CLI=true
  export MACOSX_DEPLOYMENT_TARGET=10.9
}

# codex_objc_provider OBJC_DIR: the Recaulk Objective-C provider the codex binary links
#   (build/fetch-recaulk-objc.sh), and shipyard's linker arguments for it in OBJC_DIR/link-args, exported
#   as MAVERICKS_OBJC_LINK_ARGS_FILE with the archive's digest as MAVERICKS_OBJC_PROVIDER_ARCHIVE_SHA256.
#   patches/0014's codex-rs/cli/build.rs hands them to the codex binary's link alone, for an x86_64
#   macOS target only: never as rustflags, which would reach every target, build script, proc macro
#   and codex-code-mode-host. Sets RECAULK_PREFIX, RECAULK_ORIGIN, RECAULK_VERSION,
#   RECAULK_ARCHIVE_SHA256 and RECAULK_DECLARATION_SHA256.
codex_objc_provider() {
  objc_dir=$1
  provider=$(sh "$BUILD_DIR/fetch-recaulk-objc.sh") || {
    echo "build-codex: no verified Recaulk Objective-C provider (build/fetch-recaulk-objc.sh above)" >&2; exit 1;
  }
  RECAULK_PREFIX=$(printf '%s\n' "$provider" | sed -n 1p)
  RECAULK_ORIGIN=$(printf '%s\n' "$provider" | sed -n 2p)
  RECAULK_VERSION=$(printf '%s\n' "$provider" | sed -n 3p)
  mkdir -p "$objc_dir/linkmaps"
  sh "$SHIPYARD_SCRIPTS/objc-provider-link-args.sh" --prefix "$RECAULK_PREFIX" \
    --link-map "$objc_dir/linkmaps/codex.map" > "$objc_dir/link-args.new" || {
    rm -f "$objc_dir/link-args.new"
    echo "build-codex: shipyard gave no linker arguments for the provider at $RECAULK_PREFIX" >&2; exit 1;
  }
  # platform: build.rs reruns, and codex relinks, when the file's mtime moves; unchanged arguments
  #           keep the old file so a rebuild does not relink for nothing.
  if cmp -s "$objc_dir/link-args.new" "$objc_dir/link-args"; then
    rm "$objc_dir/link-args.new"
  else
    mv "$objc_dir/link-args.new" "$objc_dir/link-args"
  fi
  archive=$(sed -n 1p "$objc_dir/link-args")
  RECAULK_ARCHIVE_SHA256=$(shasum -a 256 "$archive" | cut -c1-64)
  RECAULK_DECLARATION_SHA256=$(shasum -a 256 "$RECAULK_PREFIX/share/recaulk/objc-providers.json" | cut -c1-64)
  MAVERICKS_OBJC_LINK_ARGS_FILE="$objc_dir/link-args"
  # spec: patches/0014 -- an archive whose bytes change under the same mtime still reruns build.rs.
  MAVERICKS_OBJC_PROVIDER_ARCHIVE_SHA256=$RECAULK_ARCHIVE_SHA256
  export MAVERICKS_OBJC_LINK_ARGS_FILE MAVERICKS_OBJC_PROVIDER_ARCHIVE_SHA256
}

# codex_cargo ARGS...: cargo in SOURCE/codex-rs, under codex_build_env's environment.
codex_cargo() {
  if [ "$MODE" = native ]; then
    (cd "$SOURCE/codex-rs" && PATH="$RUST_PREFIX/bin:$PATH" env DYLD_LIBRARY_PATH="$LIBCXX_PREFIX/lib" \
      DYLD_FORCE_FLAT_NAMESPACE=1 \
      DYLD_INSERT_LIBRARIES="$LIBCXX_PREFIX/lib/libc++abi.1.dylib:$LIBCXX_PREFIX/lib/libc++.1.dylib" \
      "$RUST_PREFIX/bin/cargo" "$@")
  else
    (cd "$SOURCE/codex-rs" && PATH="$RUST_PREFIX/bin:$PATH" "$RUST_PREFIX/bin/cargo" "$@")
  fi
}
