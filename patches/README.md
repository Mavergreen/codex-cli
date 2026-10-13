# Patches

`build/fetch-codex.sh` applies every `*.patch` here, in lexical order, to the Codex commit in
`build/codex-revision`. Each patch also applies on its own to that commit, because `git apply
--check` runs on all of them before any is applied. A new patch is added only for an
incompatibility measured on Mac OS X 10.9. All seven patches are Wowfunhappy's; `PROVENANCE.md`
says where each came from.

## 0001-force-rustls.patch

- **What:** `codex-rs/http-client/src/custom_ca.rs` makes every reqwest client use the bundled
  rustls backend, with the platform's native roots, instead of only the custom-CA path.
- **Why:** reqwest's default backend is native-tls (Secure Transport). On 10.9 it cannot negotiate
  modern TLS, so "Sign in with ChatGPT" fails with a handshake error. Codex's rustls retry is
  opt-in and not every API client turns it on.
- **Invariant kept:** the custom-CA handling that follows is unchanged.
- **When to reconsider:** when upstream defaults reqwest to rustls, or its rustls path covers
  every client.

## 0002-update-check-off-by-default.patch

- **What:** `codex-rs/core/src/config/mod.rs` changes the default of `check_for_update_on_startup`
  from `true` to `false`.
- **Why:** on these hosts the package manager Codex detects (notably Homebrew) may be absent or
  unable to run, so startup would offer an update path that cannot work.
- **Invariant kept:** only the default changes. `check_for_update_on_startup = true` still turns
  the check on.
- **When to reconsider:** when this package has its own update path that the check can offer.

## 0003-daemon-auto-start-off-by-default.patch

- **What:** `codex-rs/features/src/lib.rs` changes the default of the `daemon_auto_start` feature
  from enabled to disabled.
- **Why:** the shared background app-server daemon runs from a packaged install, which a cargo
  build lacks, so it fails with "this CLI has no complete local package". Its updater also
  installs upstream builds the host may not run. The TUI hosts the app server in-process instead,
  as with `--no-daemon`.
- **Invariant kept:** only the default changes. `[features] daemon_auto_start = true` still turns
  it on.
- **When to reconsider:** when the package ships what the daemon needs and its updater no longer
  installs upstream builds.

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
