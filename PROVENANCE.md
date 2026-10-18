# Provenance

Patches 0004 to 0007 in `patches/` are Wowfunhappy's work, as were 0001, 0002 and 0003 until
they were removed (see "Removed patches" below). The received patch files are named for Codex
0.151.0 and 0.157.0 (see the table); the patches were carried to Codex 0.161.0 and measured there,
by building it natively on Mac OS X 10.9. They are CC0 and used with Wowfunhappy's permission.
Later patches are this product's own.

| Received file | Where it is now | How it changed |
|---|---|---|
| `test-builds.sh` | `0001-force-rustls.patch`, `0002-update-check-off-by-default.patch` and `0003-daemon-auto-start-off-by-default.patch`, all since removed | extracted byte for byte from the heredocs `CODEX_RUSTLS_TLS_PATCH`, `CODEX_DISABLE_UPDATE_CHECK_PATCH` and `CODEX_DISABLE_DAEMON_AUTO_START_PATCH`. 0001 was rewritten here before it was removed: it keeps the idea of forcing rustls for every client, but now does it in `client_builder.rs` with one shared config and marks the native-TLS retry tests ignored. 0003 was then given a hunk that updates the two TUI tests relying on the old default. The fourth heredoc, `CODEX_MAVERICKS_SEATBELT_PATCH`, is not kept: its hunks are a subset of 0006, and the script skips it once 0006 has applied. The script itself is not kept; its native-build knowledge is carried in `docs/compatibility-matrix.md` |
| `codex-0.157.0-mavericks-user-verification.patch` | `patches/0004-user-verification-unsupported.patch` | unchanged |
| `codex-0.157.0-mavericks-accessibility-probes.patch` | `patches/0005-accessibility-selector-guards.patch` | unchanged |
| `codex-0.151.0-mavericks-seatbelt.patch` | `patches/0006-seatbelt-policies.patch` | kept byte for byte, with one hunk added at the end that updates the KMP test to the guarded rule |
| `codex-0.157.0-mavericks-seatbelt-runtime.patch` | `patches/0007-seatbelt-runtime-policy.patch` | trimmed to `codex-rs/sandboxing/`: the `seatbelt.rs` and `seatbelt_daemon.rs` sections are kept byte for byte and the `codex-rs/cli/src/debug_sandbox.rs` section is dropped, as Wowfunhappy's script did with `git apply --include='codex-rs/sandboxing/**'` |

## Removed patches

Wowfunhappy's 0002 (the startup update check off by default) and 0003 (the app-server daemon's
auto-start off by default) were removed when Codex began updating itself from this product's own
builds. Both turned off an upstream feature that could not work here: the update check offered
update paths that failed or installed OpenAI's builds, and the daemon needed a packaged install
and updated itself to OpenAI's builds. Codex's update check and `codex update` now use this
product's builds channel and installer (0012), and the daemon updates through the same installer
(0013), so upstream's defaults stand. Their source,
`test-builds.sh`, stays in this repo's history under Wowfunhappy's authorship (see "Received files"),
and `patches/README.md` says what each patch did and why it went.

Wowfunhappy's 0001 (every HTTPS client on rustls) was removed once AquaTransport, which is also
Wowfunhappy's, fixed what the patch worked around (see `patches/README.md`), so the patch has
nothing left to do for Codex's HTTPS clients. The patch's history, with the
rewrite done here, stays in this repo under Wowfunhappy's authorship.

## Received files

Received from Wowfunhappy on 2026-10-13 and committed verbatim, with Wowfunhappy as author, in the
commit before they were arranged into `patches/`.

| File | SHA-256 |
|---|---|
| `codex-0.151.0-mavericks-seatbelt.patch` | `6f476e3fdb26a2d53bfb500e7b375ca9acc541fe835453ed2891fb59c44256d5` |
| `codex-0.157.0-mavericks-accessibility-probes.patch` | `72e68004d0978e47b2cd019e8371e5a5c85ff952aad62ebf8e55998224643472` |
| `codex-0.157.0-mavericks-seatbelt-runtime.patch` | `fd81b245265d83cafcc26563022625e93a3fc3c5b3891584c05cba8d345f0ea8` |
| `codex-0.157.0-mavericks-user-verification.patch` | `994b7ad33960344516da67aedec0fb7b3e4e927cb50819852a911e66b02d72c5` |
| `test-builds.sh` | `4caddbb1e71578011af0c7a547e9344ec52cf70315bbf869379da22b24d32f70` |

## The package's Codex installer

`tree/libexec/codex-cli/install.sh` is derived from OpenAI's `scripts/install/install.sh`, from
`openai/codex` at revision `979011409de0a60b52f179721948e65531d26144` (the one in
`build/codex-revision`). Codex is Apache-2.0; its `LICENSE` and `NOTICE`, copied from that revision,
travel with the installer in `tree/share/doc/codex-cli/`. The file's header lists the same changes:

1. release metadata and the package come from Mavergreen's builds channel (`CODEX_BUILDS_URL`), not
   from the GitHub API or releases.openai.com, and the npm layout, `codex-package_SHA256SUMS` and the
   Linux and Apple Silicon targets are gone; fetching metadata and signature times out after
   30 seconds and the package after 300
2. the metadata's `.sig` is checked with `ed25519-verify` against the package's public key before
   the metadata is parsed, so the temp dir and its cleanup trap are set up before the release is
   resolved; a refusal suggests trying again in a minute, since a fetch while a build is published
   can see the new `latest.json` beside the old signature
3. `validate_version` accepts `latest` and `<x.y.z>-mavericks.<N>`, and `tag_name` `rust-v<ID>`
   resolves to `<ID>`; because the package's `codex` reports OpenAI's `x.y.z` rather than the build
   ID, a release is complete when `codex --version` reports the build's `x.y.z`, and "already
   installed" is judged by the current link's release name
4. a build whose `mavergreen_min_pkg` is newer than the installed package installs nothing and exits
   3, before any progress line; an interactive run first opens the package's updater, and a guarded
   run (the daemon's markers, `CODEX_INSTALL_NO_UPDATER=1` as the launcher's first run sets, or no
   usable tty as in upstream's `prompt_yes_no`) opens nothing; `CODEX_NON_INTERACTIVE`, which
   `codex update` sets with somebody watching, guards nothing, since the prompts it skips upstream
   are removed
5. it never creates or changes `~/.local/bin/codex` or a shell profile, and does not look for
   conflicting installs
6. everything else, including the guarded modes the daemon uses and the `current` link but for 8,
   is upstream's, except that a build that is already installed says "Codex CLI <ID> is already
   installed" where upstream says "Updating Codex CLI"
7. the temp dir is made from an explicit `"${TMPDIR:-/tmp}"` template, the family conventions
   check's rule, where upstream's `mktemp -d` takes none
8. the `current` link is swapped atomically on 10.9 too: its `mv` has neither `-T` nor `-h`, so
   where both of upstream's attempts fail, perl's `rename(2)` replaces the link in one step before
   upstream's last resort (remove, then move)
