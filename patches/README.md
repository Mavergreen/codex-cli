# Patches

`build/fetch-codex.sh` applies every `*.patch` here, in lexical order, to the Codex commit in
`build/codex-revision`. Each patch also applies on its own to that commit, because `git apply
--check` runs on all of them before any is applied. A new patch is added only for an
incompatibility measured on Mac OS X 10.9, or to make Codex update from this product's own builds
rather than OpenAI's. Patches 0004 to 0007 are Wowfunhappy's; `PROVENANCE.md` says where each came
from. 0008, 0009 and 0011 to 0013 are this product's own. 0001, 0002, 0003 and 0010 are removed,
and their numbers are not reused: "Removed patches"
at the end says what each did and why it went.

## 0004-user-verification-unsupported.patch

- **What:** `codex-rs/user-verification/src/lib.rs` routes macOS through Codex's existing
  unsupported provider: `platform_supported()` and `device_supported()` return `false`, and the
  native macOS modules are no longer compiled.
- **Why:** Codex's biometric user verification uses LocalAuthentication and Secure Enclave APIs.
  10.9 has neither, so the build must not advertise a native verifier it cannot provide.
- **Invariant kept:** other platforms already used the unsupported provider; it is not changed.
- **When to reconsider:** when the floor rises to a macOS release with LocalAuthentication and the
  Secure Enclave APIs.

## 0005-accessibility-selector-guards.patch

- **What:** `codex-rs/tui/src/system_motion.rs` and `codex-rs/tui/src/screen_reader.rs` check
  `respondsToSelector:` before sending `accessibilityDisplayShouldReduceMotion` and
  `isVoiceOverEnabled`. `codex-rs/tui/Cargo.toml` enables `objc2-foundation`'s `NSObjCRuntime`
  feature for `NSSelectorFromString`.
- **Why:** NSWorkspace gains those selectors in 10.12 and 10.13. On 10.9 the unrecognized selector
  raises an Objective-C exception that aborts the TUI at launch.
- **Invariant kept:** a host that has the selector is asked exactly as before. A host without it
  reports no reduce-motion preference and no screen reader.
- **When to reconsider:** when the floor rises past 10.13.

## 0006-seatbelt-policies.patch

- **What:** `codex-rs/sandboxing/src/seatbelt_base_policy.sbpl` and
  `seatbelt_preferences_policy.sbpl` are rewritten so 10.9's Seatbelt can parse them, and
  `seatbelt_tests.rs` gains `generated_seatbelt_profile_is_accepted_by_sandbox_exec`, which runs
  the generated profile through `sandbox-exec`.
  `base_policy_allows_kmp_registration_shm_read_create_and_unlink` now expects the guarded KMP
  rule.
- **Why:** 10.9 rejects a target filter on `process-info*` and on `process-info-listpids`, and has
  no `sysctl-name`, `ipc-posix-name-regex` or `ipc-posix-name-prefix` filter and no
  `iokit-registry-entry-class`. Rust executables need `sysctl-read` at startup.
- **Invariant kept:** every newer-macOS rule stays behind `(if (defined? …))`. An unfiltered
  fallback is added only where 10.9 cannot parse the filter: `(allow sysctl-read)` when
  `sysctl-name` is undefined. The six target-filterable `process-info-*` operations keep the
  same-sandbox restriction; `process-info-listpids` is allowed without a target. This split, and
  `(literal "/dev/null")` for `(path "/dev/null")`, apply on every macOS release. Where
  `iokit-registry-entry-class` is undefined, it is defined as `iokit-user-client-class`.
- **When to reconsider:** when the floor rises past 10.9, or upstream guards these rules itself.

## 0007-seatbelt-runtime-policy.patch

- **What:** `codex-rs/sandboxing/src/seatbelt.rs` puts the `xpc-service-name-prefix` mach-lookup
  deny and the `system-fcntl` deny behind `(if (defined? …))`. `seatbelt_daemon.rs` keeps the
  pathname-qualified unix-socket deny for the daemon directory when `ipc-posix-name-prefix` is
  defined, and otherwise denies all outbound unix-socket connections.
- **Why:** 10.9 defines neither `xpc-service-name-prefix` nor `system-fcntl`, and rejects pathname
  filters nested inside `unix-socket`.
- **Invariant kept:** newer-macOS rules stay behind `(if (defined? …))`. The 10.9 fallback for the
  daemon socket is a broader deny, so the daemon boundary still holds.
