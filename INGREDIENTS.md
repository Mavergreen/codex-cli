# Build ingredients

| Ingredient | Pin | Use |
| --- | --- | --- |
| OpenAI Codex | `UPSTREAM_VERSION` `0.161.0`; `build/codex-revision` `979011409de0a60b52f179721948e65531d26144`. Renovate (`github-releases` on `openai/codex`, tags `rust-v<x.y.z>`, so prereleases such as `rust-v0.162.0-alpha.1` never match) bumps `UPSTREAM_VERSION` only; the commit is a manual edit, see "Releasing" | CLI source and Cargo workspace |
| Mavergreen Rust toolchain (`rust` on 10.9, `rust-cross` on a modern Mac) | `components/rust/version` (`1.99.0-mavericks.2`, the first release whose `rustc` defers its back-fill to a linker that already links `librecaulk.a`, as clang-22's `clang++` does); the released `.pkg` is verified against the release's `SHA256SUMS` and extracted under the build root, never installed. Renovate tracks it (`github-releases` on `Mavergreen/rust`, `-mavericks.N` versioning); a bump repackages. `build/check-rust-pin.sh` refuses a pin whose upstream version is older than Codex's `rust-toolchain.toml` channel (`1.95.0`); a newer one builds it | Rust compiler, Cargo, and target support for `x86_64-apple-darwin` on 10.9 |
| Mavergreen clang-22 (`clang22` on 10.9, `clang22-cross` on a modern Mac, and `libcxx22`) | `components/clang-22/version` (`22.1.1-mavericks.8`). Each pkg is verified against the release's `SHA256SUMS` by `build/fetch-clang-22.sh` and extracted under the build root, never installed. Renovate tracks it (`github-releases` on `Mavergreen/clang-22`, `-mavericks.N` versioning); a bump repackages | C and C++ compiler for Codex's native dependencies (`CC_x86_64_apple_darwin`, `CXX_x86_64_apple_darwin`), and its `clang++` is the linker (`CARGO_TARGET_X86_64_APPLE_DARWIN_LINKER`). `libcxx22` is the libc++ runtime that the build-time `protoc` runs on, natively only. It is never linked into the shipped binaries |
| Mavergreen shipyard | `v1.0.487` or later: that release (shipyard commit `b3b9a91`) added the `codex-cli` registry row the updater and packaging need. The fetch scripts verify their downloads (Rust, clang-22 and `rusty_v8`) with `shipyard_fetch_verified`, called by its canonical name in `build/fetch-release-pkg.sh` and `build/fetch-rusty-v8.sh`, so they do not depend on the `mav_*` aliases. The workflows pin `Mavergreen/shipyard/...@v1`, which Renovate's github-actions manager tracks, and `@v1` moving repackages nothing by itself | SDK, build mode, source fetch, compatibility, and package helpers |
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
native voice runtime, or `codex-resources/voice`; voice support is deferred. The native build on ultimate-hat was last run on 2026-10-15,
in `MAVERICKS_BUILD_ROOT=/Users/schmonz/Library/Caches/mm-build` (macOS sweeps `$TMPDIR` nightly). Both
binaries link and pass the non-interactive smoke checks: see `docs/compatibility-matrix.md`.

## Declared state

- upstream: UPSTREAM_VERSION
- codex-revision: build/codex-revision
- rust: components/rust/version
- clang-22: components/clang-22/version

## Compatibility gate implementation

Both imported Rust executables, `codex` and `codex-code-mode-host`, are checked by shipyard's
`assert_binary_compatible.sh` as CTest tests (`compat_guard_codex`, `compat_guard_codex-code-mode-host`), run by
`shipyard-ctest --preset native|cross`, as mavergreen-gh does. They are not a build-time step.
Shipyard's `mavericks_assert_binary_compatible()` attaches a `POST_BUILD` command to a compiled
target, while CMake does not permit that command on an imported executable. The tests therefore
invoke the same shipyard checker on each exact imported file. The tests `load_paths_codex` and
`load_paths_codex-code-mode-host` run `build/check-load-paths.sh` on each, which refuses any library outside `/usr/lib/` and `/System/Library/` and any `LC_RPATH`:
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
manifest ships as `share/doc/codex-cli/build-manifest`, and the repo's own `README.md` as
`share/doc/codex-cli/README.md`, copied at package time, as mavergreen-gh does, so the pkg carries
whatever the maintainer's edit of it leaves. The pkg has no `codex-voice-host` and no
`codex-resources/voice`, and `build-pkg.sh` refuses an artifact directory that has either.

`tests/package-test.sh PKG CODEX-OUT` checks the pkg, in either mode, with no Bats and no Python:
payload contents and modes, binaries byte-identical to the build, the installed README equal to
`README.md`, the installed `build-manifest`'s `version=` equal to the package version, manifest
identity, a link farm that holds `codex` alone and resolves to a directory holding the host, a clean
upgrade and uninstall, and the updater's bundle ID, feed and comparison version against the registry
and the package version. It runs the pkg's own install scripts against a temporary target root,
never `/`.

`check-readme-reviewed.sh`, run by shipyard's `publish-release.yml`, refuses a release while
`README.md` carries shipyard's unreviewed-README marker line. The maintainer's edit removed it.

The updater is an off-by-default CMake option, `-DCODEX_BUILD_UPDATER=ON`, because it needs `codex-cli`
in the installed shipyard's product registry (`codex-cli dev.mavergreen.codex-cli codex-cli`). The row arrived in shipyard commit `b3b9a91`, released as `v1.0.487`; packaging and the updater were verified against that
registry with no override. It stays off by default, as in mavergreen-gh. The updater never links the CLI binary.

## License notices

Codex is Apache-2.0, whose section 4 requires the license text and the NOTICE file to accompany
redistributed binaries. `build/build-codex.sh` copies `LICENSE` and `NOTICE` from the fetched, pinned
Codex source root into the artifact directory, next to the binaries and `build-manifest`, in both modes
and failing if either is missing or empty. `transfer-artifact.sh` and `verify-artifact.sh` carry and
require them, so a cross artifact moved from the modern Mac has them too. `packaging/build-pkg.sh`
installs them from the artifact, never from a checkout, at `share/doc/codex-cli/LICENSE` and
`share/doc/codex-cli/NOTICE`, and fails without them. `tests/package-test.sh` checks both are in the pkg
and byte-identical to the artifact's.

The binaries are built from Codex's sources as modified by the patches in `patches/` (Apache-2.0
section 4(b)); `patches/README.md` says what each patch changes.

