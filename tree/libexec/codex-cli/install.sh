#!/bin/sh
# platform: macOS-only -- installs the x86_64-apple-darwin build and reads the package's version with PlistBuddy
# Mavergreen's Codex installer, derived from OpenAI's scripts/install/install.sh.
#
# Source: https://github.com/openai/codex, scripts/install/install.sh at revision
#   979011409de0a60b52f179721948e65531d26144 (the revision in build/codex-revision).
# License: Apache-2.0; the LICENSE and NOTICE of Codex travel with it in share/doc/codex-cli/.
#
# Changes from upstream:
#   1. Source: release metadata comes from $CODEX_BUILDS_URL (default: Mavergreen's builds channel),
#      latest.json for "latest" and codex-build-<ID>.json for a requested ID, and the asset is
#      codex-package-x86_64-apple-darwin-<ID>.tar.gz from the same base. The GitHub API and
#      releases.openai.com paths, the npm layout and codex-package_SHA256SUMS are removed, as are
#      the Linux and Apple Silicon targets. The asset's digest comes from the signed metadata.
#      Fetching the channel's metadata and signature times out after 30 seconds (upstream's
#      metadata timeout) and the package after 300.
#   2. Signature: the metadata's .sig is fetched and checked with $CODEX_ED25519_VERIFY against
#      the package's public key before the metadata is parsed. The temp dir and its cleanup trap
#      are therefore set up before the release is resolved. A refusal suggests trying again in a
#      minute: a fetch while a build is published can see a new latest.json beside the old signature.
#   3. Versions: validate_version accepts "latest" and <x.y.z>-mavericks.<N>; tag_name rust-v<ID>
#      resolves to <ID>. The package's codex reports OpenAI's x.y.z, not the build ID, so a
#      release counts as complete when `codex --version` reports the build's x.y.z. Whether the
#      requested build is already installed is judged by the current link's release name.
#   4. Package requirement: a build whose mavergreen_min_pkg is newer than the installed package
#      installs nothing; an interactive run opens the package's updater, and either way exits 3,
#      before any "Updating" or "Resolved version" line. A run is guarded (it opens nothing) when
#      CODEX_INSTALL_IF_LATEST, CODEX_INSTALL_IF_CURRENT or CODEX_INSTALL_DAEMON_ONLY is 1, when
#      CODEX_INSTALL_NO_UPDATER is 1 (the launcher's first run), or when, as in upstream's
#      prompt_yes_no, there is no usable /dev/tty and stdin is not a tty (CODEX_INSTALL_ASSUME_TTY=1
#      overrides that, for tests). CODEX_NON_INTERACTIVE, which `codex update` sets, guards nothing:
#      upstream's prompts, which it skips, are removed, so NON_INTERACTIVE is never read.
#   5. One codex: the installer never creates or changes ~/.local/bin/codex or a shell profile
#      (the launcher owns the link), and it does not look for conflicting installs.
#   6. Everything else (lock, staging, digest check, the current link but for 8, CODEX_HOME, the
#      guarded modes) is upstream's, except that a build that is already installed says "Codex CLI
#      <ID> is already installed" where upstream says "Updating Codex CLI".
#   7. The temp dir is made from an explicit "${TMPDIR:-/tmp}" template, where upstream's
#      `mktemp -d` takes none. 10.9's mktemp accepts either; the template is the family conventions
#      check's rule, which flags a bare `mktemp -d`.
#   8. The current link is swapped atomically on 10.9 too: 10.9's mv has neither -T nor -h, so where
#      both of upstream's attempts fail, perl's rename(2) replaces the link in one step before
#      upstream's last resort (remove, then move) is tried.

set -eu

