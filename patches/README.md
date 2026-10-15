# Patches

`build/fetch-codex.sh` applies every `*.patch` here, in lexical order, to the Codex commit in
`build/codex-revision`. Each patch also applies on its own to that commit, because `git apply
--check` runs on all of them before any is applied. A new patch is added only for an
incompatibility measured on Mac OS X 10.9. Patches 0001 to 0007 are Wowfunhappy's, and 0001 has
since been rewritten here; `PROVENANCE.md` says where each came from. 0008 is this product's own.

## 0001-force-rustls.patch

- **What:** `codex-rs/http-client/src/client_builder.rs` makes every client it builds use the
  bundled rustls backend instead of native-tls. A client with its own root certificate or client
  identity gets reqwest's rustls, which honors them. Every other client gets one rustls config
  shared by the process, from `custom_ca.rs`. That config trusts the platform's native roots and
  offers `h2` and `http/1.1` by ALPN, as reqwest's own would. Its certificate verifier is rustls's
  own WebPKI verifier over those roots, built at the first certificate check, so a client that
  never makes a TLS connection never loads them. `custom_ca.rs` loads the native roots at most
  once per process, and its websocket config reuses them. The six `http-client` tests of
  upstream's native-TLS-to-rustls retry are marked ignored, with the reason.
- **Why:** reqwest's default backend is native-tls (Secure Transport). On a stock 10.9 it cannot
  negotiate modern TLS (`-9824`, handshake failure). With AquaTransport installed, the handshake
  completes, but native-tls then checks the server's certificates itself: it breaks the handshake
  for server authentication and asks for the peer trust. `SSLCopyPeerTrust` returns `-909`
  (errSecBadReq) at that point, so every native-tls request still fails, and "Sign in with
  ChatGPT" fails with "error sending request". Measured on 2026-10-14 with AquaTransport
  2026.09.21. Codex's rustls retry is opt-in and not every API client turns it on.
- **Why shared:** loading the native roots takes about 450 ms on 10.9 (214 roots, measured on
  2026-10-14), and reqwest's own rustls loads them again for every client it builds. One `codex
  exec` built 10 clients that way, and upstream tests that build many clients ran past their time
  limits. Loading eagerly at the first client build was not enough: nextest runs every test in its
  own process, so plain-HTTP loopback tests and MCP startup paid for roots they never used.
- **Roots:** rustls trusts the roots in the keychain's trust settings. A stock 10.9 lacks ISRG
  Root X1 there. AquaTransport's ModernRootCertificates package adds it, which is enough for
  auth.openai.com, chatgpt.com and api.openai.com.
- **Invariant kept:** a client's own root certificate and client identity are honored as before.
  With `CODEX_CA_CERTIFICATE` or `SSL_CERT_FILE` set, upstream's custom-CA path is unchanged: it
  still builds reqwest's rustls for each client, so it still loads the roots each time.
- **Cost:** a change to the keychain's trust settings reaches a running Codex only after it
  restarts. The process's first TLS handshake still pays the one root load, about 450 ms on 10.9.
  An HTTPS MCP server configured with a `startup_timeout_sec` below about half a second can time
  out if its handshake is the first; the default is 30 s.
- **Clients outside `HttpClientBuilder`:** four reqwest clients are built elsewhere, and 0001
  puts each on rustls too. The blocking OTLP client (`otel/src/otlp.rs`) shares the config, or
  uses reqwest's rustls when it has its own CA or client identity. The log, trace and metrics
  exporters (`otel/src/provider.rs`, `otel/src/metrics/client.rs`) passed that client only when a
  `tls` table was configured; otherwise opentelemetry-otlp built its own, with native-tls. They
  now always pass it. `codex-responses-api-proxy` (`responses-api-proxy/src/lib.rs`) uses
  reqwest's rustls: that crate does not depend on `codex-http-client`, and adding the dependency
  would change `Cargo.lock`. `client_builder.rs`'s
  last-resort client tries the shared config before falling back to `reqwest::Client::new()`. The
  reqwest 0.13 that `rmcp` depends on is built with no TLS backend, so Codex gives it its own
  clients. Every other reqwest client in the workspace is in a test or the custom-CA test probe.
- **When to reconsider:** when upstream defaults reqwest to rustls, its rustls path covers every
  client, or AquaTransport returns a peer trust after a server-authentication break. That last
  would let native-tls work on 10.9 for every client, including any a later Codex adds, so
  forcing rustls in each place would no longer be needed.

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
  from enabled to disabled. The two TUI tests in `tests/suite/focus_palette.rs` that relied on
  the old default (`no_daemon_skips_startup_and_discovery` and
  `auto_daemon_start_failure_exits_with_manual_fallback_hint`) now set
  `features.daemon_auto_start = true` themselves.
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
