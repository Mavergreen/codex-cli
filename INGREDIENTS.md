# Build ingredients

| Ingredient | Pin | Use |
| --- | --- | --- |
| OpenAI Codex | `UPSTREAM_VERSION` `0.161.0`; `build/codex-revision` `979011409de0a60b52f179721948e65531d26144` | CLI source and Cargo workspace |
| Mavergreen Rust toolchain (`rust` on 10.9, `rust-cross` on a modern Mac) | `components/rust/version` (`1.99.0-mavericks.2`, the first release whose `rustc` defers its back-fill to a linker that already links `librecaulk.a`, as clang-22's `clang++` does); the released `.pkg` is verified against the release's `SHA256SUMS` and extracted under the build root, never installed. Renovate (`github-releases` on `Mavergreen/rust`, `-mavericks.N` versioning) will be wired by the old plan's Task 6; nothing bumps the pin yet. `build/check-rust-pin.sh` refuses a pin whose upstream version is older than Codex's `rust-toolchain.toml` channel (`1.95.0`); a newer one builds it | Rust compiler, Cargo, and target support for `x86_64-apple-darwin` on 10.9 |
| Mavergreen clang-22 (`clang22` on 10.9, `clang22-cross` on a modern Mac, and `libcxx22`) | `components/clang-22/version` (`22.1.1-mavericks.8`). Each pkg is verified against the release's `SHA256SUMS` by `build/fetch-clang-22.sh` and extracted under the build root, never installed. Renovate (`github-releases` on `Mavergreen/clang-22`, `-mavericks.N` versioning) will be wired by the old plan's Task 6; nothing bumps the pin yet | C and C++ compiler for Codex's native dependencies (`CC_x86_64_apple_darwin`, `CXX_x86_64_apple_darwin`), and its `clang++` is the linker (`CARGO_TARGET_X86_64_APPLE_DARWIN_LINKER`). `libcxx22` is the libc++ runtime that the build-time `protoc` runs on, natively only. It is never linked into the shipped binaries |
| Mavergreen shipyard | inspected revision `66579f0a5899a16744a7c9c79e52e63b95a46fa2` | SDK, build mode, source fetch, compatibility, and package helpers |
| Sparkle, in the updater | shipyard's `fetch_sparkle_framework.sh`, pinned by hash there; the family EdDSA public key is `updater/ed25519_key.pub`, the same file every Mavergreen product carries | Update channel for the installed CLI. Untrackable here: shipyard owns the Sparkle pin |
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

Both imported Rust executables, `codex` and `codex-code-mode-host`, are checked by shipyard's
`assert_binary_compatible.sh` from the CMake custom target `codex_compat`. Shipyard's
`mavericks_assert_binary_compatible()` attaches a `POST_BUILD` command to a compiled target, while
CMake does not permit that command on an imported executable. The custom target therefore invokes
the same shipyard checker on each exact imported file. It then runs `build/check-load-paths.sh` on
both, which refuses any library outside `/usr/lib/` and `/System/Library/` and any `LC_RPATH`:
shipyard's checker does not look at load paths, and it passed a `codex` that loaded pkgsrc's
`/opt/pkg` dylibs. `build/verify-artifact.sh` runs the same load-path check on a transferred
artifact. It is interim, until shipyard's family guard checks load paths.

## Packaging

`packaging/build-pkg.sh UPDATER-APP CODEX-OUT VERSION OUT-DIR` wraps a build's artifact directory
(`codex-native` or `codex-cross`) in `OUT-DIR/codex-cli-VERSION.pkg`, the same way in either mode, using
shipyard's `stage_product.sh`, `build_component_pkg.sh` and `set_install_floor.sh`; nothing is
hand-written. The product tree is `/usr/local/mavergreen/codex-cli` with `bin/codex` and
`bin/codex-code-mode-host` side by side, because Codex finds the host beside its canonicalized
executable (patch 0009 makes that work through the link farm's symlink). Only `codex` is exported to
`/usr/local/mavergreen/bin`: `--exclude bin/codex-code-mode-host` keeps the host out. The build
manifest ships as `share/doc/codex-cli/build-manifest`. The pkg has no `codex-voice-host` and no
`codex-resources/voice`, and `build-pkg.sh` refuses an artifact directory that has either.

`tests/package-test.sh PKG CODEX-OUT` checks the pkg, in either mode, with no Bats and no Python:
payload contents and modes, binaries byte-identical to the build, manifest identity, a link farm that
holds `codex` alone and resolves to a directory holding the host, a clean upgrade and uninstall, and the
updater's bundle ID, feed and comparison version against the registry and the package version. It runs
the pkg's own install scripts against a temporary target root, never `/`.

The updater is an off-by-default CMake option, `-DCODEX_BUILD_UPDATER=ON`, because it needs `codex-cli`
in the installed shipyard's product registry (`codex-cli dev.mavergreen.codex-cli codex-cli`). That
registry row is pending: it is not in a shipyard release yet, and this file records no shipyard revision
for it until it is. The updater never links the CLI binary.

## License notices

Codex is Apache-2.0, whose section 4 requires the license text and the NOTICE file to accompany
redistributed binaries. `build/build-codex.sh` copies `LICENSE` and `NOTICE` from the fetched, pinned
Codex source root into the artifact directory, next to the binaries and `build-manifest`, in both modes
and failing if either is missing or empty. `transfer-artifact.sh` and `verify-artifact.sh` carry and
require them, so a cross artifact moved from the modern Mac has them too. `packaging/build-pkg.sh`
installs them from the artifact, never from a checkout, at `share/doc/codex-cli/LICENSE` and
`share/doc/codex-cli/NOTICE`, and fails without them. `tests/package-test.sh` checks both are in the pkg
and byte-identical to the artifact's.

## Deviations

- **Generic updater icon.** The updater passes `ALLOW_GENERIC` and ships no `.icns`: Codex's mark is
  OpenAI's, and this is an unofficial build that must not read as official. `updater/ICON-CREDIT.txt`
  says why and what ends the deviation, as mavergreen-rg does.
- **Codex is not built by CMake.** The CMake project imports the two executables that
  `build/build-codex.sh` made, so the product is packaged by `packaging/build-pkg.sh` from that output
  rather than from CMake install rules.
