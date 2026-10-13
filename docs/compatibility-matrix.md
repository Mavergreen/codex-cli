# Compatibility matrix

What building and running Codex 0.161.0 on Mac OS X 10.9 needed, one row per symptom. Wowfunhappy's
native 10.9 build of 0.161.0 met some of these first. "Source" says whether this build reproduced
them. The native rows were measured on ultimate-hat (Mac OS X 10.9.5, x86_64) on 2026-10-13 with
`sh build/build-codex.sh native`.

## Build

| Symptom | Cause | Fix | Ingredient | Source |
|---|---|---|---|---|
| `error: cannot update the lock file .../codex-rs/Cargo.lock because --locked was passed to prevent this` before anything compiles | The `rust-v0.161.0` tag sets `[workspace.package] version = "0.161.0"`, but its `Cargo.lock` still records `0.0.0` for all 160 workspace packages. Not specific to 10.9 | `build/fetch-codex.sh` writes the workspace version into the `Cargo.lock` entries that have no `source` and are at `0.0.0`, after the patch series. It fails if it finds none. `--locked` still refuses any other drift | none (recipe) | measured here; not in Wowfunhappy's build, which used `cargo install` on a long-lived tree |
| A rerun fails with `pinned source checkout is dirty before patch application` | `fetch-codex.sh` refused the checkout its own patches had left dirty | `fetch-codex.sh` stamps the prepared tree under `.git/` (the patch series, the script, `UPSTREAM_VERSION`, `codex-revision`, and the tree state including ignored files) and reuses it unchanged, keeping Cargo's mtime fingerprints. Any other dirty tree is reset and prepared again | none (recipe) | measured here |
| `aws-lc-sys`: `rsaz-4k-avx512.S: error: invalid instruction mnemonic 'kmovb'` (and every other AVX-512 line), then `c11.c: fatal error: 'stdatomic.h' file not found` | 10.9's `cc` is Apple clang-600.0.57 (LLVM 3.5svn). It cannot assemble AVX-512 and has no C11 `<stdatomic.h>` | `CC_x86_64_apple_darwin` / `CXX_x86_64_apple_darwin` are clang-22's `clang` / `clang++`, in both modes. The target-specific names keep a cross build's aarch64 build scripts on the host compiler | Mavergreen/clang-22 `22.1.1-mavericks.8` (`clang22` natively, `clang22-cross` on Apple Silicon), `components/clang-22/version`, fetched by `build/fetch-clang-22.sh` | measured here. It is the same class as Wowfunhappy's "a C dependency rejects C11 `static_assert`", and has the same fix. The `static_assert` error itself was not seen, because aws-lc failed first |
| clang-22: `no such sysroot directory: .../clang22/bin/../SDKs/MacOSX10.9.sdk`, then `'AvailabilityMacros.h' file not found` | The clang-22 pkg ships `SDKs` as a link to an empty `var/<product>/SDKs`, and this host's `xcrun --show-sdk-path` prints nothing | Both modes use shipyard's pinned 10.9 SDK (`fetch_sdk.sh`) as `SDKROOT`. `build-codex.sh` links it in as the extracted product's `SDKs/MacOSX10.9.sdk`. Both manifests record the SDK by name (`sdk=MacOSX10.9.sdk`), and `check-build-manifests.sh` requires it to match | shipyard's SDK pin | measured here, on a test compile with the extracted clang22 |
| `protoc failed: dyld: Symbol not found: __ZNSt19bad_optional_accessD1Ev ... Expected in: /usr/lib/libc++.1.dylib` (build script of `codex-code-mode-protocol`) | `protoc-bin-vendored` 3.2.0's macOS `protoc` needs a newer libc++ than 10.9's, and Codex's `build.rs` runs it by a fixed path | Natively, cargo runs under `DYLD_INSERT_LIBRARIES=<libcxx22>/lib/libc++abi.1.dylib:<libcxx22>/lib/libc++.1.dylib`, `DYLD_FORCE_FLAT_NAMESPACE=1` and `DYLD_LIBRARY_PATH=<libcxx22>/lib`. The last one makes libc++'s absolute libc++abi dependency resolve in the extracted copy, not in a host-installed `/usr/local/mavergreen/libcxx22`. This is build-time only. The cross host's `protoc` is the aarch64 one on a modern libc++ and gets none of this. The manifest records `protoc_runtime`, and `check-build-manifests.sh` allows only that difference | Mavergreen/clang-22 `libcxx22` from the same release | measured by Wowfunhappy, reproduced here |
| `linking with cc failed ... clang: error: unable to execute command: posix_spawn failed: Argument list too long` at `codex-code-mode-host`'s final link (1355 objects) | 10.9's clang 3.5 cannot pass that many arguments to `ld`, and it has no response file | **Open.** clang-22's `clang++` as `CARGO_TARGET_X86_64_APPLE_DARWIN_LINKER` (it links through lld with a response file, and its `portable-ld` adds the static libc++ V8 needs) fails on every link, build scripts included: `ld64.lld: error: duplicate symbol: linkat` / `openat` / `unlinkat` / `fclonefileat` / `fdopendir$INODE64` / `sysconf` / ..., between `librecaulk.a` (from clang-22's `clang++.cfg`) and `libMacportsLegacySupport.a` (force-loaded by Mavergreen/rust's `rustc` wrapper). Not committed. Waiting on a maintainer decision | Mavergreen/clang-22 and Mavergreen/rust, which conflict | measured by Wowfunhappy, reproduced here; the fix is blocked |
| Link or rebuild times impractical | upstream's release profile uses `lto = "thin"` | not applied | none | not measured: no link completed. Compiling through to the host's link took about 11 minutes on ultimate-hat |

## Running on 10.9

| Check | Result |
|---|---|
| `codex --version` prints `codex-cli 0.161.0` | not run: no binary yet |
| `codex-code-mode-host --help` exits 0 | not run: no binary yet |
| `codex sandbox -- /usr/bin/true` exits 0 | not run: no binary yet |
| shipyard `assert_binary_compatible.sh` on both binaries | not run: no binary yet |
| `code_mode_only` model through a symlinked `codex` does not report "Code Mode is unavailable" | maintainer, interactive |
| TUI starts in Terminal with a prompt, not an Objective-C exception | maintainer, interactive |