The binaries also contain open-source dependencies under their own licenses, listed in Codex's
pinned [`codex-rs/Cargo.lock`](https://github.com/openai/codex/blob/979011409de0a60b52f179721948e65531d26144/codex-rs/Cargo.lock).
No third-party notices file is shipped, which matches upstream's own releases (maintainer decision,
2026-10-15). Codex's tree at `build/codex-revision` has none: besides `LICENSE` and `NOTICE` it has
only `docs/license.md`, which points at `LICENSE`, and `codex-rs/deny.toml`, cargo-deny's
configuration, which includes a license policy for its dependencies. The link names the commit, so
a Codex bump updates it here along with `build/codex-revision`.

## Deviations

- **Generic updater icon.** The updater passes `ALLOW_GENERIC` and ships no `.icns`: Codex's mark is
  OpenAI's, and this is an unofficial build that must not read as official. `updater/ICON-CREDIT.txt`
  says why and what ends the deviation, as mavergreen-rg does.
- **Codex is not built by CMake.** The CMake project imports the two executables that
  `build/build-codex.sh` made, so the product is packaged by `packaging/build-pkg.sh` from that output
  rather than from CMake install rules.
- **No voice.** The package ships no `codex-voice-host` and no `codex-resources/voice`, so Codex's
  voice features are unsupported. `packaging/build-pkg.sh` refuses an artifact that has either and
  `tests/package-test.sh` checks the payload has neither. Voice is deferred, not dropped:
  nobody has yet tried building `codex-voice-host` on 10.9, so what it needs is unmeasured.
- **Only `codex` is exported to the link farm.** `codex-code-mode-host` stays in the product tree
  beside it, because Codex runs it as a sibling and it is not a command to run by hand; patch 0009
  makes the symlinked `codex` find it.
- **Native TLS is replaced by rustls.** Patch 0001 puts every HTTPS client on rustls, because native-tls
  (Secure Transport) fails every request on 10.9, even with AquaTransport installed. The
  trust store is the keychain's, so a stock 10.9 needs AquaTransport's ModernRootCertificates to
  reach OpenAI. `patches/README.md` has the reasons and what ends the patch: an AquaTransport
  release with the TLS fix native-tls needs.