RELEASE="${CODEX_RELEASE:-latest}"
DAEMON_ONLY="${CODEX_INSTALL_DAEMON_ONLY:-0}"
BUILDS_URL="${CODEX_BUILDS_URL:-https://github.com/Mavergreen/codex-cli/releases/download/codex-builds}"
BUILDS_URL="${BUILDS_URL%/}"
PKG_ROOT="${CODEX_PKG_ROOT:-/usr/local/mavergreen/codex-cli}"
ED25519_VERIFY="${CODEX_ED25519_VERIFY:-/usr/local/mavergreen/ed25519/bin/ed25519-verify}"
UPDATER_OPEN="${CODEX_PKG_UPDATER_OPEN:-/usr/bin/open '/Library/Application Support/Mavergreen/codex-cli-updater.app' --args --user}"
RELEASES_CONNECT_TIMEOUT=10
RELEASES_METADATA_TIMEOUT=30
RELEASES_ASSET_TIMEOUT=300
vendor_target="x86_64-apple-darwin"
install_layout="package"

CODEX_HOME_DIR="${CODEX_HOME:-$HOME/.codex}"
STANDALONE_ROOT="$CODEX_HOME_DIR/packages/standalone"
if [ "$DAEMON_ONLY" = "1" ]; then
  STANDALONE_ROOT="$CODEX_HOME_DIR/packages/app-server-daemon"
fi
RELEASES_DIR="$STANDALONE_ROOT/releases"
CURRENT_LINK="$STANDALONE_ROOT/current"
if [ "${CODEX_INSTALL_DEFER_SELECTION:-0}" = "1" ]; then
  if [ "$DAEMON_ONLY" != "1" ]; then
    echo "Deferred selection requires a daemon-only installation." >&2
    exit 1
  fi
  CURRENT_LINK="$STANDALONE_ROOT/.migration-current"
fi
AUTO_UPDATE_VERSION="$STANDALONE_ROOT/auto-update-version"
LOCK_FILE="$STANDALONE_ROOT/install.lock"
LOCK_DIR="$STANDALONE_ROOT/install.lock.d"
LOCK_STALE_AFTER_SECS=600

lock_kind=""
tmp_dir=""

step() {
  printf '==> %s\n' "$1"
}

warn() {
  printf 'WARNING: %s\n' "$1" >&2
}

normalize_version() {
  case "$1" in
    "" | latest)
      printf 'latest\n'
      ;;
    rust-v*)
      printf '%s\n' "${1#rust-v}"
      ;;
    v*)
      printf '%s\n' "${1#v}"
      ;;
    *)
      printf '%s\n' "$1"
      ;;
  esac
}

validate_version() {
  version="$1"

  if [ "$version" = "latest" ]; then
    return
  fi

  if ! printf '%s\n' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+-mavericks\.[1-9][0-9]*$'; then
    echo "Invalid Codex build: $version. Expected latest or x.y.z-mavericks.N." >&2
    return 1
  fi
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --release)
        if [ "$#" -lt 2 ]; then
          echo "--release requires a value." >&2
          exit 1
        fi
        RELEASE="$2"
        shift
        ;;
      --help | -h)
        cat <<EOF
Usage: install.sh [--release BUILD]

Environment:
  CODEX_RELEASE          Build to install (latest or x.y.z-mavericks.N); overridden by --release.
  CODEX_NON_INTERACTIVE  Accepted, as upstream's; this installer asks nothing, so it has no effect.
  CODEX_INSTALL_NO_UPDATER  Set to 1 for a run that must never open the package's updater.
  CODEX_BUILDS_URL       Where the builds channel is (any curl URL).
EOF
        exit 0
        ;;
      *)
        echo "Unknown argument: $1" >&2
        exit 1
        ;;
    esac
    shift
  done
}

download_file() {
  url="$1"
  output="$2"
  max_time="${3:-$RELEASES_ASSET_TIMEOUT}"

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --connect-timeout "$RELEASES_CONNECT_TIMEOUT" --max-time "$max_time" "$url" -o "$output"
    return
  fi

  if command -v wget >/dev/null 2>&1; then
    wget -q -t 1 -T "$max_time" -O "$output" "$url"
    return
  fi

  echo "curl or wget is required to install Codex." >&2
  exit 1
}

