# Provenance

Patches 0001 to 0007 in `patches/` are Wowfunhappy's work, made against Codex 0.161.0 and tested by
building it natively on Mac OS X 10.9. They are CC0 and used with Wowfunhappy's permission. Later
patches are this product's own.

| Received file | Where it is now | How it changed |
|---|---|---|
| `test-builds.sh` | `patches/0001-force-rustls.patch`, `0002-update-check-off-by-default.patch`, `0003-daemon-auto-start-off-by-default.patch` | extracted byte for byte from the heredocs `CODEX_RUSTLS_TLS_PATCH`, `CODEX_DISABLE_UPDATE_CHECK_PATCH` and `CODEX_DISABLE_DAEMON_AUTO_START_PATCH`. The fourth heredoc, `CODEX_MAVERICKS_SEATBELT_PATCH`, is not kept: its hunks are a subset of 0006, and the script skips it once 0006 has applied. The script itself is not kept; its native-build knowledge is carried in `docs/compatibility-matrix.md` |
| `codex-0.157.0-mavericks-user-verification.patch` | `patches/0004-user-verification-unsupported.patch` | unchanged |
| `codex-0.157.0-mavericks-accessibility-probes.patch` | `patches/0005-accessibility-selector-guards.patch` | unchanged |
| `codex-0.151.0-mavericks-seatbelt.patch` | `patches/0006-seatbelt-policies.patch` | unchanged |
| `codex-0.157.0-mavericks-seatbelt-runtime.patch` | `patches/0007-seatbelt-runtime-policy.patch` | trimmed to `codex-rs/sandboxing/`: the `seatbelt.rs` and `seatbelt_daemon.rs` sections are kept byte for byte and the `codex-rs/cli/src/debug_sandbox.rs` section is dropped, as Wowfunhappy's script did with `git apply --include='codex-rs/sandboxing/**'` |

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