- **Three defaults differ from upstream's.** Each can be turned on in config, except verification.
  The startup update check (0002) is off because the package manager Codex detects (notably
  Homebrew) may be absent or unable to run, so startup would offer an update path that cannot work.
  The shared background daemon (0003) is off because it runs from a packaged install that a cargo
  build lacks, and its updater installs upstream builds the host may not run; the TUI hosts the
  app server in-process instead. Biometric user verification (0004) reports unsupported because it
  needs LocalAuthentication and Secure Enclave APIs, which 10.9 lacks.

## Conformance deviations

(The section is empty: `check-family-conventions.sh` passes with no check-level exceptions. The
items under "Deviations" are product facts, not exceptions to a family check.)

## Releasing

A merged `UPSTREAM_VERSION` bump releases itself: the push to `main` cuts `-mavericks.1`. A merged
bump of `components/rust/version` or `components/clang-22/version` repackages (`repackage-on-ingredient-bump`).

A packaging-only release of the same source (a new `.N`):

    gh workflow run release.yml -R Mavergreen/codex-cli --ref main -f local_release=true

**Bumping Codex takes two edits, and only one is automatic.** The family has a convention for a tag
pinned together with its commit (Renovate's `git-refs`/`currentDigest`, as in porthole's `SKALIBS_REF`
and recaulk's `components/macports-legacy-support/version`), but it pins both in one file. Here the
tag is `UPSTREAM_VERSION`, which the family requires to be a bare committed version, and the commit is
`build/codex-revision`, which eight scripts and tests read as a bare SHA. Renovate bumps
`UPSTREAM_VERSION` alone, so the gap is guarded rather than closed: `build/check-upstream-pin.sh
--remote` is the first step after install in `release.yml`, and fails the PR before anything is built,
printing the commit that `rust-v<version>` points at and naming `build/codex-revision`. Until that edit
is made on the Renovate branch (with `patches/` refreshed if they no longer apply), the PR stays red
and does not automerge. The same step refuses a prerelease or otherwise non-`x.y.z`
`UPSTREAM_VERSION`: `0.162.0-alpha.1-mavericks.1` has no order the updater can compare, so the form is
unsupported rather than mapped. Follow-up: one file holding both (`<sha> # <version>`, with a second
manager on `UPSTREAM_VERSION` for the same dependency) would close the gap; it needs the readers
updated and shipyard's convention confirmed for two files.

`release.yml` mirrors mavergreen-gh's: a `build` job on `macos-26` (cross build, updater, compat guard tests,
repo tests, pkg, package test, notes, feeds, conformance), `on-mavericks` (installs the cross-built pkg
in a real 10.9 VM and runs `codex --version`, `codex --help`, `codex-code-mode-host --help`, the link
farm's symlinked `codex`, and `codex sandbox -- /usr/bin/true`; no login and no secrets beyond the VM
key), `scan` (key-log scan) and `publish`, which needs `build`, `scan` and `on-mavericks`. The
`conventions` check and `reconcile` backstop are gh's, unchanged. Voice is not built or smoked.

Two CI-specific points:

- CI has no native build to compare against, so the cross configure passes
  `-DCODEX_CROSS_ONLY_MANIFEST=ON`, which runs `build/check-build-manifests.sh --cross-only`: the cross
  manifest is checked against the committed pins (source commit, Rust, clang-22, target, deployment
  target, SDK shape, host protoc). The native-vs-cross comparison is an out-of-band check, like the logged-in smokes: nothing enforces it before a release. Run it with the
  native artifact transferred from ultimate-hat.
- The logged-in smokes (a symlinked `codex` running a `code_mode_only` model) need credentials and
  stay out-of-band checks on ultimate-hat; see `docs/compatibility-matrix.md`.

## Hardware validation

On 2026-10-15, out of band, on ultimate-hat (Mac OS X 10.9.5): the native package and a package of
the cross-built binaries were each installed and passed the non-interactive smokes, the
maintainer's TUI turns, and, for the native one, login and `exec` on a clean `CODEX_HOME`. The native and cross
builds had matching inputs, and matching architecture, deployment target and SDK, linked libraries
and undefined symbols, with no `LC_RPATH`. Their hashes and sizes differ, with expected causes,
partly unmeasured. Results are in `docs/compatibility-matrix.md`:
"Installed native package on 10.9", "Native versus cross" and "Cross binaries on 10.9".

Open shipyard dependency: a pkg built on a modern Mac that tags files with
`com.apple.provenance` (macOS 27) carries `._` entries and is not releasable until shipyard fixes
it. The cross pkg was therefore packaged on 10.9. CI-built pkgs are likely fine, but that is
unmeasured, and measuring it is shipyard's.