- **When to reconsider:** when the floor rises past 10.9, or upstream guards these rules itself.
- **Trimmed:** Wowfunhappy's runtime patch also changed `codex-rs/cli/src/debug_sandbox.rs` to
  deny TIOCSTI by number. That section is dropped. At `build/codex-revision`, `debug_sandbox.rs`
  already writes the deny with the numeric `libc::TIOCSTI`, and the old hunk no longer applies.

## 0008-pty-addchdir-runtime-lookup.patch

- **What:** `codex-rs/utils/pty/src/posix_child.rs` looks up `posix_spawn_file_actions_addchdir_np`
  with `dlsym` on macOS, as it already does on glibc, instead of declaring it as a hard `extern`.
  When the lookup fails, `NativeChild::spawn` returns `Ok(None)`, and the caller falls back to
  `tokio::process::Command`. Only Rust's bundled musl keeps the hard `extern`.
- **Why:** the function is new in macOS 10.15. As a hard `extern` it makes `codex` and
  `logs_client` fail to link against 10.9's libSystem (`undefined symbol:
  posix_spawn_file_actions_addchdir_np`), and Recaulk does not back-fill it.
- **Invariant kept:** on 10.15 and later, the lookup finds the function and native spawning
  behaves exactly as upstream's. On 10.9 every native spawn takes the compatibility fallback that
  upstream already uses for glibc without the function.
- **Why widening the fallback is safe:** 10.9 also lacks `POSIX_SPAWN_SETSID` (macOS 10.15), so
  every `NativeChild` spawn would need a fallback there, not only spawns with a cwd. The lookup
  fails before the cwd is looked at, so all of them take upstream's existing Tokio/std path,
  rather than a native one that 10.9 cannot run.
- **What changes on 10.9:** callers that ask for `SpawnFallback::ReturnError`, and hook spawns,
  also go through Tokio's or std's `Command`, so they get the executable-text and `PATH`
  fallbacks they otherwise avoid. Upstream's tests that expect a native child (pty
  `macos_child_tests.rs`, hooks `command_runner_tests.rs`) are valid only on 10.15 and later.
- **When to reconsider:** when the floor rises to 10.15, or upstream looks the function up at
  runtime itself.

## 0009-code-mode-host-beside-resolved-executable.patch

- **What:** `codex-rs/install-context/src/lib.rs` looks for `codex-code-mode-host` beside the file
  `codex` resolves to, not beside the path it was started by. If that path cannot be resolved, it
  looks where upstream does. `code_mode_host_program_follows_a_symlinked_codex_to_its_directory`
  tests it.
- **Why:** on 10.9, `_NSGetExecutablePath`, and so `std::env::current_exe()`, returns the path
  `codex` was started by, a symlink included. Upstream resolves only that path's directory, so a
  symlink to `codex` in another directory made Code Mode fail with "host executable was not
  found". Measured on 2026-10-15. Whether newer macOS returns the resolved path was not measured.
- **Invariant kept:** a package layout or standalone release directory is used first, as before.
  Started from its own directory, `codex` finds the host where it always did.
- **When to reconsider:** when upstream resolves the executable before taking its directory.
- **To be measured:** whether Codex still needs it now that the launcher runs the real binary from
  the user's standalone install, where Codex looks in its package's `bin/` before this code runs.

## 0011-mavergreen-build-identity.patch

- **What:** `codex-rs/install-context/src/mavergreen.rs`, a new module, holds what a build knows
  about where its updates come from: the builds channel and its `latest.json`, the package's
  installer (`/usr/local/mavergreen/codex-cli/libexec/codex-cli/install.sh`) and the package's
  updater. Its `BuildId` reads a build identity, `<x.y.z>-mavericks.<N>` with N at least 1 and no
  leading zero, as the channel's identity rule has it, or a plain `x.y.z` as build 0, and orders
  builds by Codex version and then by build number.
  `CodexPackageManifest` in `install-context/src/lib.rs` reads `codex-package.json`'s
  `mavergreenBuild`, and `current_build_id` returns it for the running package. Tests in
  `mavergreen.rs` cover parsing, ordering and the manifest.
- **Why:** a rebuild of the same Codex version, for a patch or a toolchain change, must reach users
  as an update, while `codex --version` keeps printing OpenAI's version. Upstream's update check
  compares versions with `parse_version`, which reads only `x.y.z`, so it cannot tell
  `0.161.0-mavericks.2` from `0.161.0-mavericks.1`. The build's identity travels in its package
  manifest instead, which `packaging/build-codex-package.sh` writes.
- **Invariant kept:** `codex --version` and the workspace version are OpenAI's. A manifest without
  `mavergreenBuild` reads as before, and its build is the plain Codex version.
- **When to reconsider:** when the channel, the package's installer or its updater moves. Nothing
  upstream would replace the build identity while Codex reaches 10.9 as this product's own builds.

## 0012-update-from-the-mavergreen-channel.patch

- **What:** the TUI's startup check (`codex-rs/tui/src/updates.rs`) and `codex doctor`'s update
  section (`codex-rs/cli/src/doctor/updates.rs`) read the newest build from the channel's
  `latest.json`, not from `api.github.com/repos/openai/codex/releases/latest`, and compare it with
  the running build using 0011's `BuildId` (`codex-rs/tui/src/update_versions.rs`). The Homebrew
  cask probe is removed, and installs from Homebrew, npm, bun, vp or pnpm check nothing. The
  standalone update action (`codex-rs/tui/src/update_action.rs`), which `codex update` and the
  startup notice run, is `CODEX_NON_INTERACTIVE=1 exec /bin/sh
  /usr/local/mavergreen/codex-cli/libexec/codex-cli/install.sh` instead of piping
  `chatgpt.com/codex/install.sh` into `sh`. The Windows action only reports that it is unsupported.
  When the installer exits 3 because the newest build needs a newer codex-cli package,
  `codex update` (`codex-rs/cli/src/main.rs`) says so, where to get the newer package (its updater,
  or the package's latest release), and to run it again then, rather than that the command failed.
  It does not assume the updater opened, since a run with nobody at a terminal opens nothing; the
  installer's own lines come first, as before.
  The two standalone history-cell snapshots show the new commands. `codex doctor`'s update section
  names the running build (`running build: <ID>`) and, for a standalone install, the `latest.json`
  it checks (`update channel: <URL>`). When the newest build is a rebuild of the running Codex
  version, the startup notice and its history cell (`tui/src/update_prompt.rs`,
  `tui/src/history_cell/notices.rs`) show both build identities, `0.161.0-mavericks.1 →
  0.161.0-mavericks.2`; for a new Codex version they show the plain versions, as upstream's do.
- **Why:** upstream's check offers OpenAI's newest release, and its update action installs OpenAI's
  build, which 10.9 cannot run. Nothing on a 10.9 Mac may fetch or run OpenAI's builds. With the
  check reading this product's channel and `codex update` running the package's installer, the
  startup check can stay on, as upstream ships it, so 0002 is removed. `codex --version` stays
  OpenAI's, so the build number shows where a user looks for it: `codex doctor`, and the notice
  for a rebuild, which plain versions would show as `0.161.0 → 0.161.0`.
- **Invariant kept:** upstream's notice, its wording, its dismissal and its 20-hour cache are
  unchanged, and so is `check_for_update_on_startup`, which still turns the check off. The notice's
  release-notes link is still upstream's.
- **When to reconsider:** when the channel or the package's installer moves (both are in 0011).

## 0013-daemon-updates-through-the-package-installer.patch

- **What:** `codex-rs/app-server-daemon/src/update_loop.rs`: the app-server daemon's background
  update loop, and the migration its manual update runs, read the package's installer from disk at
  0011's path instead of downloading `https://chatgpt.com/codex/install.sh`. A failed scheduled
  update is logged on the updater's stderr (`warning: scheduled update failed: …`) where upstream
  dropped it. The installer's own stderr is not kept, so its exit 3 gets a message that says why:
  the newest build needs a newer codex-cli package, and nothing was installed.
  `local_installer_reads_the_package_installer` in `update_loop_tests.rs` checks that the script's
  bytes come back unchanged and that a missing script is an error naming its path, and
  `an_installer_that_needs_a_newer_package_says_why` checks the exit-3 message.
  The daemon runs its updater, and restarts into what it installed, only while its selected release
  is a "stable" one, which upstream recognises by a plain `x.y.z` in the release's name.
  `codex-rs/app-server-daemon/src/managed_install.rs` also accepts the installer's
  `<x.y.z>-mavericks.<N>` names, and `prepare_install.rs` names the daemon's first release for the
  package's build (`mavergreenBuild`), as the installer would. `mavergreen_build_releases_are_stable`
  and `a_mavergreen_package_seeds_a_release_named_for_its_build` test both.