parse_release_metadata() {
  # Bound awk's record size so compact, single-line JSON stays fast on every
  # supported awk implementation. JSON strings cannot contain literal newlines,
  # so the record boundaries inserted by fold do not change the document.
  LC_ALL=C fold -b -w 4096 | LC_ALL=C awk '
    function finish_string(value) {
      if (object_depth == 1 && key == "tag_name") {
        print "tag_name\t" value
      } else if (object_depth == 1 && key == "mavergreen_min_pkg") {
        print "min_pkg\t" value
      } else if (object_depth == asset_object_depth) {
        if (key == "name") {
          asset_name = value
        } else if (key == "digest") {
          asset_digest = value
        }
      }

      expecting_value = 0
      key = ""
    }

    {
      for (i = 1; i <= length($0); i++) {
        char = substr($0, i, 1)

        if (in_string) {
          if (escaped) {
            token = token "\\" char
            escaped = 0
          } else if (char == "\\") {
            escaped = 1
          } else if (char == "\"") {
            in_string = 0
            if (string_is_value) {
              finish_string(token)
            } else {
              pending_key = token
            }
          } else {
            token = token char
          }
          continue
        }

        if (char == "\"") {
          in_string = 1
          token = ""
          escaped = 0
          string_is_value = expecting_value
        } else if (char == ":" && pending_key != "") {
          key = pending_key
          pending_key = ""
          expecting_value = 1
        } else if (char == "{") {
          object_depth++
          if (assets_array_depth != 0 &&
              array_depth == assets_array_depth &&
              asset_object_depth == 0) {
            asset_object_depth = object_depth
            asset_name = ""
            asset_digest = ""
          }
          expecting_value = 0
          key = ""
        } else if (char == "}") {
          if (object_depth == asset_object_depth) {
            if (asset_name != "" && asset_digest != "") {
              print "asset\t" asset_name "\t" asset_digest
            }
            asset_object_depth = 0
            asset_name = ""
            asset_digest = ""
          }
          object_depth--
          expecting_value = 0
          key = ""
          pending_key = ""
        } else if (char == "[") {
          array_depth++
          if (expecting_value && key == "assets" && object_depth == 1) {
            assets_array_depth = array_depth
          }
          expecting_value = 0
          key = ""
        } else if (char == "]") {
          if (array_depth == assets_array_depth) {
            assets_array_depth = 0
          }
          array_depth--
          expecting_value = 0
          key = ""
          pending_key = ""
        } else if (char == ",") {
          expecting_value = 0
          key = ""
          pending_key = ""
        }
      }
    }

    END {
      if (in_string || object_depth != 0 || array_depth != 0) {
        exit 1
      }
    }
  '
}

parse_downloaded_release_metadata() {
  requested_release="$1"
  source_name="$2"
  if ! release_metadata="$(printf '%s\n' "$release_json" | parse_release_metadata)"; then
    echo "Could not parse $source_name release metadata for Codex $requested_release." >&2
    return 1
  fi
}

resolve_metadata_version() {
  release_tag="$(printf '%s\n' "$release_metadata" | awk -F '\t' '$1 == "tag_name" { print $2; exit }')"
  case "$release_tag" in
    rust-v*) metadata_version="${release_tag#rust-v}" ;;
    *) metadata_version="" ;;
  esac
  if [ -z "$metadata_version" ]; then
    echo "Failed to resolve the Codex build from the metadata." >&2
    return 1
  fi
  validate_version "$metadata_version"
}

verify_metadata_signature() {
  metadata_file="$1"
  signature_file="$metadata_file.sig"
  public_key_file="$PKG_ROOT/share/codex-cli/ed25519_key.pub"

  if ! download_file "$2.sig" "$signature_file" "$RELEASES_METADATA_TIMEOUT"; then
    echo "Could not fetch the build metadata's signature from $2.sig." >&2
    return 1
  fi
  if [ ! -x "$ED25519_VERIFY" ]; then
    echo "Could not run the signature verifier at $ED25519_VERIFY." >&2
    return 1
  fi
  if [ ! -r "$public_key_file" ]; then
    echo "Could not read the package's public key at $public_key_file." >&2
    return 1
  fi
  if ! "$ED25519_VERIFY" -p "$(cat "$public_key_file")" "$metadata_file" "$(cat "$signature_file")" >/dev/null 2>&1; then
    # publishing replaces latest.json and then its signature, so a fetch between the two sees a pair
    # that does not match for a few seconds
    echo "The build metadata's signature does not verify; refusing $2. If a build was being published just then, try again in a minute." >&2
    return 1
  fi
}

