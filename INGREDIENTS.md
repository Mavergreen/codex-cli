# Build ingredients

| Ingredient | Pin | Use |
| --- | --- | --- |
| OpenAI Codex | `UPSTREAM_VERSION` `0.161.0`; `build/codex-revision` `979011409de0a60b52f179721948e65531d26144` | CLI source and Cargo workspace |
| Mavergreen Rust toolchain (`rust` on 10.9, `rust-cross` on a modern Mac) | `components/rust/version` (`1.99.0-mavericks.2`, the first release whose `rustc` defers its back-fill to a linker that already links `librecaulk.a`, as clang-22's `clang++` does); the released `.pkg` is verified against the release's `SHA256SUMS` and extracted under the build root, never installed. Renovate (`github-releases` on `Mavergreen/rust`, `-mavericks.N` versioning) is wired with the old plan's Task 6. `build/check-rust-pin.sh` refuses a pin whose upstream version is older than Codex's `rust-toolchain.toml` channel (`1.95.0`); a newer one builds it | Rust compiler, Cargo, and target support for `x86_64-apple-darwin` on 10.9 |
| Mavergreen clang-22 (`clang22` on 10.9, `clang22-cross` on a modern Mac, and `libcxx22`) | `components/clang-22/version` (`22.1.1-mavericks.8`). Each pkg is verified against the release's `SHA256SUMS` by `build/fetch-clang-22.sh` and extracted under the build root, never installed | C and C++ compiler for Codex's native dependencies (`CC_x86_64_apple_darwin`, `CXX_x86_64_apple_darwin`), and its `clang++` is the linker (`CARGO_TARGET_X86_64_APPLE_DARWIN_LINKER`). `libcxx22` is the libc++ runtime that the build-time `protoc` runs on, natively only. It is never linked into the shipped binaries |
| Mavergreen shipyard | inspected revision `66579f0a5899a16744a7c9c79e52e63b95a46fa2` | SDK, build mode, source fetch, compatibility, and package helpers |
| OpenAI prebuilt `rusty_v8` | Derived from Codex's `Cargo.lock` (`v8` package), so a Codex bump moves it with no separate pin and Renovate tracks nothing extra; verified against upstream's published `.sha256` checksums file | Static V8 archive linked into `codex-code-mode-host`; prebuilt because building V8 needs Chromium's toolchain and python3, which a native 10.9 build lacks |

Codex is fetched into a host-local build root with shipyard's `clone_pinned.sh`. The exact Codex
commit is verified before committed `patches/*.patch` files are applied. `patches/README.md` says
what each patch changes and why, and `PROVENANCE.md` says where they came from. The `codex/`
directory is an ignored inspection checkout and is never a build input. The Rust toolchain is
fetched and verified independently from its release. Build and transfer staging directories
must remain outside this product source tree; `MAVERICKS_BUILD_ROOT` overrides the default
`${TMPDIR:-/tmp}/mm-build`.

`build/build-codex.sh native` runs on ultimate-hat (Mac OS X 10.9). It fetches the released Mavergreen
Rust toolchain and builds Codex CLI for `x86_64-apple-darwin`. `build/build-codex.sh cross` runs on modern
macOS. Both modes use shipyard's pinned 10.9 SDK, which is also the SDK the clang-22 product compiles against. Both paths set `MACOSX_DEPLOYMENT_TARGET=10.9`, use
Cargo's locked dependency graph, and set `CARGO_NET_GIT_FETCH_WITH_CLI=true` for nested Git sources.
Cargo home, target output, extracted toolchains, and transfer staging stay under the local build root.

`codex-cli` and `codex-code-mode-host` are built and transferred together: Codex finds the host as a
sibling of its own canonicalized executable. The host links V8, so the build fetches OpenAI's prebuilt
`rusty_v8` archive with `build/fetch-rusty-v8.sh` (the one declared non-Mavergreen input) and records
`rusty_v8_version` in the build manifest. The package does not include `codex-voice-host`, the
native voice runtime, or `codex-resources/voice`; voice support is deferred. The native build on ultimate-hat was last run on 2026-10-14,
in `MAVERICKS_BUILD_ROOT=/Users/schmonz/Library/Caches/mm-build` (macOS sweeps `$TMPDIR` nightly). Both
binaries link and pass the non-interactive smoke checks: see `docs/compatibility-matrix.md`.

## Compatibility gate implementation

The imported Rust executable is checked by shipyard's `assert_binary_compatible.sh` from a CMake
custom target. Shipyard's `mavericks_assert_binary_compatible()` attaches a `POST_BUILD` command to
a compiled target, while CMake does not permit that command on an imported executable. The custom
target therefore invokes the same shipyard checker on the exact imported `codex` file.
