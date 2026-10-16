# Codex CLI for Mavericks

This README has not been read or edited by a human yet; it is a draft for the maintainer to rewrite.

OpenAI's Codex CLI (`codex`) for Mac OS X 10.9 Mavericks, on Intel Macs.

This is an unofficial, community build. It is not affiliated with or endorsed by OpenAI. It is
built from OpenAI's Codex source, modified by the patches in [`patches/`](patches/README.md) so it
builds and runs on 10.9.

## What gets installed

The package `codex-cli-<version>.pkg` (it needs Mac OS X 10.9.5 or later) installs:

- `/usr/local/mavergreen/codex-cli/bin/codex`, the command, and `bin/codex-code-mode-host` beside
  it, which `codex` runs itself for Code Mode
- `/usr/local/mavergreen/bin/codex`, a link to the command. `/usr/local/mavergreen/bin` is on the
  login `PATH`, so `codex` works in a new Terminal window. The host is not linked there: it is not a
  command to run by hand
- `/usr/local/mavergreen/codex-cli/share/doc/codex-cli/`: this README, Codex's `LICENSE` and
  `NOTICE` (Apache-2.0), and `build-manifest`, which records the Codex commit, toolchain versions
  and build mode the binaries came from
- the updater, `/Library/Application Support/Mavergreen/codex-cli-updater.app`, and its LaunchAgent
  `/Library/LaunchAgents/dev.mavergreen.codex-cli-updatecheck.plist`

## Before you sign in: root certificates

Sign-in and API access go over TLS, and this build checks servers' certificates against the roots
in the keychain's trust settings. A stock 10.9 lacks ISRG Root X1 there, so it cannot reach
`auth.openai.com`, `chatgpt.com` or `api.openai.com`. AquaTransport's ModernRootCertificates package
adds that root, and that is the setup this build was tested with. A change to the keychain's trust
settings reaches a running `codex` only after it restarts.

## What is different from upstream

- **No voice.** The voice runtime (`codex-voice-host` and `codex-resources/voice`) is not built or
  shipped, so Codex's voice features are unsupported.
- **No startup update check (patch 0002).** Upstream's check offers to update through the package
  manager it detects, such as Homebrew, which may be absent or unable to run on 10.9. This package
  updates itself instead (below). To turn the check back on, put this in `~/.codex/config.toml`:

      check_for_update_on_startup = true

- **No shared background daemon (patch 0003).** The daemon needs upstream's complete local package,
  which a cargo build like this one lacks, so it fails; its updater also installs upstream builds
  that 10.9 may not run. The TUI runs the app server in-process instead, as with `--no-daemon`. To
  turn it back on, in `~/.codex/config.toml`:

      [features]
      daemon_auto_start = true

- **No biometric user verification (patch 0004).** It needs LocalAuthentication and the Secure
  Enclave, which 10.9 lacks, so it always reports unsupported. It cannot be turned on.

The other patches make the build link and run on 10.9: HTTPS through rustls instead of the system
TLS (0001), Seatbelt sandbox policies 10.9 can parse (0006, 0007), and fixes for APIs 10.9 lacks
(0005, 0008, 0009). [`patches/README.md`](patches/README.md) says what each one changes and why.

## Known harmless warnings

`codex exec` prints a few lines like this on stderr per run:

    FSEventsPurgeEventsForDeviceUpToEventId: f2d_purge_events_for_device_up_to_event_id_rpc() failed: 5

They are harmless. Codex's file watcher (notify 8.2.0) calls a function only root may call, and
10.9 prints the failure. They go away when Codex moves to notify 9.

## Updating

The updater checks this product's feed once a day, silently. When it finds a new release it posts a
notification; click it to install the update.

## Uninstalling

```sh
sudo mavergreen uninstall codex-cli
```

This removes the installed tree, the `codex` link, the updater and its LaunchAgent. Codex's own
settings and login, in `~/.codex` (or `$CODEX_HOME`), are left alone; remove them yourself if you
want them gone.

## License

Codex is OpenAI's, under the Apache License 2.0; its `LICENSE` and `NOTICE` are installed in
`share/doc/codex-cli/`. These binaries are built from Codex's sources as modified by the patches in
[`patches/`](patches/README.md).

The binaries also contain open-source dependencies under their own licenses. They are listed in
Codex's pinned
[`codex-rs/Cargo.lock`](https://github.com/openai/codex/blob/979011409de0a60b52f179721948e65531d26144/codex-rs/Cargo.lock).
This matches upstream's own releases, which ship no separate third-party notices file.

## More

- [`patches/README.md`](patches/README.md): each patch, why it is needed, and when to reconsider it
- [`docs/compatibility-matrix.md`](docs/compatibility-matrix.md): what building and running Codex
  on 10.9 needed, and what was measured on real 10.9 hardware
- [`PROVENANCE.md`](PROVENANCE.md): where the patches came from. Patches 0001 to 0007 are
  Wowfunhappy's work, carried to Codex 0.161.0 and used with Wowfunhappy's permission. Thanks to
  Wowfunhappy, whose native 10.9 build of Codex came first
- [`INGREDIENTS.md`](INGREDIENTS.md): how it is built and packaged
