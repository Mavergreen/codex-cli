# Build ingredients

| Ingredient | Pin | Use |
| --- | --- | --- |
| OpenAI Codex | `UPSTREAM_VERSION` `0.161.0`; `build/codex-revision` `979011409de0a60b52f179721948e65531d26144` | CLI source and Cargo workspace |
| Mavergreen Rust | `mavericks-rust.pin` `48cf610771f9e006e79a02b59999200e9e22cc79` | Native and cross Rust compiler, Cargo, and target support |
| Mavergreen shipyard | inspected revision `66579f0a5899a16744a7c9c79e52e63b95a46fa2` | SDK, build mode, source fetch, compatibility, and package helpers |

Codex is fetched into a host-local build root with shipyard's `clone_pinned.sh`. The exact Codex
commit is verified before committed `patches/*.patch` files are applied. The `codex/` directory is
an ignored inspection checkout and is never a build input. The Rust checkout is fetched and verified
independently from its exact pin. Build and transfer staging directories must remain outside this
product source tree; `MAVERICKS_BUILD_ROOT` overrides the default `${TMPDIR:-/tmp}/mm-build`.

`build/build-codex.sh native` runs on ultimate-hat (Mac OS X 10.9). It builds the pinned Mavergreen
Rust toolchain and Codex CLI for `x86_64-apple-darwin`. `build/build-codex.sh cross` runs on modern
macOS and uses shipyard's pinned 10.9 SDK. Both paths set `MACOSX_DEPLOYMENT_TARGET=10.9`, use
Cargo's locked dependency graph, and set `CARGO_NET_GIT_FETCH_WITH_CLI=true` for nested Git sources.
Cargo home, target output, Rust work trees, and transfer staging stay under the local build root.

Only `codex-cli` is built and transferred. The package does not include `codex-voice-host`, the
native voice runtime, or `codex-resources/voice`; voice support is deferred. Native build and CLI
smoke validation on ultimate-hat remain required out-of-band checks and have not yet been run.

## Compatibility gate implementation

The imported Rust executable is checked by shipyard's `assert_binary_compatible.sh` from a CMake
custom target. Shipyard's `mavericks_assert_binary_compatible()` attaches a `POST_BUILD` command to
a compiled target, while CMake does not permit that command on an imported executable. The custom
target therefore invokes the same shipyard checker on the exact imported `codex` file.
