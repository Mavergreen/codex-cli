#!/bin/bash
#
# §8 test-builds: exercise the freshly-built native 10.9 Rust toolchain on a real-world crate
# (registry fetch + dependency graph + native C deps + proc-macros), proving it is not just a
# hello-world compiler. Builds `mergiraf` (the §8 example) with cargo into an isolated prefix.
#
# Prereqs: scripts/rust.sh (the rust-1.95.0 toolchain) and scripts/build.sh (clang-22).
#
#   ./test-builds.sh         build the test crates (idempotent; skips ones already built)
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
RUST="$ROOT/toolchains/rust-1.95.0"; CLANG="$ROOT/toolchains/clang-22"
OUT="$ROOT/build/test-builds"                       # disposable: cargo home + install prefix
mkdir -p "$OUT"

msg() { printf '\n=== %s ===\n' "$*"; }

# rustc (the polyfill-wrapping one) is on PATH; CARGO_HOME is isolated so we don't touch ~/.cargo.
# CC/CXX = clang-22 so the `cc` crate compiles native C/C++ deps (tree-sitter, ...) with a modern
# compiler -- the system clang-3.5's old C default rejects C11 `static_assert` as an undefined
# function. The final link of each binary goes through the wrapped rustc, which auto-links the
# polyfill, so 10.12 std symbols (and any the C deps need) resolve and the result runs on 10.9.
export PATH="$RUST/bin:$CLANG/bin:$ROOT/toolchains/tools/bin:$PATH"
export CARGO_HOME="$OUT/cargo-home"
export CC="$CLANG/bin/clang" CXX="$CLANG/bin/clang++"
# Link final binaries with clang-22's C++ driver (clang++), not the system cc: a large workspace
# like codex links thousands of object files, which overflows the system clang-3.5's argv (no
# response-file support) -> "posix_spawn: Argument list too long"; clang-22 uses a linker response
# file (via lld). It must be clang++ (not clang): codex links V8, which is C++, so it needs libc++/
# libc++abi/libunwind -- and those live in clang++.cfg, since the C clang.cfg is deliberately C-only.
# The wrapped rustc still adds the polyfill; the resulting double archive is harmless (lazy load,
# and the polyfill carries no ObjC classes).
export CARGO_TARGET_X86_64_APPLE_DARWIN_LINKER="$CLANG/bin/clang++"

require() {
  [ -x "$RUST/bin/cargo" ] || { echo "ERROR: rust toolchain missing -- run scripts/rust.sh first" >&2; exit 1; }
}

