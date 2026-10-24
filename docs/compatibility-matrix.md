# Compatibility matrix

What building and running Codex 0.161.0 on Mac OS X 10.9 needed, one row per symptom. Wowfunhappy's
native 10.9 build of 0.161.0 met some of these first. "Source" says whether this build reproduced
them. The native rows were measured on ultimate-hat (Mac OS X 10.9.5, x86_64) with
`sh build/build-codex.sh native`: on 2026-10-13 with Mavergreen/rust `1.95.0-mavericks.2`, and on
2026-10-14 with `1.99.0-mavericks.2`.

## Build

| Symptom | Cause | Fix | Ingredient | Source |
|---|---|---|---|---|
| `error: cannot update the lock file .../codex-rs/Cargo.lock because --locked was passed to prevent this` before anything compiles | The `rust-v0.161.0` tag sets `[workspace.package] version = "0.161.0"`, but its `Cargo.lock` still records `0.0.0` for all 160 workspace packages. Not specific to 10.9 | `build/fetch-codex.sh` writes the workspace version into the `Cargo.lock` entries that have no `source` and are at `0.0.0`, after the patch series. It fails if it finds none. `--locked` still refuses any other drift | none (recipe) | measured here; not in Wowfunhappy's build, which used `cargo install` on a long-lived tree |
| A rerun fails with `pinned source checkout is dirty before patch application` | `fetch-codex.sh` refused the checkout its own patches had left dirty | `fetch-codex.sh` stamps the prepared tree under `.git/` (the patch series, the script, `components/codex/version`, and the tree state including ignored files) and reuses it unchanged, keeping Cargo's mtime fingerprints. Any other dirty tree is reset and prepared again | none (recipe) | measured here |
| `aws-lc-sys`: `rsaz-4k-avx512.S: error: invalid instruction mnemonic 'kmovb'` (and every other AVX-512 line), then `c11.c: fatal error: 'stdatomic.h' file not found` | 10.9's `cc` is Apple clang-600.0.57 (LLVM 3.5svn). It cannot assemble AVX-512 and has no C11 `<stdatomic.h>` | `CC_x86_64_apple_darwin` / `CXX_x86_64_apple_darwin` are clang-22's `clang` / `clang++`, in both modes. The target-specific names keep a cross build's aarch64 build scripts on the host compiler | Mavergreen/clang-22 `22.1.1-mavericks.8` (`clang22` natively, `clang22-cross` on Apple Silicon), `components/clang-22/version`, fetched by `build/fetch-clang-22.sh` | measured here. It is the same class as Wowfunhappy's "a C dependency rejects C11 `static_assert`", and has the same fix. The `static_assert` error itself was not seen, because aws-lc failed first |
| clang-22: `no such sysroot directory: .../clang22/bin/../SDKs/MacOSX10.9.sdk`, then `'AvailabilityMacros.h' file not found` | The clang-22 pkg ships `SDKs` as a link to an empty `var/<product>/SDKs`, and this host's `xcrun --show-sdk-path` prints nothing | Both modes use shipyard's pinned 10.9 SDK (`fetch_sdk.sh`): natively as `SDKROOT`; in cross, where `SDKROOT` would also reach the aarch64 build scripts, as `-isysroot` link args for the x86_64 target alone (measured on 2026-10-14 on an arm64 Mac running macOS 27.0.1: every aarch64 build script and proc macro linked, and the x86_64 C objects carry `LC_VERSION_MIN_MACOSX 10.9`). `build-codex.sh` links it in as the extracted product's `SDKs/MacOSX10.9.sdk`. Both manifests record the SDK by name (`sdk=MacOSX10.9.sdk`), and `check-build-manifests.sh` requires it to match | shipyard's SDK pin | measured here, on a test compile with the extracted clang22 |
| `protoc failed: dyld: Symbol not found: __ZNSt19bad_optional_accessD1Ev ... Expected in: /usr/lib/libc++.1.dylib` (build script of `codex-code-mode-protocol`) | `protoc-bin-vendored` 3.2.0's macOS `protoc` needs a newer libc++ than 10.9's, and Codex's `build.rs` runs it by a fixed path | Natively, cargo runs under `DYLD_INSERT_LIBRARIES=<libcxx22>/lib/libc++abi.1.dylib:<libcxx22>/lib/libc++.1.dylib`, `DYLD_FORCE_FLAT_NAMESPACE=1` and `DYLD_LIBRARY_PATH=<libcxx22>/lib`. The last one makes libc++'s absolute libc++abi dependency resolve in the extracted copy, not in a host-installed `/usr/local/mavergreen/libcxx22`. This is build-time only. The cross host's `protoc` is the aarch64 one on a modern libc++ and gets none of this. The manifest records `protoc_runtime`, and `check-build-manifests.sh` allows only that difference | Mavergreen/clang-22 `libcxx22` from the same release | measured by Wowfunhappy, reproduced here |
| `linking with cc failed ... clang: error: unable to execute command: posix_spawn failed: Argument list too long` at `codex-code-mode-host`'s final link (1355 objects) | 10.9's clang 3.5 cannot pass that many arguments to `ld`, and it has no response file | `CARGO_TARGET_X86_64_APPLE_DARWIN_LINKER` is clang-22's `clang++`, in both modes. It links through lld with a response file, and its cfg adds `librecaulk.a`. V8's C++ runtime is Chromium's own libc++, carried in the v8 crate's archive; the cfg's `libc++.a` only fills gaps. Mavergreen/rust `1.99.0-mavericks.2`'s `rustc` sees that the linker already links `librecaulk.a` and adds only `-mmacosx-version-min=10.9`. With `1.95.0-mavericks.2` it also force-loaded `libMacportsLegacySupport.a`, and every link failed on duplicate symbols (`linkat`, `openat`, `sysconf`, ...). On 2026-10-14, `codex-code-mode-host` linked, as did every build script. The manifest has no linker field, because the linker follows `clang_version`, which both modes must match | Mavergreen/clang-22 `22.1.1-mavericks.8` (`clang22` natively, `clang22-cross` on Apple Silicon) with Mavergreen/rust `1.99.0-mavericks.2` | measured by Wowfunhappy, reproduced here |
| `ld64.lld: error: undefined symbol: posix_spawn_file_actions_addchdir_np`, `>>> referenced by posix_child.rs:178 (utils/pty/src/posix_child.rs:178)`, at the final links of `codex` and `logs_client` (both `codex-cli` bins) | `codex-utils-pty` declares `posix_spawn_file_actions_addchdir_np` (macOS 10.15) as a hard extern on macOS. 10.9's libSystem has `posix_spawn_file_actions_addinherit_np` but not `addchdir_np` (`dlsym` returns NULL for it on ultimate-hat), and Recaulk `20261012.1` does not back-fill it | `patches/0008-pty-addchdir-runtime-lookup.patch` widens the glibc `dlsym` lookup's cfg to macOS. On 10.9 the lookup fails, `NativeChild::spawn` returns `Ok(None)`, and the spawn falls back to `tokio::process::Command`. On 10.15 and later the lookup finds the function, so nothing changes there. Measured on 2026-10-14: `codex` links, does not import the symbol, and an app-server `command/exec` with a `cwd` (piped and tty) runs in that directory | none (Codex patch) | measured here. Not in Wowfunhappy's notes: their own polyfill may have provided it |
| `otool -L codex` lists `/opt/pkg/lib/liblzma.5.dylib` and `/opt/pkg/lib/libiconv.2.dylib`. The build succeeds and shipyard's compat guard passes | `lzma-sys` asks pkg-config for liblzma, and the one on `PATH` is ultimate-hat's pkgsrc `/opt/pkg/bin/pkg-config`. Its `-L/opt/pkg/lib` then makes `-liconv` resolve to pkgsrc's libiconv too. `aws-lc-sys` and `bzip2-sys` also probed `/opt/pkg` through pkg-config, and found nothing | `PKG_CONFIG_x86_64_apple_darwin=/usr/bin/false` in both modes, so no host pkg-config answers for the 10.9 target. Natively the host is also x86_64-apple-darwin, so the variable covers host build scripts too, which is harmless: they run on this host and ship nothing. `lzma-sys` then builds its bundled xz statically with clang-22 (`rustc-link-lib=static=lzma`), and `codex` links only OS libraries (`/usr/lib/libiconv.2.dylib`) | none (recipe) | measured here |
| `failed to parse manifest at .../cargo-home/registry/src/.../approx-0.5.1/Cargo.toml`, `can't find library approx` on a rerun, before anything compiles | macOS's daily `dirhelper` sweep (03:35) deletes files under `$TMPDIR` that have gone unaccessed for 3 days. The default build root is `${TMPDIR}/mm-build`, and crate sources keep their packaged mtimes (2006 for `approx`), so the sweep removed most of `registry/src` but left each crate's `.cargo-ok`, so Cargo did not extract it again | this host now builds in `MAVERICKS_BUILD_ROOT=/Users/schmonz/Library/Caches/mm-build`, outside the sweep (maintainer decision, 2026-10-14). The default in `resolve-build-root.sh` is unchanged | none | measured here, on the first rerun the next day |
| Link or rebuild times impractical | upstream's release profile uses `lto = "thin"` | not applied | none | not reproduced. On ultimate-hat a full native build from an empty target dir took 54 minutes (`Finished ... in 54m 06s`), and so did the rebuild after the pkg-config change (`54m 27s`). How much of that is the LTO link was not measured |