resolve_release() {
  normalized_version="$(normalize_version "$RELEASE")"
  validate_version "$normalized_version"

  if [ "$normalized_version" = "latest" ]; then
    requested_release="latest"
    metadata_url="$BUILDS_URL/latest.json"
  else
    requested_release="$normalized_version"
    metadata_url="$BUILDS_URL/codex-build-$normalized_version.json"
  fi

  metadata_path="$tmp_dir/release.json"
  if ! download_file "$metadata_url" "$metadata_path" "$RELEASES_METADATA_TIMEOUT"; then
    echo "Could not fetch the build metadata for Codex $requested_release from $metadata_url." >&2
    exit 1
  fi
  if ! verify_metadata_signature "$metadata_path" "$metadata_url"; then
    exit 1
  fi
  release_json="$(cat "$metadata_path")"

  parse_downloaded_release_metadata "$requested_release" "the builds channel's" || exit 1
  resolve_metadata_version || exit 1
  if [ "$normalized_version" != "latest" ] && [ "$metadata_version" != "$normalized_version" ]; then
    echo "Release metadata build did not match requested Codex build $normalized_version." >&2
    exit 1
  fi
  resolved_version="$metadata_version"
  min_pkg="$(printf '%s\n' "$release_metadata" | awk -F '\t' '$1 == "min_pkg" { print $2; exit }')"
  select_release_assets
}

select_release_assets() {
  asset="codex-package-$vendor_target-$resolved_version.tar.gz"
  if ! release_asset_exists "$asset"; then
    echo "Could not find $asset in the build metadata for Codex $resolved_version." >&2
    exit 1
  fi
  download_url="$BUILDS_URL/$asset"
}

installed_pkg_version() {
  # PlistBuddy prints its complaints on stdout and would create a missing file
  [ -r "$PKG_ROOT/mavergreen.plist" ] || return 0
  /usr/libexec/PlistBuddy -c 'Print :version' "$PKG_ROOT/mavergreen.plist" 2>/dev/null || true
}

# True when the installed package version ($1, maybe empty) is older than the required one ($2).
# Versions are YYYYMMDD.N (eight digits, a dot, one to four digits), compared by date and then by N,
# both numerically. An unreadable installed version is older than anything.
pkg_version_is_older() {
  have="$1"
  need="$2"
  pkg_version_format='^[0-9]{8}\.[0-9]{1,4}$'

  if ! printf '%s\n' "$need" | grep -Eq "$pkg_version_format"; then
    echo "The build asks for a package version this installer cannot read: $need." >&2
    exit 1
  fi
  if ! printf '%s\n' "$have" | grep -Eq "$pkg_version_format"; then
    return 0
  fi
  have_date="${have%%.*}"
  have_n="${have#*.}"
  need_date="${need%%.*}"
  need_n="${need#*.}"

  if [ "$have_date" -ne "$need_date" ]; then
    [ "$have_date" -lt "$need_date" ]
  else
    [ "$have_n" -lt "$need_n" ]
  fi
}

# Like upstream's prompt_yes_no, a run with no usable /dev/tty and no tty on stdin has nobody to ask.
# CODEX_INSTALL_ASSUME_TTY=1 (tests) says somebody is there.
interactive_session() {
  [ "${CODEX_INSTALL_ASSUME_TTY:-}" = "1" ] && return 0
  ( : </dev/tty ) 2>/dev/null && return 0
  [ -t 0 ]
}

