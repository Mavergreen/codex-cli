# Build ingredients

| Ingredient | Pin | Use |
| --- | --- | --- |
| OpenAI Codex | `components/codex/version` `0.161.0`; `build/codex-revision` `979011409de0a60b52f179721948e65531d26144`. Renovate (`github-releases` on `openai/codex`, tags `rust-v<x.y.z>`, so prereleases such as `rust-v0.162.0-alpha.1` never match) bumps `components/codex/version` only; the commit is a manual edit, see "Releasing". A bump publishes a Codex build, never a pkg | CLI source and Cargo workspace, built into the Codex builds the package installs |
| Mavergreen Rust toolchain (`rust` on 10.9, `rust-cross` on a modern Mac) | `components/rust/version` (`1.99.0-mavericks.2`, the first release whose `rustc` defers its back-fill to a linker that already links `librecaulk.a`, as clang-22's `clang++` does); the released `.pkg` is verified against the release's `SHA256SUMS` and extracted under the build root, never installed. Renovate tracks it (`github-releases` on `Mavergreen/rust`, `-mavericks.N` versioning); a merged bump publishes a Codex build, never a pkg. `build/check-rust-pin.sh` refuses a pin whose upstream version is older than Codex's `rust-toolchain.toml` channel (`1.95.0`); a newer one builds it | Rust compiler, Cargo, and target support for `x86_64-apple-darwin` on 10.9 |
| Mavergreen clang-22 (`clang22` on 10.9, `clang22-cross` on a modern Mac, and `libcxx22`) | `components/clang-22/version` (`22.1.1-mavericks.8`). Each pkg is verified against the release's `SHA256SUMS` by `build/fetch-clang-22.sh` and extracted under the build root, never installed. Renovate tracks it (`github-releases` on `Mavergreen/clang-22`, `-mavericks.N` versioning); a merged bump publishes a Codex build, never a pkg | C and C++ compiler for Codex's native dependencies (`CC_x86_64_apple_darwin`, `CXX_x86_64_apple_darwin`), and its `clang++` is the linker (`CARGO_TARGET_X86_64_APPLE_DARWIN_LINKER`). `libcxx22` is the libc++ runtime that the build-time `protoc` runs on, natively only. It is never linked into the shipped binaries |
| Mavergreen shipyard | `v1.0.487` or later: that release (shipyard commit `b3b9a91`) added the `codex-cli` registry row the updater and packaging need. The fetch scripts verify their downloads (Rust, clang-22 and `rusty_v8`) with `shipyard_fetch_verified`, called by its canonical name in `build/fetch-release-pkg.sh` and `build/fetch-rusty-v8.sh`, so they do not depend on the `mav_*` aliases. The workflows pin `Mavergreen/shipyard/...@v1`, which Renovate's github-actions manager tracks, and `@v1` moving publishes nothing by itself | SDK, build mode, source fetch, compatibility, and package helpers |
| Wowfunhappy's AquaTransport (runtime requirement, not a build input) | `components/aquatransport/min-version`, the oldest release that has the TLS fixes Codex's native-tls needs. Pending: it holds `unreleased` until such a release exists. While it does, no pkg can be released (`build/check-aquatransport-pin.sh`, run by the release workflow), both workflows' 10.9 jobs fail at once and say so, so no build is published either, and the nightly `reconcile.yml` dispatches nothing. The pin is copied to `tree/share/codex-cli/aquatransport-min-version`, and a test keeps the two identical. When the pin moves, the Mavericks VM image (Mavergreen/mavericks-vm) must carry at least that release; the VM jobs refuse an older one. Not on Renovate: AquaTransport is a dmg, not a tracked release | The launcher reads the `Wowfunhappy.AquaTransport` pkg receipt (`pkgutil --pkg-info`, `YYYY.MM.DD`) and refuses to run Codex without it or with an older one, because Codex's HTTPS clients use native-tls, which goes through AquaTransport on 10.9 (patch 0001 once forced rustls instead). AquaTransport speaks TLS 1.0 to 1.3, so Codex's native-tls to rustls fallback, which exists because modern macOS's Secure Transport lacks TLS 1.3, is not needed here. Two paths still verify through rustls, with roots that `rustls-native-certs` reads from the 10.9 keychain: WebSockets (`codex-websocket-client` always uses rustls) and the OTLP gRPC exporter. On those paths AquaTransport's ModernRootCertificates may still matter, which release testing checks. Five `codex-http-client` tests of that fallback fail on 10.9, a test-only gap: AquaTransport's `my_SSLHandshake` reports every handshake failure as errSSLClosedAbort (-9806), where stock Secure Transport gives -9836 for the protocol_version alert they send. They pass once AquaTransport returns stock's codes. The family's 10.9 VM image already carries AquaTransport, so the VM jobs install nothing and only check the receipt |
| Sparkle, in the updater | shipyard's `fetch_sparkle_framework.sh`, pinned by hash there; the family EdDSA public key is `updater/ed25519_key.pub`, the same file every Mavergreen product carries | Update channel for the package itself: the launcher, the installer and the updater. Codex builds never go through it. Untrackable here: shipyard owns the Sparkle pin |
| OpenAI prebuilt `rusty_v8` | Derived from Codex's `Cargo.lock` (`v8` package), so a Codex bump moves it with no separate pin and Renovate tracks nothing extra; verified against upstream's published `.sha256` checksums file | Static V8 archive linked into `codex-code-mode-host`; prebuilt because building V8 needs Chromium's toolchain and python3, which a native 10.9 build lacks |

This product ships in two streams from this one repo. **Codex builds** are what users run: each is
one tarball in upstream's package layout, published to this repo's `codex-builds` release (the
builds channel, below) and installed by `codex update` or the launcher's first run into the user's
`~/.codex/packages/standalone`. The **pkg**, `codex-cli-<YYYYMMDD.N>.pkg`, carries no Codex binary:
only the launcher, the installer, `requires` and the Sparkle updater. Every ingredient in the table
above is an ingredient of the Codex builds; the pkg is built from `tree/`, `updater/` and shipyard
alone, so it is its own upstream, versioned by `UPSTREAM_VERSION` (the pkg's own date, `YYYYMMDD`).
`components/codex/min-pkg` is the oldest pkg (`YYYYMMDD.N`) the current source needs, or empty; each
build records it in its channel metadata (see "A build that needs a newer pkg").

Not ingredients: `rg` and `ed25519` are required at install and run time
(`tree/share/codex-cli/requires`, checked by the pkg's preinstall and by the launcher), not shipped
in this package. Each build's `codex-path/rg` is a two-line script that runs the `rg` package's
`/usr/local/mavergreen/rg/bin/rg`, so no other `rg` is fetched or pinned, and the installer checks
each build's signature with the `ed25519` package's `ed25519-verify`.

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

`codex-cli` and `codex-code-mode-host` are built and transferred together: Codex finds the host in
its package's `bin/`. The host links V8, so the build fetches OpenAI's prebuilt
`rusty_v8` archive with `build/fetch-rusty-v8.sh` (the one declared non-Mavergreen input) and records
`rusty_v8_version` in the build manifest. No build includes `codex-voice-host`, the
native voice runtime, or `codex-resources/voice`; voice support is deferred. The native build on ultimate-hat was last run on 2026-10-17,
in `MAVERICKS_BUILD_ROOT=/Users/schmonz/Library/Caches/mm-build` (macOS sweeps `$TMPDIR` nightly). Testing the
current self-updating layout end to end on 10.9 waits for the AquaTransport release with the TLS fixes
Codex needs: see `docs/compatibility-matrix.md`.

## Declared state

- upstream: UPSTREAM_VERSION

Only the pkg's own input is declared, as in mavergreen-claude-code. The Codex and toolchain pins
move the Codex builds, not the pkg; declaring them would make the nightly `reconcile` backstop cut a
pkg for every Codex bump, which is exactly what the builds stream exists to avoid. The builds
channel has its own backstop in `reconcile.yml` (see "Releasing").

## No repackage-on-ingredient-bump caller here

The pkg bakes in no build ingredient: it carries no Codex binary, so `components/codex/version`,
`build/codex-revision`, `components/rust/version`, `components/clang-22/version` and `patches/` are
ingredients of the Codex builds alone, as is `packaging/build-codex-package.sh`, which lays out each
build's tarball. A merged change to any of them publishes a build through `builds.yml`'s own push
filter, and a caller would only dispatch a pkg release that changes nothing. The pkg's other
inputs are `shipyard@v1`, whose moving tag no path filter can observe, and its own `tree/` and
`updater/`, which a person releases by dispatch. Add a caller the day the pkg bakes in a file-based
ingredient pin.

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

CMake registers these four tests only when it finds a build in the build root's `codex-native` or
`codex-cross`, since configuring for the pkg needs no Codex. `builds.yml` fails if any of the four
is missing, so a build that is not where CMake looks cannot pass unguarded. Only the updater is
compiled for the pkg, and it is guarded as it is built.

## Packaging

**The pkg.** `packaging/build-pkg.sh UPDATER-APP VERSION OUT-DIR` stages `tree/` as committed at
`HEAD` (it warns about uncommitted changes there, which it leaves out), the repo's `README.md` and the
updater under `/usr/local/mavergreen/codex-cli`, and wraps them in `OUT-DIR/codex-cli-VERSION.pkg`
with shipyard's `stage_product.sh`, `build_component_pkg.sh` and `set_install_floor.sh`; nothing is
hand-written. `VERSION` is the pkg's own `YYYYMMDD.N`. The tree is:

| Path under `/usr/local/mavergreen/codex-cli` | What |
| --- | --- |
| `bin/codex` | the launcher, a shell script, and the only file exported to `/usr/local/mavergreen/bin` |
| `libexec/codex-cli/lib.sh`, `link.sh` | the launcher's modules |
| `libexec/codex-cli/install.sh` | the installer, derived from upstream's `install.sh` (see `PROVENANCE.md`) |
| `share/codex-cli/requires` | `rg` and `ed25519`, which the preinstall and the launcher require |
| `share/codex-cli/ed25519_key.pub` | the family EdDSA public key, against which the installer checks each build's signature |
| `share/doc/codex-cli/` | the repo's `README.md`, copied at package time as mavergreen-gh does, and the `LICENSE` and `NOTICE` of Codex, which the installer is derived from |

The updater is installed in `/Library/Application Support/Mavergreen/codex-cli-updater.app`, with
its LaunchAgent. `build-pkg.sh` refuses a payload holding any Mach-O file or a Codex binary, and
`tests/package-test.sh PKG` checks the pkg with no Bats and no Python: exactly that payload, no
Codex binary, a preinstall that requires each product in `requires`, the link farm exporting
`codex` alone and resolving to the launcher, a clean upgrade and uninstall (run against a temporary
target root, never `/`), and the updater's bundle ID, feed and versions against shipyard's
registry and the pkg's version.

**The launcher.** `/usr/local/mavergreen/bin/codex` resolves its own symlinks, sources its modules,
checks `requires`, and then runs the user's Codex: `${CODEX_HOME:-~/.codex}/packages/standalone/current/bin/codex`,
with the arguments unchanged, when that is a complete Mavergreen build (its `codex-package.json`
names a `mavergreenBuild`). On the first run there is none, so it says `installing Codex (first
run; this downloads Codex and can take a minute)`, runs the installer non-interactively, and then
runs what it installed; if the installer fails, it says why and exits 1. It seeds the newest build
`latest.json` names, as Claude's launcher does, not a build pinned in the pkg as pi's does: the
retention rule below would delete a pinned build within months and break an older pkg's first run.
It points `~/.local/bin/codex` at itself, as Claude's launcher does with `claude`, unless that path
is someone else's, which it leaves alone and mentions once; the installer never touches it or a
shell profile, so there is one `codex` on `PATH`.

**The installer.** `libexec/codex-cli/install.sh` is what both the launcher's first run and
`codex update` run. It reads `latest.json` (or `codex-build-<ID>.json` for `--release <ID>`) from the
builds channel, checks its signature against `share/codex-cli/ed25519_key.pub` before parsing it,
downloads the tarball it names, checks the sha256 the signed metadata gives, stages it, and only
then moves `current`, under upstream's lock and in upstream's layout. A build already installed says
so. It also implements the guarded modes the app-server daemon's background update loop runs it
in. Its header lists every change from upstream's.

**A Codex build.** `packaging/build-codex-package.sh CODEX-OUT BUILD-ID OUT-DIR` lays a build's
artifact directory (`codex-native` or `codex-cross`) out as upstream's package:
`bin/codex`, `bin/codex-code-mode-host`, an empty `codex-resources/`, `codex-path/rg` (a script that
execs the `rg` package's `rg`), `codex-package.json` (upstream's fields plus `"mavergreenBuild":"<ID>"`), and
the artifact's `build-manifest`, `LICENSE` and `NOTICE`, in
`OUT-DIR/codex-package-x86_64-apple-darwin-<ID>.tar.gz`. It refuses an artifact with a voice
runtime. Upstream's macOS package can also carry OpenAI's prebuilt zsh fork in `codex-resources/`;
this one never does (see "Deviations").

`check-readme-reviewed.sh`, run by shipyard's `publish-release.yml`, refuses a release while
`README.md` carries shipyard's unreviewed-README marker line. The maintainer's edit removed it.

The updater is an off-by-default CMake option, `-DCODEX_BUILD_UPDATER=ON`, because it needs `codex-cli`
in the installed shipyard's product registry (`codex-cli dev.mavergreen.codex-cli codex-cli`). The row arrived in shipyard commit `b3b9a91`, released as `v1.0.487`; packaging and the updater were verified against that
registry with no override. It stays off by default, as in mavergreen-gh. The updater's version is the
pkg's own, from `VERSION` (else `UPSTREAM_VERSION`), as mavergreen-claude-code's is, because Sparkle
compares the feed's version with the bundle's. The updater never links the CLI binary.

## The builds channel

The channel is the GitHub release `codex-builds` on `Mavergreen/codex-cli`, titled "Codex builds
(fetched by codex update)" and created once with `--latest=false`, so it is never the release
GitHub marks Latest; the family's Sparkle feed is the Latest release's, which is always a pkg. Its
tag never moves. Everything reads it at its fixed download URL,
`https://github.com/Mavergreen/codex-cli/releases/download/codex-builds/`, never through the GitHub
API and its anonymous limit.

| Asset | What |
| --- | --- |
| `codex-package-x86_64-apple-darwin-<ID>.tar.gz` | one build |
| `codex-build-<ID>.json`, `.json.sig` | that build's metadata and its signature |
| `latest.json`, `latest.json.sig` | byte copies of the newest build's metadata and signature |

`<ID>` is the build identity, `<x.y.z>-mavericks.<N>`: Codex's version and this product's build
number for it, from 1. `codex --version` prints only `x.y.z`; `codex doctor` and the startup notice
show the identity. The metadata is one line shaped like a GitHub release, so the installer's parser
(upstream's) reads it: `tag_name` (`rust-v<ID>`), `mavergreen_build`, `mavergreen_codex_version`,
`mavergreen_min_pkg`, `mavergreen_state` (the build state below) and one asset with its
`sha256:` digest. The signature is the base64 line that the family EdDSA key's `ed25519-sign`
prints for the metadata file's bytes; the installer refuses metadata whose signature does not
verify, and the sha256 inside then vouches for the tarball.

`build/build-id.sh` decides each build's identity and whether to publish it. The build state is a
sha256 over, in order, `components/codex/version`, `build/codex-revision`, `components/rust/version`,
`components/clang-22/version`, every `patches/*.patch` in `LC_ALL=C` order, and
`packaging/build-codex-package.sh`, which decides what each tarball holds. A run publishes only
when that state differs from the newest build of the same Codex version on the channel, and the
build number is the next one for that version; a dispatch with `rebuild` always takes the next.
`build/channel-json.sh` writes the metadata, and `build/channel-publish.sh` signs and uploads
(below). It refuses a build older than one already on the channel, and a same-numbered build
whose metadata differs.

**Retention.** After each publish, `build/channel-prune.sh` keeps a build if it is one of the newest
10 builds, the last build of one of the newest 30 `major.minor`s, or the last build of a minor
divisible by 10 or of a major (kept forever); "last" is the highest patch, then the highest build
number. Everything else is deleted. A build's membership depends only on its own version and what was
published after it, so a build kept forever is never deleted later. The counts are
`channel-publish.sh upload`'s `--keep-newest` and `--keep-minors`.

**A build that needs a newer pkg.** When `components/codex/min-pkg` names a pkg version, every build
records it as `mavergreen_min_pkg`, and `channel-publish.sh` refuses to publish a build that names a
pkg newer than the repo's Latest release. The installer compares it with the installed pkg's
`mavergreen.plist` version: when the pkg is older, it installs nothing and exits 3. A run with
someone at the terminal opens the package's updater; a guarded run, such as the daemon's background
update, only says why. The installer never falls back to an older build the installed pkg could
run.

## License notices

Codex is Apache-2.0, whose section 4 requires the license text and the NOTICE file to accompany
redistributed binaries. `build/build-codex.sh` copies `LICENSE` and `NOTICE` from the fetched, pinned
Codex source root into the artifact directory, next to the binaries and `build-manifest`, in both modes
and failing if either is missing or empty. `transfer-artifact.sh` and `verify-artifact.sh` carry and
require them, so a cross artifact moved from the modern Mac has them too.
`packaging/build-codex-package.sh` puts the artifact's copies in every build's tarball, beside the
binaries, and fails without them. The pkg carries no Codex binary, but its installer is derived from
Codex's `install.sh`, so the pkg carries Codex's `LICENSE` and `NOTICE` too, from
`tree/share/doc/codex-cli/`, and `tests/package-test.sh` checks both are in the pkg.

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
  `build/build-codex.sh` made, to run the compatibility guards on them; each build is packaged by
  `packaging/build-codex-package.sh` from that output rather than from CMake install rules.
- **Codex is installed per user, not by the pkg.** The pkg installs a launcher, and Codex itself
  lands in each user's `~/.codex/packages/standalone` on first run, as upstream's standalone install
  does. `sudo mavergreen uninstall codex-cli` removes the launcher, the installer and the updater,
  and leaves every user's `~/.codex` alone, as Claude's uninstall leaves users' home directories
  alone.
- **No voice.** No build has `codex-voice-host` or `codex-resources/voice`, so Codex's voice
  features are unsupported. `packaging/build-codex-package.sh` refuses an artifact that has either.
  Voice is deferred, not dropped: nobody has yet tried building `codex-voice-host` on 10.9, so what
  it needs is unmeasured.
- **No `shell_zsh_fork`.** Upstream's macOS package carries OpenAI's prebuilt zsh fork in
  `codex-resources/` for this feature, which is under development and off by default. It is
  OpenAI's binary, so no build carries it, and the feature is unsupported.
- **No `codex app`.** `codex app` downloads and opens OpenAI's desktop app, which is not a Codex CLI
  build and does not run on 10.9. It is left as upstream's, unpatched, and unsupported.
- **`codex-path/rg` is the family's `rg`.** Upstream's package carries BurntSushi's macOS `rg` in
  `codex-path/`, which Codex puts first on the agent shell's `PATH`. Here it is a script,
  `exec /usr/local/mavergreen/rg/bin/rg "$@"`, for the `rg` package the pkg requires, as pi uses
  that `rg`. It is not a link because the app-server daemon copies the package and refuses any link
  that resolves outside it.
- **Updates come from this product's builds.** The startup check, `codex update`, `codex doctor`
  and the app-server daemon's background updates all use the builds channel and the package's
  installer, never OpenAI's releases (0011 to 0013). Their wording and defaults are upstream's: the
  startup check and the daemon are on.
- **Biometric user verification reports unsupported** (0004), because it needs LocalAuthentication
  and Secure Enclave APIs, which 10.9 lacks. It cannot be turned on.

## Conformance deviations

- scheme: the package is its own upstream (Codex reaches users through the builds channel, pinned in components/codex/version), so it versions itself by date as YYYYMMDD.N with no -mavericks.N axis
- builds-channel: Codex builds are signed and published to this repo's codex-builds release by build/channel-publish.sh from .github/workflows/builds.yml, not by shipyard, until shipyard has machinery for a builds channel

The items under "Deviations" are product facts, not exceptions to a family check.

## Releasing

Two streams are released from this repo, and no ordinary commit to `main` publishes anything else.

| Stream | What | Version | Published by | Offered by |
| --- | --- | --- | --- | --- |
| Codex builds | one tarball per build, on the `codex-builds` channel | `<x.y.z>-mavericks.<N>` | `builds.yml`, when a push to `main` changes the build state (a merged bump of `components/codex/version`, `build/codex-revision`, `components/rust/version` or `components/clang-22/version`, or a merged change to `patches/*.patch` or `packaging/build-codex-package.sh`), or by dispatch | `codex` itself: the startup notice, `codex update`, and the daemon's background updates |
| The pkg | the launcher, the installer, `requires` and the updater | `YYYYMMDD.N` | `release.yml`, by dispatch only | Sparkle |

A packaging-only release (a new `.N` of `UPSTREAM_VERSION`'s date, or a new date after bumping it):

    gh workflow run release.yml -R Mavergreen/codex-cli --ref main -f local_release=true

Another build of the same Codex version, with nothing in the build state changed:

    gh workflow run builds.yml -R Mavergreen/codex-cli --ref main -f rebuild=true

The first release is both, in this order: a build on the channel, then the first pkg. A pkg must
never be published while the channel is empty, or every first run fails; `release.yml`'s
`on-mavericks` job fails when the channel names no build.

Nothing publishes while `components/aquatransport/min-version` says `unreleased`. The test pkg
`builds.yml` installs on 10.9 carries that pin, and its launcher refuses every command, so both
workflows' `on-mavericks` jobs fail as they start ("AquaTransport pin is unreleased; set it when the
fixed AquaTransport ships"), `builds.yml`'s `publish` never runs, and the nightly backstops dispatch
nothing. Merging to `main` before then publishes no build. The first build publishes once the pin
names the fixed AquaTransport release (in both pin files) and the VM image carries it: the
next nightly reconcile dispatches `builds.yml`, since the channel has no `latest.json`, or dispatch it
by hand:

    gh workflow run builds.yml -R Mavergreen/codex-cli --ref main

Then the first pkg, by the `local_release` dispatch above (shipyard's nightly backstop may dispatch
`release.yml` as well); its `on-mavericks` holds it back until the build is on the channel.

**Bumping Codex takes two edits, and only one is automatic.** The family has a convention for a tag
pinned together with its commit (Renovate's `git-refs`/`currentDigest`, as in porthole's `SKALIBS_REF`
and recaulk's `components/macports-legacy-support/version`), but it pins both in one file. Here the
tag is `components/codex/version`, and the commit is `build/codex-revision`, which scripts and tests
read as a bare SHA. Renovate bumps `components/codex/version` alone, so the gap is guarded rather
than closed: `build/check-upstream-pin.sh --remote` is the first step after install in `builds.yml`,
and fails the PR before anything is built, printing the commit that `rust-v<version>` points at and
naming `build/codex-revision`. Until that edit is made on the Renovate branch (with `patches/`
refreshed if they no longer apply), the PR stays red and does not automerge. The same step refuses
a prerelease or otherwise non-`x.y.z` version: `0.162.0-alpha.1-mavericks.1` has no order the
update check can compare, so the form is unsupported rather than mapped. Follow-up: one file holding
both (`<sha> # <version>`, with a second manager on the version for the same dependency) would close
the gap; it needs the readers updated and shipyard's convention confirmed for two files.

`builds.yml` has a `codex-build` job on `macos-26` (the upstream-pin check, the build identity and
publish decision, the cross build, the updater, the compat guard tests, the repo tests, the
tarball and its metadata, a second tarball one build number later, signing with the family key, a
check that the signature verifies against the key the pkg ships, and a test pkg), `on-mavericks`,
`scan` (key-log scan of the job that held the key) and `publish`, which needs all three and holds
no key. `on-mavericks` installs the `rg` and `ed25519` packages and the test pkg in a real 10.9 VM,
points the launcher at the staged channel with `CODEX_BUILDS_URL`, and checks that the first run
seeds the build, `codex --version`, `--help`, `codex-code-mode-host --help`, that the host is not
exported, `codex sandbox -- /usr/bin/true`, that a daemon start seeds the daemon's own package
root with the build, that `codex update` moves to the second build, and that `codex app-server daemon
update` runs the package's installer in the daemon's guarded mode, moves the daemon's root to the
second build and restarts the running daemon into it. Before the VM starts, the job fails if the
AquaTransport pin is `unreleased`, and the guest refuses an AquaTransport older than the pin. A run
that does not publish signs in the guest with a key made there.
`publish` (`build/channel-publish.sh upload`) verifies every signature, uploads the build,
replaces `latest.json`, re-points it if a concurrent run published a newer build meanwhile, and
prunes. Each run that can publish is alone in its concurrency group, so none is evicted while
queued.

`release.yml` has a `build` job on `macos-26` (the version step, the updater and its compat guard,
the repo tests, the pkg, the package test, notes, feeds, conformance), `on-mavericks` (installs the
pkg and its requirements in a real 10.9 VM, and checks that the first run seeds the build the
published channel names, `codex --help`, `codex-code-mode-host --help`, that the host is not
exported, and `codex sandbox -- /usr/bin/true`; no login and no secrets beyond the VM key), `scan`
and `publish`, which needs `build`, `scan` and `on-mavericks`. The pkg becomes the repo's Latest.

The nightly `reconcile.yml` runs shipyard's backstop for the pkg and its own for the channel: when
the channel's newest build was not made from `main`'s build state, and no `builds.yml` run is in
flight, it dispatches `builds.yml`. While the AquaTransport pin is `unreleased` it runs neither, and
logs a notice instead: no run could publish, and each would cost a 4-hour macOS build. The
`conventions` check is gh's, unchanged. Voice is not built or smoked.

Two CI-specific points:

- CI has no native build to compare against, so the cross configure passes
  `-DCODEX_CROSS_ONLY_MANIFEST=ON`, which runs `build/check-build-manifests.sh --cross-only`: the cross
  manifest is checked against the committed pins (source commit, Rust, clang-22, target, deployment
  target, SDK shape, host protoc). The native-vs-cross comparison is an out-of-band check, like the logged-in smokes: nothing enforces it before a release. Run it with the
  native artifact transferred from ultimate-hat.
- The logged-in smokes (an `exec` turn with a `code_mode_only` model, run through the launcher) need
  credentials and stay out-of-band checks on ultimate-hat; see `docs/compatibility-matrix.md`.

## Hardware validation

The current self-updating layout (the launcher, the installer and the builds channel) is not yet
tested end to end on 10.9 hardware. That waits for the AquaTransport release with the TLS fixes Codex needs;
the checks it will run are listed as pending in `docs/compatibility-matrix.md`.

An earlier patch series, which still had 0001 (every HTTPS client on rustls), was run through the
same layout on 2026-10-17 on ultimate-hat, natively built, from a `file://` channel with a scratch
`HOME` and `CODEX_HOME`. The first run seeded the build; a `code_mode_only` `exec` turn ran through
the launcher; the startup notice offered the second build (from a seeded version cache, since the
channel was not live); `codex update` installed it (through a test shim for the fixed installer
path); `--release` stepped back; `check_for_update_on_startup = false` hid the notice; and
`codex doctor` reported the standalone installer. The daemon did not
start (`package link escapes its root`), which is why `codex-path/rg` became a script. Results are
in `docs/compatibility-matrix.md`, "The self-updating Codex, end to end on 10.9".

With the earlier packaging, which put both binaries in the pkg: on 2026-10-15, out of band, on ultimate-hat (Mac OS X 10.9.5): the native package and a package of
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