- **Why:** upstream's loop downloads OpenAI's installer and runs it, which installs OpenAI's builds.
  Read from the package, the installer fetches only this product's signed builds. With that, the
  daemon can start on its own, as upstream's does, so 0003 is removed. Without the build names,
  the daemon's first scheduled update would install the running build again under its build name,
  and then count that release as unstable: it would never restart into a newer build, and would
  stop updating once restarted.
- **Invariant kept:** the loop's guarded runs (`CODEX_INSTALL_IF_LATEST`,
  `CODEX_INSTALL_IF_CURRENT`, `CODEX_INSTALL_DAEMON_ONLY`, `CODEX_INSTALL_DEFER_SELECTION`,
  `CODEX_UPDATE_FROM_RELEASE`) and their environment are upstream's. The package's installer
  implements each of them as upstream's `install.sh` does.
- **When to reconsider:** when the package's installer moves.

## Removed patches

### 0001-force-rustls.patch

- **What it did:** put every HTTPS client on the bundled rustls backend instead of native-tls, with
  one shared rustls config in `codex-rs/http-client` that loaded the platform's native roots at the
  first certificate check; moved the OTLP exporters and the Responses API proxy onto rustls too; and
  marked the six `http-client` tests of upstream's native-TLS-to-rustls retry ignored. It was
  Wowfunhappy's, and was rewritten here.