# A guarded run never opens the package's updater. CODEX_NON_INTERACTIVE does not guard: upstream's
# `codex update` sets it while somebody watches, and this installer has no prompts for it to skip.
guarded_run() {
  if [ "${CODEX_INSTALL_IF_LATEST:-}" = "1" ] || [ "${CODEX_INSTALL_IF_CURRENT:-}" = "1" ] || [ "$DAEMON_ONLY" = "1" ]; then
    return 0
  fi
  if [ "${CODEX_INSTALL_NO_UPDATER:-}" = "1" ]; then
    return 0
  fi
  if interactive_session; then
    return 1
  fi
  return 0
}

require_pkg_for_release() {
  [ -n "$min_pkg" ] || return 0

  pkg_version="$(installed_pkg_version)"
  if ! pkg_version_is_older "$pkg_version" "$min_pkg"; then
    return 0
  fi

  if [ -z "$pkg_version" ]; then
    pkg_version="unknown, the package's mavergreen.plist is missing or unreadable"
  fi
  if guarded_run; then
    echo "Codex $resolved_version needs a newer codex-cli package (it requires $min_pkg; installed: $pkg_version); installing nothing. Get the newer package with its updater (/Library/Application Support/Mavergreen/codex-cli-updater.app) or from https://github.com/Mavergreen/codex-cli/releases/latest" >&2
    exit 3
  fi
  echo "Codex $resolved_version requires codex-cli package $min_pkg (installed: $pkg_version)." >&2
  echo "this update needs a newer codex-cli package; opening its updater" >&2
  sh -c "$UPDATER_OPEN" || true
  exit 3
}

release_asset_digest_or_empty() {
  asset="$1"

  digest="$(printf '%s\n' "$release_metadata" | awk -F '\t' -v asset="$asset" '
    $1 == "asset" && $2 == asset {
      print $3
      exit
    }
  ')"

  case "$digest" in
    sha256:????????????????????????????????????????????????????????????????)
      digest="${digest#sha256:}"
      case "$digest" in
        *[!0-9a-fA-F]*) return 1 ;;
      esac
      printf '%s\n' "$digest"
      ;;
    *)
      return 1
      ;;
  esac
}

release_asset_exists() {
  asset="$1"

  release_asset_digest_or_empty "$asset" >/dev/null 2>&1
}

release_asset_digest() {
  asset="$1"

  digest="$(release_asset_digest_or_empty "$asset" || true)"
  if [ -z "$digest" ]; then
    echo "Could not find SHA-256 digest for release asset $asset." >&2
    exit 1
  fi

  printf '%s\n' "$digest"
}

file_sha256() {
  path="$1"

  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
    return
  fi

  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | awk '{print $1}'
    return
  fi

  if command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$path" | sed 's/^.*= //'
    return
  fi

  echo "sha256sum, shasum, or openssl is required to verify the Codex download." >&2
  exit 1
}

verify_archive_digest() {
  archive_path="$1"
  expected_digest="$2"
  actual_digest="$(file_sha256 "$archive_path")"

  if [ "$actual_digest" != "$expected_digest" ]; then
    echo "Downloaded Codex archive checksum did not match expected digest." >&2
    echo "expected: $expected_digest" >&2
    echo "actual:   $actual_digest" >&2
    return 1
  fi
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "$1 is required to install Codex." >&2
    exit 1
  fi
}

mkdir_lock_is_stale() {
  [ -d "$LOCK_DIR" ] || return 1

  pid="$(cat "$LOCK_DIR/pid" 2>/dev/null || true)"
  started_at="$(cat "$LOCK_DIR/started_at" 2>/dev/null || true)"
  now="$(date +%s 2>/dev/null || printf '0')"

  case "$started_at" in
    ''|*[!0-9]*)
      started_at=0
      ;;
  esac

  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    return 1
  fi

  if [ "$started_at" -eq 0 ] || [ "$now" -eq 0 ]; then
    return 0
  fi

  [ $((now - started_at)) -ge "$LOCK_STALE_AFTER_SECS" ]
}