Build 8 (2026-10-14) finished with only known warnings: rustc's notice that its minimum supported
deployment target is 10.12, `proc-macro-error2` v2.0.1's future-incompatibility report, deprecations
of `fetch_update` (renamed `try_update`) because Codex's 1.95 channel is built with 1.99, and
upstream's own lints (trailing semicolons in `bail!`, unused imports and `mut`).

## Running on 10.9

| Check | Result |
|---|---|
| `codex --version` prints `codex-cli 0.161.0` | passed on 2026-10-14: `codex-cli 0.161.0`, exit 0 |
| `codex-code-mode-host --help` exits 0 | passed on 2026-10-14: it prints the usage (`--listen`, `--otel-trace-listen`, `--otel-trace-exporter`) and exits 0 |
| `codex sandbox -- /usr/bin/true` exits 0 | passed on 2026-10-14: exit 0. `codex sandbox -- /bin/sh -c 'echo inside; exit 3'` prints `inside` and exits 3 |
| A child spawned in another working directory takes 0008's fallback | passed on 2026-10-14, with no login: `codex app-server` (with a scratch `CODEX_HOME`), `initialize`, then `command/exec` with `cwd` set to a scratch `spawn-cwd/sub`. `["/bin/pwd"]` returns `exitCode 0` and that path on stdout. With `tty: true` and streamed output, `/bin/sh -c 'pwd; exit 7'` streams the same path and returns `exitCode 7`. `codex sandbox` has no cwd option (it runs in the current directory through Tokio's `Command`, not `codex-utils-pty`) |
| shipyard `assert_binary_compatible.sh` on both binaries | passed natively for both (`compat guard: 1 binaries clean (x86_64, pinned minos and SDK per arch, no post-10.9 imports)`). It also passed the earlier `codex` that linked `/opt/pkg` dylibs, so it does not check where a binary's libraries come from |
| `otool -L` shows no libcxx22, `@rpath` or build-root paths | passed for both after the pkg-config fix: libobjc, libSystem and `/usr/lib/libiconv.2.dylib`, plus OS frameworks (`codex` adds IOKit, AppKit and CoreGraphics), and no `LC_RPATH` and no `/opt/pkg` string. Build-root paths appear only as Cargo source paths in panic locations (2141 in `codex`, 828 in the host), not as load paths |
| `otool -l` shows minos 10.9 and SDK 10.9 | passed for both: `LC_VERSION_MIN_MACOSX`, `version 10.9`, `sdk 10.9` |
| `code_mode_only` model through a symlinked `codex` does not report "Code Mode is unavailable" | failed on 2026-10-15 before 0009: logged in with `codex login --device-auth`, `codex exec -m gpt-5.6-terra "run ls"` through a symlink in another directory warned "host executable was not found" for `codex-code-mode-host` beside the symlink, and the model could not run `ls`. From the real path it ran `ls` through the host in the read-only sandbox. Passed through the symlink with 0009 |
| `codex update` on the installed package opens the package's updater | failed on 2026-10-17 before 0010: `Updating Codex via \`brew upgrade --cask codex\`...` then `Error: No such file or directory (os error 2)`, since upstream reads every `/usr/local` install as Homebrew's. Passed with 0010, natively built and installed from the pkg: it prints `Opening the codex-cli updater...`, and `codex-cli-updater --user` logs `user-initiated: starting interactive check`. `codex doctor` reports install method `mavergreen` and update action `codex-cli updater`. An `exec` turn from the same install ran `ls` and answered. 0010 has since been removed: Codex now runs from the user's standalone install, and `codex update` runs the package's installer (see "The self-updating Codex, end to end on 10.9") |
| TUI starts in Terminal with a prompt, not an Objective-C exception | passed on 2026-10-15 (maintainer): the trust prompt, then the TUI; a full turn ran a command and answered. No FSEvents lines on the screen at startup or quit |
| `FSEventsPurgeEventsForDeviceUpToEventId: f2d_purge_events_for_device_up_to_event_id_rpc() failed: 5` on stderr | seen in `codex exec` output, a few lines per run; harmless. notify 8.2.0, Codex's file watcher, calls it whenever it restarts an FSEvents stream, and Apple's header says only root may call it. 10.9 prints the failure. notify removed the call in 9.0.0-rc.2 (#795); Codex 0.161.0 pins 8.2.0, so it goes away when Codex moves to notify 9 |

## Cross build

Measured on 2026-10-14 on an arm64 Mac running macOS 27.0.1, at the same source as the native build.

| Check | Result |
|---|---|
| `build-codex.sh cross` from a cold build root | passed: 36 minutes, exit 0. Every target C compile took its sysroot from clang22-cross's cfg (cc printed no SDK detection of its own), and no `rustc-link-search` points outside the target dir |
| `verify-artifact.sh` on the transferred native artifact | passed with Apple's `/usr/bin/file` |
| `check-build-manifests.sh` | `native and cross inputs match`. The manifests differ only in `mode` and `protoc_runtime` |
| CMake `codex_compat` (both compat guards and `check-load-paths.sh`, then a build-time target) | passed for both cross binaries. Those checks are now the CTest tests `compat_guard_*` and `load_paths_*`, run by `shipyard-ctest --preset cross`: see that row under "Native versus cross" (2026-10-15, at `3ab408c`) |
| `otool -L`, minos and SDK of the cross binaries | the same OS libraries as native, `LC_VERSION_MIN_MACOSX 10.9` and SDK 10.9, no `LC_RPATH`, no `/opt/pkg` string |
| The cross binaries on 10.9 | see "Cross binaries on 10.9" below: the 2026-10-15 run of a cross artifact built at `f6de432` |

## Installed native package on 10.9

Measured on 2026-10-15 on ultimate-hat (Mac OS X 10.9.5), with the earlier packaging, which put both
binaries in the pkg. The native package `codex-cli-0.161.0-mavericks.1` was installed there at
16:02 EDT with `sudo installer`, on the maintainer's instruction. "The self-updating Codex, end to
end on 10.9" below measures the current packaging.

| Check | Result |
|---|---|
| The installed tree | passed: only `codex` is in the link farm; `LICENSE`, `NOTICE` and `build-manifest` are in `share/doc/codex-cli`; `dev.mavergreen.codex-cli-updatecheck` was loaded |
| Non-interactive smokes through `/usr/local/mavergreen/bin/codex` (on the login `PATH`) | passed: `--version` prints `codex-cli 0.161.0`; `--help` works; `codex-code-mode-host --help` works; `codex sandbox -- /usr/bin/true` exits 0; `codex exec -m gpt-5.6-terra "run ls"` ran `ls` through the host, using the existing login |
| An interactive TUI workflow with the installed `codex` (maintainer, in this repo) | passed: the model read `build/build-codex.sh` and ran it with no arguments; it printed `usage: build-codex.sh native|cross` and exited 2, as it should, and the TUI quit cleanly |
| Login on a clean `CODEX_HOME` | passed: `codex login --device-auth`, then `codex exec "say hi"` answered "Hi!" with the default model `gpt-6-luna` |
| `failed to refresh available models: request timed out` on the clean profile | intermittent; seen twice in the maintainer's clean-profile run. The models manager gives the request 5 s (`manager.rs:421`). Three reruns on a clean profile: once exit 1, once an error at +5 s, once clean, where the models request took 1.2 s with a 200, of which about 0.5 s was the lazy root load at the first certificate check. `exec` still answered in the maintainer's run. It was not attributed to the port |

## The self-updating Codex, end to end on 10.9

### Measured with an earlier patch series

Measured on 2026-10-17 on ultimate-hat, natively built with a series that still had 0001 (every
HTTPS client on rustls), and with `codex-path/rg` still a link. Three tarballs of that one build
(`-mavericks.1`, `.2`, and `.3` with `mavergreen_min_pkg` `20261018.1`) were signed with a
throwaway key and served from a `file://` channel (`CODEX_BUILDS_URL`), with a scratch `HOME` and
`CODEX_HOME`. The channel itself was not live (`latest.json` answered 404).

| Check | Result |
|---|---|
| A first run with an empty channel | passed: `codex: could not install Codex: Could not fetch the build metadata for Codex latest from file:///…/latest.json.`, exit 1 |
| The launcher's first run seeds `-mavericks.1` into `packages/standalone` | passed: the launcher's line, then the installer's (`Resolved version: 0.161.0-mavericks.1`, `installed successfully`), then `codex-cli 0.161.0`, in 3.9 s. `current` names the release, `auto-update-version` is written, and the manifest's `mavergreenBuild` is the build |
| `codex exec` runs a turn, with a `code_mode_only` model through the launcher | passed: `gpt-5.6-terra` ran `ls` in the read-only sandbox and answered, with no "host executable was not found" |
| The startup notice offers `-mavericks.2` | passed from a seeded version cache, since the channel was not live: `Update available · 0.161.0 → 0.161.0-mavericks.2`, with the installer as the update command. The background refresh asked only the channel's `latest.json`, and nothing at `api.github.com/repos/openai`, `chatgpt.com/codex/install`, `releases.openai.com` or `formulae.brew.sh`. The "from" side showed `0.161.0`; the notice now shows both build identities for a rebuild |
| `check_for_update_on_startup = false` | passed: no notice with it, the notice without it |
| `codex update` installs `-mavericks.2` | passed through a test shim for the fixed installer path (the old-scheme pkg on that host had no installer there): `Updating Codex CLI from 0.161.0-mavericks.1 to 0.161.0-mavericks.2`, exit 0. A second run said `already installed` |
| `install.sh --release 0.161.0-mavericks.1` steps back | passed: `current` moved back and `auto-update-version` was removed; `codex update` then moved to `.2` again |
| `codex doctor` reports the standalone installer | passed: the standalone runtime and package path, update action `standalone installer`, the cached latest build, and the channel's 404. doctor now also prints `running build:` and `update channel:` lines |
| `codex app-server daemon start` and a TUI with the daemon on: `Error: package link escapes its root` | failed: the daemon copies the CLI's package into its own root and refuses an entry that resolves outside it, as the absolute `codex-path/rg` link did, so the TUI failed unless run with `--no-daemon`. `codex-path/rg` is now a script that execs the `rg` package's `rg`. With such a script in a variant tarball, the daemon started, the TUI connected to it over its socket and a turn answered |

### Pending

These checks wait for the AquaTransport release with the TLS fixes Codex's native-tls needs. Each
runs natively on ultimate-hat with the current series, with a `file://` builds channel, builds of
one Codex version (`-mavericks.1`, `.2`, and a `.3` that needs a newer pkg) signed with a throwaway
key that the test pkg ships, and a scratch `HOME` and `CODEX_HOME`.

| Check | Result |
|---|---|
| The native release build of the current series compiles: the TUI's update check and `run_update_prompt_if_needed` are built only without debug assertions | pending |
| The launcher's first run seeds `-mavericks.1` into `packages/standalone` | pending |
| `codex exec` runs a turn, with a `code_mode_only` model through the launcher | pending |
| The startup notice offers `-mavericks.2` and shows both build identities | pending |
| `codex update` installs `-mavericks.2` | pending |
| `codex doctor` shows `running build:` and `update channel:` | pending |
| The app-server daemon starts with the `codex-path/rg` script, and the TUI connects to it | pending |
| A scheduled background update moves the daemon to `-mavericks.2`, the daemon restarts into it, and the next scheduled update still runs | pending |
| `.3`, whose `mavergreen_min_pkg` is newer than the installed pkg, makes `codex update` open the package's updater, say so and install nothing | pending |
| The daemon's update for `.3` installs nothing and logs why | pending |
| A first run with a pkg too old for the newest build fails and says how to get a newer pkg | pending |
| A `code_mode_only` model finds `codex-code-mode-host` through the launcher without patch 0009 | pending |
| A `~/.codex` copied from a modern Mac, with OpenAI's standalone and daemon releases in it: the launcher replaces `current`; what the daemon then does | pending |

### First runs in CI

| Check | Result |
|---|---|
| The first `builds.yml` publish against GitHub: the release created with `--latest=false`, the uploads, the `latest.json` replace, the re-point loop, assets fetched by id (`Accept: application/octet-stream`, following the redirect), pruning, the 10.9 job checking the family key's signature, and the key-log scan | pending |
| A second publish: the stale-ID and same-ID refusals, and `build/build-id.sh auto` reading the published state | pending |
| The first `release.yml` publish: its 10.9 job seeds from the real HTTPS channel (`/usr/bin/curl` reaching github.com is measured on ultimate-hat; the redirect to the asset host is not), the appcast, and the pkg becoming the repo's Latest | pending |
| Sparkle offers a second pkg, and `sudo mavergreen uninstall codex-cli` leaves `~/.codex` alone | pending |
| Where the `codex-builds` release sits on the Releases page after the first few pkgs; if it sits first, the channel moves to a repo of its own | pending |

## Native versus cross

Measured on 2026-10-15 at `f6de432`: the cross side on the arm64 Mac running macOS 27 from a clean
build root, the native side on ultimate-hat.

| Check | Result |
|---|---|
| `build-codex.sh cross` from a clean build root | passed: 37 minutes 4 seconds, exit 0 |
| The native artifact verified on the modern Mac | passed |
| `check-build-manifests.sh` | `native and cross inputs match`; the manifests differ only in `mode` and `protoc_runtime` |
| Cross configure with the updater, and the compat guard | passed: configure exit 0; the guard was clean for `codex`, the host and the updater |
| `check-load-paths.sh` on the cross binaries | exit 0 |
| `shipyard-ctest --preset cross`, at `3ab408c` on the modern Mac | 4/4 passed |
| `shipyard-ctest --preset native`, at `b664361` on ultimate-hat | 4/4 passed. The updater's compat guard was clean |

| Comparison | Native versus cross |
|---|---|
| `lipo` architecture | same |
| `minos` and SDK | same |
| `otool -L` | same (12 entries) |
| `nm -u` | `codex` 465 undefined symbols and the host 420, the same count on both builds, with 0 lines differing |
| `LC_RPATH` | none in either |
| File mode | same |
| `codex` sha256 | native `4f6de220…a01e`, cross `7f176ce9…316e` |
| `codex` size | native 357,475,576 bytes, cross 357,389,912 (cross 85,664 smaller) |
| `codex-code-mode-host` sha256 | native `385ad878…89a4`, cross `81a40466…2e7e` |
| `codex-code-mode-host` size | native 90,492,720 bytes, cross 90,497,672 (cross 4,952 larger) |
| `__cstring` section | cross larger by 6,084 bytes (`codex`) and 2,304 (host) |
| `__text` section | cross smaller by 35,968 bytes (`codex`) and 7,168 (host) |
| Build-root path strings | native 2,141 (`codex`) and 828 (host), under `mm-build`; cross 2,143 and 829, under `mm-build-t7` |

The native build ran on ultimate-hat under `~/Library/Caches/mm-build` and the cross build on the
modern Mac under `~/Library/Caches/mm-build-t7`. The expected causes of the byte differences were not
isolated by experiment:

- Build-root path strings in panic locations differ, and the counts above differ by 2 and 1. Whether
  they account for the whole `__cstring` growth was not measured.
- Crate metadata hashes differ, because the host triple and the cross-only rustflags differ.
- The `__text` difference may come from codegen following the names (the longer path and metadata
  strings). That is a hypothesis, unmeasured.

## Cross binaries on 10.9

Measured on 2026-10-15 on ultimate-hat, with the cross artifact built on the modern Mac at `f6de432`.

| Check | Result |
|---|---|
| Transferring the artifact | failed at first: macOS 27 tags every file it creates with `com.apple.provenance`, so `tar` carried `._` and pax extended-attribute entries that 10.9's `tar` rejects. `build/transfer-artifact.sh` now sets `COPYFILE_DISABLE` and adds `--no-xattrs` where a probe shows `tar` supports it (`41870d3`; test 17 runs only where the local `tar -tf` lists `._` members). On macOS 27 at `3ab408c` the staged `codex.tar` (sha256 `9c9560bd…`) had exactly 5 members and no `._` entry, and was byte-identical to a hand-made clean tar. At `b664361`, `artifact-transfer.bats` passed 17/17 there; test 17 skips unless the local `tar -tf` both succeeds and lists `._codex`, which macOS 27's `tar` does not, and on 10.9 it runs and passes |
| `verify-artifact.sh` on 10.9 | passed. `codex` sha256 `7f176ce9…` and the host's `81a40466…` matched the values reported on the modern Mac |
| Packaging | The cross pkg that was smoke-tested was packaged on 10.9 from the cross artifact, with `packaging/build-pkg.sh` and the native-built updater. The pkg built on the modern Mac failed `tests/package-test.sh` and was not installed: macOS 27's `pkgbuild` writes `._` entries into the BOM of a pkg built on the provenance-tagged Mac. That is a shipyard issue, not yet fixed there. Until it is fixed a pkg built locally on the modern Mac is not releasable. Whether CI-built pkgs are affected was not measured |
| `tests/package-test.sh` on that pkg | `ok 43` |
| The installed cross build | passed: the installed `codex` reports `mode=cross`; `--version`, `--help` and `codex-code-mode-host --help` work; `codex sandbox -- /usr/bin/true` exits 0; `codex exec -m gpt-5.6-terra` ran commands through the host |
| A TUI turn with the installed cross build (maintainer) | passed: a full turn, with no FSEvents lines |
| The model's note that it was in "Codex CI" with the network disabled | upstream behaviour. For tool commands, unified exec sets `CODEX_CI=1`, `TERM=dumb` and a `C.UTF-8` locale, and the default sandbox sets `CODEX_SANDBOX_NETWORK_DISABLED`. Not a port effect |

The native package was reinstalled afterwards.

## Codex's own tests

`just test -p codex-sandboxing -p codex-user-verification -p codex-tui -p codex-http-client -p
codex-features -p codex-core -p codex-utils-pty -p codex-hooks`, the crates the patches touch, run
on 2026-10-15 on the same arm64 Mac (Codex's channel 1.95.0, cargo-nextest). These tests do not run
on 10.9.

| Check | Result |
|---|---|
| The full run above, patched against unpatched upstream | no failure caused by the patches. Every failure also fails on upstream there: 366 come from that Mac's environment, and the rest are tests that fail on both trees when the machine is loaded |
| `codex-http-client`, `codex-otel` and `codex-responses-api-proxy`, 5 runs each, measured with the since-removed 0001, which loaded its roots at the first certificate check | `codex-http-client` and the proxy: no failures, and faster than upstream. `codex-otel`: `otlp_http_exporter_times_out_when_collector_stalls_during_bounded_shutdown` fails on both trees; `…sends_traces_to_collector_with_bounded_shutdown_in_tokio_runtime` failed once in 5 patched runs, not root-caused. The 6 tests of upstream's native-TLS retry are ignored by 0001 |
| Measured with the since-removed 0001: an OTLP trace exporter with no `tls` table, unmanaged policy, against a TLS 1.3-only local server | the patched tree completes a TLS 1.3 handshake with ALPN through the lazy verifier. Upstream's exporter used native-tls and failed the handshake |
| `suite::mcp_optional_startup_grace` | 3 of its 6 cases fail with the patches when the 6 start together, and upstream fails 1 or 2 there too. The cause is the test harness: the first `CFBundleGetMainBundle` in a process lists the executable's directory, and a test binary sits in `target/debug/deps` (about 134,000 entries), which took 0.6 to 1.3 s. With rustls, that first lookup falls inside MCP startup, through the system-proxy probe reqwest makes when it builds a client. An installed `codex` sits in a small directory, where the same lookup takes about 0.4 ms |
| The two `codex-otel` OTLP tests above, without 0001, run natively on ultimate-hat (10.9), 50 times each, one at a time with `build/cargo-dev.sh test -p codex-otel --test tests -- <name>`, 2026-10-24 | no failures: `…sends_traces_to_collector_with_bounded_shutdown_in_tokio_runtime` 50 of 50, `…times_out_when_collector_stalls_during_bounded_shutdown` 50 of 50. Both talk plain HTTP to a loopback collector, so AquaTransport is not involved. The earlier failures do not recur without 0001 |
| `cargo fmt` with upstream's options, and `cargo clippy -p codex-http-client -p codex-otel -p codex-responses-api-proxy --tests` | clean |

### TLS, pending the AquaTransport release

Patch 0001 is dropped, so Codex's HTTPS clients use native-tls, which goes through AquaTransport.
WebSockets (`codex-websocket-client` always uses rustls) and the OTLP gRPC exporter still verify
through rustls, with roots `rustls-native-certs` reads from the 10.9 keychain. These checks wait for
the AquaTransport release with the TLS fixes Codex's native-tls needs, and are run natively on
ultimate-hat with a scratch `CODEX_HOME`. The measurements above that name 0001 do not apply to the
current series.

| Check | Result |
|---|---|
| The six `codex-http-client` tests that 0001 ignored (the native-TLS-to-rustls retry), run alone with `build/cargo-dev.sh test -p codex-http-client --lib -- <names>` | one passes (`request_failures_classify_real_untrusted_certificate_handshakes`). Five fail on 10.9 with AquaTransport 2026.09.21 and also with AquaTransport's TLS fix inserted: `retries_a_native_tls_protocol_failure_once_with_rustls`, `retries_a_native_tls_failure_after_another_request_caches_rustls`, `successful_rustls_fallback_replays_the_request_and_reuses_the_destination`, `retries_a_tls_protocol_failure_when_request_url_contains_certificate_markers` and `does_not_retry_a_non_replayable_streaming_request`. Each gets `Error { code: -9806, message: "connection closed via error" }` from native-tls, and Codex retries with rustls only on "bad protocol version". The cause is a second AquaTransport gap: `my_SSLHandshake` reports every handshake failure as errSSLClosedAbort (-9806), where stock Secure Transport gives -9836 for the protocol_version alert these tests send. With AquaTransport switched off for the test binary, all five pass. The failures are the tests' alone, and harmless on 10.9: the fallback they test exists because modern macOS's Secure Transport lacks TLS 1.3, and AquaTransport speaks TLS 1.0 to 1.3, so on 10.9 nothing needs it. They are not ignored; they pass once AquaTransport returns stock's codes |
| The same five tests against the released AquaTransport | pending |
| `codex-otel` and `codex-responses-api-proxy` tests, with their HTTPS clients on native-tls | pending |
| `codex login --device-auth` on a clean `CODEX_HOME` | pending |
| `codex exec` over HTTPS and WebSockets, with no reconnects and no fallback from WebSockets | pending |
| A WebSocket turn on a 10.9 host without AquaTransport's ModernRootCertificates (rustls with the keychain's roots) | pending |
| A request through a proxy | pending |
| An OTLP trace exporter against a TLS 1.3-only local server | pending |


## Voice, a first native probe

Not shipped; this is how far `codex-voice-host` got on ultimate-hat on 2026-10-24, at the pinned
Codex commit, in a debug build (`build/cargo-dev.sh`-style environment, scratch changes only).
Upstream builds macOS voice with Bazel for macOS 14, and the helper needs a native runtime: GLib
2.88, GStreamer 1.28.6 (core, base, good) and opus 1.6.1, with seven plugins (`app`,
`audioconvert`, `audioresample`, `coreelements`, `opus`, `rtp`, `rtpmanager`). Devices go through
cpal and CoreAudio, not a GStreamer plugin.

| Symptom | Cause | Fix tried | Source |
|---|---|---|---|
| `glib-sys`, `gobject-sys`, `gio-sys` and four `gstreamer-*-sys` build scripts: `The system library glib-2.0 ... was not found` | the helper links GLib and GStreamer through pkg-config, which `codex-build-env.sh` sets to `/usr/bin/false` | pkg-config pointed at a scratch GStreamer prefix and pkgsrc's GLib 2.88.1 | reproduced |
| `opusic-sys`: `libc++abi: terminating due to uncaught exception of type std::bad_cast`, cmake killed by SIGABRT after "Generating done" | the native build runs cargo with clang-22's libc++ in `DYLD_INSERT_LIBRARIES` and `DYLD_FORCE_FLAT_NAMESPACE`, which every child inherits; pkgsrc's `cmake` aborts under it. Replaying the same cmake command without those variables succeeds | a `CMAKE` wrapper that unsets the three `DYLD_*` variables; `opusic-sys` then builds | reproduced |
| GStreamer 1.28.6 `gstmacos.m`: `use of undeclared identifier 'NSEventTypeApplicationDefined'` and `'NSEventSubtypeApplicationActivated'` | the 10.12 SDK's names for constants the 10.9 SDK calls `NSApplicationDefined` and `NSApplicationActivatedEventType` | renamed to the 10.9 names; core, base and good then build, all seven plugins included | reproduced |
| GStreamer: `gi18n-lib.h: 'libintl.h' file not found` | pkgsrc's GLib expects pkgsrc gettext's `include/gettext`; upstream's runtime uses proxy-libintl instead | `CFLAGS=-I/opt/pkg/include/gettext` (scratch only) | reproduced, pkgsrc-specific |
| final link: `undefined symbol: AudioComponentFindNext`, `AudioUnitRender`, `AudioOutputUnitStart` and seven more `AudioUnit*`/`AudioComponent*` | on 10.9 these are in `AudioUnit.framework`; newer SDKs export them from `AudioToolbox`, which is all `objc2-audio-toolbox` links | `-framework AudioUnit` | reproduced |
| final link: `undefined symbol: AudioHardwareCreateProcessTap`, `AudioHardwareDestroyProcessTap`, `AudioHardwareCreateAggregateDevice`, `AudioHardwareDestroyAggregateDevice` | cpal 0.18.2's loopback (system-audio capture) device; 10.9's CoreAudio has none of them (process taps are macOS 14.2) | `-Wl,-U` for the four, so they resolve at load time to nothing. The helper opens only the default microphone and speaker, never a loopback device, but a real fix compiles cpal's loopback out | reproduced |
| none: the helper links, `codex-voice-host --build-commit` prints `dev` on 10.9, and shipyard's compat guard reports it clean | | | measured |

Not yet measured: the helper's lifecycle against a prepared runtime (upstream's `packaged_runtime`
test needs a runtime prepared by `third_party/voice/build_native.py` and
`prepare_built_runtime.py`, which require Python 3.12 and their own build receipts), real capture and
playback, the TUI's voice path, a cross build, and packaging the runtime under
`codex-resources/voice`.