- **Why it was removed:** it worked around AquaTransport answering `kSSLIdle` from
  `SSLGetSessionState` while a handshake was in progress, where Secure Transport answers
  `kSSLHandshake`. native-tls asks there before fetching the peer trust, so security-framework
  refused with `-909` and every native-tls request failed. AquaTransport fixed that. With that
  fix, probe clients' native-tls connections work; Codex's own is still to be measured on 10.9.
  The launcher now requires an AquaTransport release that has the TLS fixes Codex's native-tls
  needs (`components/aquatransport/min-version`). Codex's HTTPS clients then need neither the patch nor
  its roughly 450 ms of root loading on first use. The dependence on 10.9's keychain roots, and so on
  AquaTransport's ModernRootCertificates, did not go with it: WebSockets (`codex-websocket-client`
  always uses rustls) and the OTLP gRPC exporter still verify through rustls, loading the
  keychain's roots with `rustls-native-certs` when first used. The six ignored tests run again: one
  passes (`request_failures_classify_real_untrusted_certificate_handshakes`), and five fail on 10.9
  with `-9806`, because AquaTransport reports every handshake failure as errSSLClosedAbort where
  stock Secure Transport gives -9836. Those five test the native-tls to rustls fallback, which
  exists for modern macOS, whose Secure Transport lacks TLS 1.3; AquaTransport speaks TLS 1.0 to
  1.3, so on 10.9 nothing needs the fallback and the failures are the tests' alone. They pass once
  AquaTransport returns stock's codes.

### 0002-update-check-off-by-default.patch

- **What it did:** made `check_for_update_on_startup` default to `false`. It was Wowfunhappy's.
- **Why it was removed:** it existed because every update path Codex detected failed here, and
  Homebrew's would have installed upstream's build. Now Codex runs from the standalone layout, its
  check reads this product's channel, and `codex update` runs the package's installer (0012).
  Upstream's default, on, is what users should see.

### 0003-daemon-auto-start-off-by-default.patch

- **What it did:** made the `daemon_auto_start` feature default to off, so the TUI hosted the app
  server in-process, and updated the two TUI tests that relied on that. It was Wowfunhappy's.
- **Why it was removed:** both of its reasons are gone. The daemon needed a packaged install, which
  the standalone layout is, and its updater installed upstream's builds, which 0013 ends.

### 0010-update-through-the-package-updater.patch

- **What it did:** reported a `codex` under `/usr/local/mavergreen` as a Mavergreen install, and
  made `codex update` open the package's Sparkle updater instead of running `brew upgrade --cask
  codex`.
- **Why it was removed:** the real binary now runs from the user's standalone layout, so Codex
  identifies the install as standalone by itself, and an ordinary Codex update no longer goes
  through Sparkle. The one part still needed, sending the user to the updater when a build needs
  a newer package, moved into the package's installer, which exits 3 for such a build.