acquire_install_lock() {
  mkdir -p "$STANDALONE_ROOT"

  if [ "$os" = "darwin" ] && command -v lockf >/dev/null 2>&1; then
    : >>"$LOCK_FILE"
    exec 9<>"$LOCK_FILE"
    lockf 9
    lock_kind="lockf"
    return
  fi

  if command -v flock >/dev/null 2>&1; then
    exec 9>"$LOCK_FILE"
    flock 9
    lock_kind="flock"
    return
  fi

  while ! mkdir "$LOCK_DIR" 2>/dev/null; do
    if mkdir_lock_is_stale; then
      warn "Removing stale installer lock at $LOCK_DIR"
      rm -rf "$LOCK_DIR"
      continue
    fi
    sleep 1
  done

  printf '%s\n' "$$" >"$LOCK_DIR/pid"
  date +%s >"$LOCK_DIR/started_at" 2>/dev/null || true
  lock_kind="mkdir"
}

release_install_lock() {
  if [ "$lock_kind" = "mkdir" ]; then
    rm -rf "$LOCK_DIR" 2>/dev/null || true
  elif [ "$lock_kind" = "flock" ] || [ "$lock_kind" = "lockf" ]; then
    exec 9>&- 2>/dev/null || true
  fi
  lock_kind=""
}

cleanup_stale_install_artifacts() {
  mkdir -p "$RELEASES_DIR" "$STANDALONE_ROOT"

  find "$RELEASES_DIR" -mindepth 1 -maxdepth 1 -name '.staging.*' -exec rm -rf {} +
  find "$STANDALONE_ROOT" -mindepth 1 -maxdepth 1 -name '.current.*' -exec rm -f {} +
}

replace_path_with_symlink() {
  link_path="$1"
  link_target="$2"
  tmp_link="$3"

  rm -f "$tmp_link"
  ln -s "$link_target" "$tmp_link"

  if mv -Tf "$tmp_link" "$link_path" 2>/dev/null; then
    return
  fi

  if mv -hf "$tmp_link" "$link_path" 2>/dev/null; then
    return
  fi

  if perl -e 'rename($ARGV[0], $ARGV[1]) or exit 1' "$tmp_link" "$link_path" 2>/dev/null; then
    return
  fi

  rm -f "$link_path"
  mv -f "$tmp_link" "$link_path"
}

version_from_binary() {
  codex_path="$1"

  if [ ! -x "$codex_path" ]; then
    return 1
  fi

  "$codex_path" --version 2>/dev/null | sed -n 's/.* \([0-9][0-9A-Za-z.+-]*\)$/\1/p' | head -n 1
}

current_installed_build() {
  current_target="$(readlink "$CURRENT_LINK" 2>/dev/null || true)"
  current_name="$(basename "$current_target")"
  printf '%s\n' "${current_name%-$vendor_target}"
}

install_package_release() {
  release_dir="$1"
  archive_path="$2"
  stage_release="$RELEASES_DIR/.staging.$(basename "$release_dir").$$"

  mkdir -p "$RELEASES_DIR"
  rm -rf "$stage_release"
  mkdir -p "$stage_release"
  tar -xzf "$archive_path" -C "$stage_release"
  chmod 0755 \
    "$stage_release/bin/codex" \
    "$stage_release/bin/codex-code-mode-host" \
    "$stage_release/codex-path/rg"
  ln -sf "bin/codex" "$stage_release/codex"

  if [ -e "$release_dir" ] || [ -L "$release_dir" ]; then
    rm -rf "$release_dir"
  fi
  mv "$stage_release" "$release_dir"
}