# Portability guard: a binary built with this toolchain must be self-contained -- it may NOT
# depend on the toolchain's own dylibs (@rpath/lib{c++,c++abi,unwind}) nor carry an absolute
# repo path in any rpath. clang++.cfg static-links the C++ runtime so this holds by default;
# this catches a regression (e.g. someone reintroducing a dynamic/-rpath link) HERE, loudly,
# instead of as "dyld: Library not loaded: @rpath/..." on another machine.
check_portable() {
  msg "portability audit (no @rpath toolchain dylibs, no absolute repo rpath)"
  local f bad=0 hits
  for f in "$OUT"/bin/*; do
    file "$f" 2>/dev/null | grep -q Mach-O || continue
    hits="$(otool -L "$f" 2>/dev/null | tail -n +2 | grep -E '@rpath/(libc\+\+|libc\+\+abi|libunwind)' || true)"
    hits="$hits$(otool -l "$f" 2>/dev/null | awk '/LC_RPATH/{r=1} r&&/ path /{print $2; r=0}' | grep -F "$ROOT" || true)"
    [ -n "$hits" ] && { bad=$((bad+1)); echo "NOT PORTABLE: ${f#$OUT/}"; echo "$hits" | sed "s#$ROOT#<REPO>#g;s/^/    /"; }
  done
  [ "$bad" -eq 0 ] && echo "all $OUT/bin binaries are self-contained" || { echo "ERROR: $bad non-portable binary(ies) above" >&2; return 1; }
}

# mergiraf: a syntax-aware merge driver (tree-sitter native deps). Pinned for reproducibility.
MERGIRAF_VER="0.6.0"
build_mergiraf() {
  [ -x "$OUT/bin/mergiraf" ] && return 0
  msg "test-build: mergiraf $MERGIRAF_VER (cargo install with the native 10.9 rust)"
  cargo install --locked --version "$MERGIRAF_VER" --root "$OUT" mergiraf
}

# OpenAI Codex CLI: a large real-world workspace (vendored OpenSSL, zstd, rustls, ...)
# whose codex-rs/rust-toolchain.toml pins exactly Rust 1.95.0 -- the version we built. The current
# stable release tag and commit are both pinned for reproducibility. The CLI and its required Code
# Mode host are built in a versioned staging prefix, then installed together under $OUT/bin.
#
# Patch (inlined in build_codex below): codex's reqwest is configured with default features on, so
# it defaults to the native-tls (SecureTransport) backend -- which cannot negotiate modern TLS on
# 10.9 and breaks "Sign in with ChatGPT" with a handshake error. Codex 0.157.0 has a narrow, opt-in
# rustls retry path, but ordinary API clients do not all enable it. The patch therefore forces the
# bundled rustls backend (which works with the platform native roots) for every Codex HTTP request.
# Update checks are disabled by default because this compatibility build runs on hosts where the
# detected package manager (notably Homebrew) may be absent or unable to run. Users can still opt
# in explicitly with check_for_update_on_startup = true. For the same reason the TUI does not
# auto-start the shared background app-server daemon: that daemon runs from a packaged install
# (which a cargo build lacks, so startup fails with "this CLI has no complete local package") and
# its updater installs upstream builds. The TUI hosts its app server in-process instead, exactly as
# with --no-daemon; users can opt in with [features] daemon_auto_start = true. The Seatbelt patches split process-info*
# into the concrete operations supported by Mavericks:
# 10.9 rejects a target filter on the wildcard and on listpids, so listpids is targetless while the
# six target-filterable operations retain the original same-sandbox restriction. Feature guards
# preserve newer macOS allowlists while omitting optional filters that 10.9 cannot parse. The 0.157
# runtime policy adds more post-Mavericks filter names and a pathname-qualified Unix-socket deny;
# guarded fallbacks keep the daemon boundary and TIOCSTI protection intact on 10.9.
# Codex 0.157.0 also adds biometric user verification backed by LocalAuthentication and Secure
# Enclave APIs. Mavericks has neither, so the compatibility patch routes that component through
# Codex's existing unsupported-provider path instead of advertising an unusable native verifier.
# The TUI probes the host's reduce-motion and VoiceOver settings through NSWorkspace selectors that
# first appear in 10.12 and 10.13; on 10.9 the unrecognized selector raises an Objective-C
# exception that aborts at launch. The accessibility patch checks respondsToSelector: first and
# treats a missing selector as "no preference".
CODEX_REPO="https://github.com/openai/codex.git"
CODEX_VERSION="0.161.0"
CODEX_TAG="rust-v$CODEX_VERSION"
CODEX_COMMIT="979011409de0a60b52f179721948e65531d26144"
CODEX_SRC="$ROOT/codex-$CODEX_VERSION"
CODEX_INSTALL="$OUT/codex-$CODEX_VERSION-install"
# Share compiled dependencies across Codex patch releases.
export CARGO_TARGET_DIR="$OUT/codex-target"
CODEX_BIN="$OUT/bin/codex"
CODEX_HOST_BIN="$OUT/bin/codex-code-mode-host"
CODEX_V8_VERSION="150.4.0"
CODEX_V8_TARGET="x86_64-apple-darwin"
CODEX_V8_PROFILE="ptrcomp_sandbox_release"
CODEX_V8_DIR="$OUT/rusty-v8-$CODEX_V8_VERSION-$CODEX_V8_TARGET"
CODEX_V8_ARCHIVE="$CODEX_V8_DIR/librusty_v8_${CODEX_V8_PROFILE}_${CODEX_V8_TARGET}.a.gz"
CODEX_V8_BINDING="$CODEX_V8_DIR/src_binding_${CODEX_V8_PROFILE}_${CODEX_V8_TARGET}.rs"
CODEX_V8_CHECKSUMS="$CODEX_V8_DIR/rusty_v8_${CODEX_V8_PROFILE}_${CODEX_V8_TARGET}.sha256"
fetch_codex_v8_artifacts() {
  local base_url="https://github.com/openai/codex/releases/download/rusty-v8-v$CODEX_V8_VERSION"
  mkdir -p "$CODEX_V8_DIR"
  if [ -f "$CODEX_V8_ARCHIVE" ] && [ -f "$CODEX_V8_BINDING" ] &&
      [ -f "$CODEX_V8_CHECKSUMS" ] &&
      ( cd "$CODEX_V8_DIR" && shasum -a 256 -c "${CODEX_V8_CHECKSUMS##*/}" >/dev/null 2>&1 ); then
    return 0
  fi
  msg "fetch Codex-built sandboxed V8 $CODEX_V8_VERSION ($CODEX_V8_TARGET)"
  local artifact tmp
  for artifact in "$CODEX_V8_ARCHIVE" "$CODEX_V8_BINDING" "$CODEX_V8_CHECKSUMS"; do
    tmp="$artifact.tmp"
    rm -f "$tmp"
    curl -fsSL "$base_url/${artifact##*/}" -o "$tmp"
    mv "$tmp" "$artifact"
  done
  [ "$(wc -l < "$CODEX_V8_CHECKSUMS")" -eq 2 ] || {
    echo "ERROR: expected exactly two Codex V8 checksums in $CODEX_V8_CHECKSUMS" >&2
    return 1
  }
  ( cd "$CODEX_V8_DIR" && shasum -a 256 -c "${CODEX_V8_CHECKSUMS##*/}" )
}
codex_is_current() {
  "$CODEX_BIN" --version 2>/dev/null | grep -qF "codex-cli $CODEX_VERSION" &&
    [ "$CODEX_BIN" -nt "$CODEX_SRC/codex-rs/sandboxing/src/seatbelt_base_policy.sbpl" ] &&
    [ "$CODEX_BIN" -nt "$CODEX_SRC/codex-rs/sandboxing/src/seatbelt_preferences_policy.sbpl" ] &&
    [ "$CODEX_BIN" -nt "$CODEX_SRC/codex-rs/sandboxing/src/seatbelt_tests.rs" ] &&
    [ "$CODEX_BIN" -nt "$CODEX_SRC/codex-rs/sandboxing/src/seatbelt.rs" ] &&
    [ "$CODEX_BIN" -nt "$CODEX_SRC/codex-rs/sandboxing/src/seatbelt_daemon.rs" ] &&
    [ "$CODEX_BIN" -nt "$CODEX_SRC/codex-rs/cli/src/debug_sandbox.rs" ] &&
    [ "$CODEX_BIN" -nt "$CODEX_SRC/codex-rs/http-client/src/custom_ca.rs" ] &&
    [ "$CODEX_BIN" -nt "$CODEX_SRC/codex-rs/core/src/config/mod.rs" ] &&
    [ "$CODEX_BIN" -nt "$CODEX_SRC/codex-rs/features/src/lib.rs" ] &&
    [ "$CODEX_BIN" -nt "$CODEX_SRC/codex-rs/user-verification/src/lib.rs" ] &&
    [ "$CODEX_BIN" -nt "$CODEX_SRC/codex-rs/tui/src/system_motion.rs" ] &&
    [ "$CODEX_BIN" -nt "$CODEX_SRC/codex-rs/tui/src/screen_reader.rs" ]
}
code_mode_host_is_current() {
  [ -x "$CODEX_HOST_BIN" ] &&
    [ "$CODEX_HOST_BIN" -nt "$CODEX_SRC/codex-rs/code-mode-host/Cargo.toml" ] &&
    [ "$CODEX_HOST_BIN" -nt "$CODEX_SRC/codex-rs/code-mode-host/src/main.rs" ] &&
    [ "$CODEX_HOST_BIN" -nt "$CODEX_SRC/codex-rs/code-mode-host/src/lib.rs" ]
}
build_codex() {
  if codex_is_current && code_mode_host_is_current; then
    return 0
  fi
  msg "test-build: openai/codex CLI $CODEX_VERSION (${CODEX_COMMIT:0:12}; requires rust 1.95.0)"
  if [ ! -d "$CODEX_SRC/.git" ]; then
    git clone --branch "$CODEX_TAG" --depth 1 "$CODEX_REPO" "$CODEX_SRC"
  fi
  local actual
  actual="$(git -C "$CODEX_SRC" rev-parse HEAD)"
  [ "$actual" = "$CODEX_COMMIT" ] || {
    echo "ERROR: $CODEX_SRC is at $actual, expected $CODEX_COMMIT ($CODEX_TAG)" >&2
    exit 1
  }
  # Apply the rustls-TLS fix as an inline diff (see comment above). A marker makes reruns safe
  # without discarding any source changes that may be under investigation in this versioned tree.
  if ! grep -qF 'macOS 10.9: reqwest defaults to Secure Transport' \
      "$CODEX_SRC/codex-rs/http-client/src/custom_ca.rs"; then
    ( cd "$CODEX_SRC" && git apply <<'CODEX_RUSTLS_TLS_PATCH'
diff --git a/codex-rs/http-client/src/custom_ca.rs b/codex-rs/http-client/src/custom_ca.rs
--- a/codex-rs/http-client/src/custom_ca.rs
+++ b/codex-rs/http-client/src/custom_ca.rs
@@ -291,6 +291,13 @@ fn build_reqwest_client_with_env(
     env_source: &dyn EnvSource,
     mut builder: reqwest::ClientBuilder,
 ) -> Result<reqwest::Client, BuildCustomCaTransportError> {
+    // macOS 10.9: reqwest defaults to Secure Transport, which cannot negotiate modern TLS and
+    // fails with a handshake error. Codex's rustls retry is opt-in and does not cover every API
+    // client, so force the bundled rustls backend (with platform native roots) for every request,
+    // not only the custom-CA path.
+    ensure_rustls_crypto_provider();
+    builder = builder.use_rustls_tls();
+
     if let Some(bundle) = env_source.configured_ca_bundle() {
         ensure_rustls_crypto_provider();
         info!(
CODEX_RUSTLS_TLS_PATCH
    )
  fi
  if ! grep -qF 'This compatibility build targets macOS versions' \
      "$CODEX_SRC/codex-rs/core/src/config/mod.rs"; then
    ( cd "$CODEX_SRC" && git apply <<'CODEX_DISABLE_UPDATE_CHECK_PATCH'
diff --git a/codex-rs/core/src/config/mod.rs b/codex-rs/core/src/config/mod.rs
--- a/codex-rs/core/src/config/mod.rs
+++ b/codex-rs/core/src/config/mod.rs
@@ -3921,7 +3921,10 @@ impl Config {
 
         let review_model = override_review_model.or(cfg.review_model);
 
-        let check_for_update_on_startup = cfg.check_for_update_on_startup.unwrap_or(true);
+        // This compatibility build targets macOS versions where Codex's detected package manager
+        // may be unavailable. Avoid background update checks unless the user explicitly enables
+        // them, so startup never offers an update path that cannot run on the host.
+        let check_for_update_on_startup = cfg.check_for_update_on_startup.unwrap_or(false);
         let model_catalog = load_model_catalog(cfg.model_catalog_json.clone())?;
 
         let log_dir = cfg
CODEX_DISABLE_UPDATE_CHECK_PATCH
    )
  fi
  if ! grep -qF 'This compatibility build has no packaged install' \
      "$CODEX_SRC/codex-rs/features/src/lib.rs"; then
    ( cd "$CODEX_SRC" && git apply <<'CODEX_DISABLE_DAEMON_AUTO_START_PATCH'
diff --git a/codex-rs/features/src/lib.rs b/codex-rs/features/src/lib.rs
--- a/codex-rs/features/src/lib.rs
+++ b/codex-rs/features/src/lib.rs
@@ -941,7 +941,10 @@ pub const FEATURES: &[FeatureSpec] = &[
         id: Feature::DaemonAutoStart,
         key: "daemon_auto_start",
         stage: Stage::Stable,
-        default_enabled: true,
+        // This compatibility build has no packaged install for the shared background server, and
+        // that server's updater installs upstream builds the host may not run. Start it only when
+        // the user explicitly enables it.
+        default_enabled: false,
     },
     FeatureSpec {
         id: Feature::TranscriptV2,
CODEX_DISABLE_DAEMON_AUTO_START_PATCH
    )
  fi
  if ! grep -qF 'macOS 10.9 has no LocalAuthentication framework' \
      "$CODEX_SRC/codex-rs/user-verification/src/lib.rs"; then
    git -C "$CODEX_SRC" apply \
      "$ROOT/scripts/patches/codex-0.157.0-mavericks-user-verification.patch"
  fi
  if ! grep -qF 'NSWorkspace gains accessibilityDisplayShouldReduceMotion' \
      "$CODEX_SRC/codex-rs/tui/src/system_motion.rs"; then
    git -C "$CODEX_SRC" apply \
      "$ROOT/scripts/patches/codex-0.157.0-mavericks-accessibility-probes.patch"
  fi
  if ! grep -qF 'Backwards compatibility for macOS 10.9' \
      "$CODEX_SRC/codex-rs/sandboxing/src/seatbelt_base_policy.sbpl"; then
    git -C "$CODEX_SRC" apply \
      "$ROOT/scripts/patches/codex-0.151.0-mavericks-seatbelt.patch"
  fi
  if ! grep -qF 'Mavericks rejects target filters' \
      "$CODEX_SRC/codex-rs/sandboxing/src/seatbelt_base_policy.sbpl"; then
    ( cd "$CODEX_SRC" && git apply <<'CODEX_MAVERICKS_SEATBELT_PATCH'
diff --git a/codex-rs/sandboxing/src/seatbelt_base_policy.sbpl b/codex-rs/sandboxing/src/seatbelt_base_policy.sbpl
--- a/codex-rs/sandboxing/src/seatbelt_base_policy.sbpl
+++ b/codex-rs/sandboxing/src/seatbelt_base_policy.sbpl
@@ -13,7 +13,17 @@
 (allow signal (target same-sandbox))
 
 ; process-info
-(allow process-info* (target same-sandbox))
+; Mavericks rejects target filters on both the process-info* wildcard and the
+; targetless listpids operation. Keep listpids separate and apply the original
+; same-sandbox restriction to every concrete operation that accepts it.
+(allow process-info-listpids)
+(allow process-info-pidinfo
+  process-info-pidfdinfo
+  process-info-pidfileportinfo
+  process-info-setcontrol
+  process-info-dirtycontrol
+  process-info-rusage
+  (target same-sandbox))
 
 (allow file-write-data
   (require-all
diff --git a/codex-rs/sandboxing/src/seatbelt_tests.rs b/codex-rs/sandboxing/src/seatbelt_tests.rs
--- a/codex-rs/sandboxing/src/seatbelt_tests.rs
+++ b/codex-rs/sandboxing/src/seatbelt_tests.rs
@@ -136,6 +136,32 @@ fn base_policy_allows_node_cpu_sysctls() {
     );
 }
 
+#[cfg(target_os = "macos")]
+#[test]
+fn generated_seatbelt_profile_is_accepted_by_sandbox_exec() {
+    let workspace = TempDir::new().expect("temp workspace");
+    let args = create_seatbelt_command_args_for_legacy_policy(
+        vec!["/usr/bin/true".to_string()],
+        &SandboxPolicy::new_read_only_policy(),
+        workspace.path(),
+        /*enforce_managed_network*/ false,
+        /*network*/ None,
+    )
+    .expect("create seatbelt args");
+
+    let output = Command::new(MACOS_PATH_TO_SEATBELT_EXECUTABLE)
+        .args(args)
+        .current_dir(workspace.path())
+        .output()
+        .expect("execute generated seatbelt profile");
+
+    assert!(
+        output.status.success(),
+        "sandbox-exec rejected generated profile: {}",
+        String::from_utf8_lossy(&output.stderr)
+    );
+}
+
 #[test]
 fn seatbelt_allows_semaphore_limit_sysconf() {
     let workspace = TempDir::new().expect("temp workspace");
CODEX_MAVERICKS_SEATBELT_PATCH
    )
  fi
  if ! grep -qF 'Mavericks rejects pathname filters nested inside' \
      "$CODEX_SRC/codex-rs/sandboxing/src/seatbelt_daemon.rs"; then
    # Upstream now emits a numeric TIOCSTI value, so only the Seatbelt policy
    # hunks of the older runtime patch are still needed.
    git -C "$CODEX_SRC" apply --include='codex-rs/sandboxing/**' \
      "$ROOT/scripts/patches/codex-0.157.0-mavericks-seatbelt-runtime.patch"
  fi
  # Cargo's embedded Git transport uses Mavericks Secure Transport and cannot fetch modern GitHub
  # endpoints. Delegate Git dependencies to the system git client, which works on this machine.
  # protoc-bin-vendored ships a modern C++ protoc that expects newer libc++ symbols than 10.9 has.
  # Inject clang-22's repository-local runtime into build-time host tools only; the installed Codex
  # binary remains self-contained and receives no DYLD environment at runtime.
  # Disable upstream's release ThinLTO to keep rebuild and link times practical on this host.
  local host_cxx_runtime="$CLANG/lib/libc++.1.dylib:$CLANG/lib/libc++abi.1.dylib:$CLANG/lib/libunwind.1.dylib"
  if ! codex_is_current; then
    ( cd "$CODEX_SRC/codex-rs" && \
        CARGO_NET_GIT_FETCH_WITH_CLI=true \
        CARGO_PROFILE_RELEASE_LTO=false \
        DYLD_INSERT_LIBRARIES="$host_cxx_runtime" DYLD_FORCE_FLAT_NAMESPACE=1 \
        cargo install --locked --path cli --root "$CODEX_INSTALL" ) || return 1
    install -m755 "$CODEX_INSTALL/bin/codex" "$CODEX_BIN"
  fi
  if ! code_mode_host_is_current; then
    fetch_codex_v8_artifacts || return 1
    ( cd "$CODEX_SRC/codex-rs" && \
        CARGO_NET_GIT_FETCH_WITH_CLI=true \
        CARGO_PROFILE_RELEASE_LTO=false \
        RUSTY_V8_ARCHIVE="$CODEX_V8_ARCHIVE" \
        RUSTY_V8_SRC_BINDING_PATH="$CODEX_V8_BINDING" \
        DYLD_INSERT_LIBRARIES="$host_cxx_runtime" DYLD_FORCE_FLAT_NAMESPACE=1 \
        cargo install --locked --path code-mode-host --root "$CODEX_INSTALL" ) || return 1
    install -m755 "$CODEX_INSTALL/bin/codex-code-mode-host" "$CODEX_HOST_BIN"
  fi
  rm -rf "$CODEX_INSTALL"
}

case "${1:-all}" in
  all)   require; build_mergiraf; build_codex
         msg "test-build smoke checks"; "$OUT/bin/mergiraf" --version; "$CODEX_BIN" --version
         check_portable ;;
  codex) require; build_codex; "$CODEX_BIN" --version; check_portable ;;
  check) check_portable ;;
  *) echo "usage: $0 [all|codex|check]"; exit 1 ;;
esac