release_dir_is_complete() {
  release_dir="$1"
  expected_version="$2"
  expected_target="$3"
  layout="$4"

  [ -d "$release_dir" ] &&
    [ "$(basename "$release_dir")" = "$expected_version-$expected_target" ] ||
    return 1

  case "$layout" in
    package)
      [ -f "$release_dir/codex-package.json" ] &&
        [ -x "$release_dir/bin/codex" ] &&
        [ -x "$release_dir/bin/codex-code-mode-host" ] &&
        [ -x "$release_dir/codex" ] &&
        [ -x "$release_dir/codex-path/rg" ] ||
        return 1
      ;;
    *)
      return 1
      ;;
  esac

  # the package's codex reports OpenAI's x.y.z, not the build ID
  installed_version="$(version_from_binary "$release_dir/bin/codex" || version_from_binary "$release_dir/codex" || true)"
  [ "$installed_version" = "${expected_version%%-mavericks.*}" ]
}

update_current_link() {
  release_dir="$1"
  tmp_link="$STANDALONE_ROOT/.current.$$"

  replace_path_with_symlink "$CURRENT_LINK" "$release_dir" "$tmp_link"
}

parse_args "$@"

require_command mktemp
require_command tar

case "$(uname -s)" in
  Darwin)
    os="darwin"
    ;;
  *)
    echo "This installer supports Mac OS X only." >&2
    exit 1
    ;;
esac
platform_label="Mac OS X (Intel)"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/codex-install.XXXXXX")"
cleanup() {
  release_install_lock
  if [ -n "$tmp_dir" ]; then
    rm -rf "$tmp_dir"
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

resolve_release
release_name="$resolved_version-$vendor_target"
release_dir="$RELEASES_DIR/$release_name"

acquire_install_lock
if [ "${CODEX_INSTALL_DEFER_SELECTION:-0}" = "1" ] &&
  { [ -e "$STANDALONE_ROOT/current" ] || [ -L "$STANDALONE_ROOT/current" ]; }; then
  echo "A dedicated daemon is already selected; retry the update." >&2
  exit 1
fi
updater_record="$CODEX_HOME_DIR/app-server-daemon/app-server-updater.pid"
if [ "$DAEMON_ONLY" = "1" ]; then
  updater_record="$CODEX_HOME_DIR/app-server-daemon/daemon-updater.pid"
fi
old_updater_parent="false"
if [ "${CODEX_INSTALL_IF_LATEST:-}" != "1" ] && [ "${CODEX_INSTALL_IF_CURRENT:-}" != "1" ] && [ -f "$updater_record" ]; then
  updater_pid="$(sed -n 's/.*"pid"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$updater_record" | head -n 1)"
  recorded_start="$(sed -n 's/.*"processStartTime"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$updater_record" | head -n 1)"
  if [ -r "/proc/$$/stat" ]; then
    parent_pid="$(sed 's/^.*) //' "/proc/$$/stat" | awk '{ print $2 }')"
  else
    parent_pid="$(ps -p "$$" -o ppid= 2>/dev/null)" || parent_pid=""
    parent_pid="$(printf '%s' "$parent_pid" | tr -d ' ')"
  fi
  if [ -n "$updater_pid" ] && [ "$updater_pid" = "$parent_pid" ]; then
    actual_details="$(ps -p "$updater_pid" -o stat= -o lstart= 2>/dev/null)" || actual_details=""
    actual_start="$(printf '%s' "$actual_details" | sed 's/^[^[:space:]]*[[:space:]]*//; s/[[:space:]]*$//')"
    if [ -n "$recorded_start" ] && [ "$recorded_start" = "$actual_start" ]; then
      old_updater_parent="true"
    fi
  fi
  if [ "$RELEASE" = "latest" ] && [ -n "$updater_pid" ] &&
    { [ -z "$parent_pid" ] || { [ "$updater_pid" = "$parent_pid" ] &&
      { [ -z "$recorded_start" ] || [ -z "$actual_start" ]; }; }; } &&
    kill -0 "$updater_pid" 2>/dev/null; then
    warn "Cannot verify whether an older updater launched this installer; skipping latest update."
    exit 0
  fi
fi
if [ "${CODEX_INSTALL_IF_LATEST:-}" = "1" ] || [ "${CODEX_INSTALL_IF_CURRENT:-}" = "1" ] || [ "$old_updater_parent" = "true" ]; then
  guarded_release="${CODEX_UPDATE_FROM_RELEASE:-}"
  if [ "$old_updater_parent" = "true" ]; then
    guarded_release="$(cat "$AUTO_UPDATE_VERSION" 2>/dev/null || true)"
  fi
  current_release_dir="$(cd -P "$CURRENT_LINK" 2>/dev/null && pwd)" || exit 0
  releases_dir="$(cd -P "$RELEASES_DIR" 2>/dev/null && pwd)" || exit 0
  if [ "$RELEASE" != "latest" ] || [ -z "$guarded_release" ] ||
    [ "$current_release_dir" != "$releases_dir/$guarded_release" ]; then
    if [ "${CODEX_INSTALL_IF_CURRENT:-}" = "1" ]; then
      echo "Daemon selection changed; retry the update." >&2
      exit 1
    fi
    exit 0
  fi
  # An explicit daemon update may leave a local or pinned release. Scheduled
  # updates still require the selected release to follow the latest channel.
  if [ "${CODEX_INSTALL_IF_CURRENT:-}" != "1" ] &&
    [ "$(cat "$AUTO_UPDATE_VERSION" 2>/dev/null || true)" != "$guarded_release" ]; then
    exit 0
  fi
fi
require_pkg_for_release
current_version="$(current_installed_build)"
if [ -n "$current_version" ] && [ "$current_version" != "$resolved_version" ]; then
  step "Updating Codex CLI from $current_version to $resolved_version"
elif [ -n "$current_version" ]; then
  step "Codex CLI $resolved_version is already installed"
else
  step "Installing Codex CLI"
fi
step "Detected platform: $platform_label"
step "Resolved version: $resolved_version"
cleanup_stale_install_artifacts

if ! release_dir_is_complete "$release_dir" "$resolved_version" "$vendor_target" "$install_layout"; then
  if [ -e "$release_dir" ] || [ -L "$release_dir" ]; then
    if [ "$DAEMON_ONLY" = "1" ]; then
      echo "Refusing to overwrite existing daemon release $release_dir." >&2
      exit 1
    fi
    warn "Found incomplete existing release at $release_dir; reinstalling."
  fi

  archive_path="$tmp_dir/$asset"

  step "Downloading Codex CLI"
  expected_digest="$(release_asset_digest "$asset")"
  if ! download_file "$download_url" "$archive_path"; then
    echo "Could not download $download_url." >&2
    exit 1
  fi
  if ! verify_archive_digest "$archive_path" "$expected_digest"; then
    exit 1
  fi

  step "Installing standalone package to $release_dir"
  install_package_release "$release_dir" "$archive_path"
fi
if ! release_dir_is_complete "$release_dir" "$resolved_version" "$vendor_target" "$install_layout"; then
  echo "Installed Codex command did not report expected version $resolved_version." >&2
  exit 1
fi
if [ "$DAEMON_ONLY" = "1" ] && [ "${CODEX_INSTALL_DEFER_SELECTION:-0}" != "1" ]; then
  installed_codex="$release_dir/codex"
  if [ "$install_layout" = "package" ]; then
    installed_codex="$release_dir/bin/codex"
  fi
  if ! "$installed_codex" app-server daemon pid-update-loop --check-package-ownership >/dev/null 2>&1; then
    echo "The production release does not support daemon-owned packages; the current selection was left unchanged." >&2
    exit 1
  fi
fi
update_current_link "$release_dir"
if [ "$RELEASE" = "latest" ]; then
  printf '%s' "$release_name" > "$AUTO_UPDATE_VERSION.tmp.$$"
  mv -f "$AUTO_UPDATE_VERSION.tmp.$$" "$AUTO_UPDATE_VERSION"
else
  rm -f "$AUTO_UPDATE_VERSION"
fi
if [ "$DAEMON_ONLY" = "1" ]; then
  release_install_lock
  exit 0
fi
release_install_lock

printf 'Codex CLI %s installed successfully.\n' "$resolved_version"
