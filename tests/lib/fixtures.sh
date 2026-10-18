#!/bin/sh
# platform: macOS-only -- builds channel tarballs with packaging/build-codex-package.sh (bsdtar) and hashes with shasum
#   usage: . "$(dirname "$0")/lib/fixtures.sh" after h_setup
#          h_url PATH               the file:// URL of PATH, percent-encoded (the harness's temp dir has a space)
#          h_channel ID [MIN_PKG]   adds build ID to the file:// channel in $H/channel (tarball built from fake
#                                   binaries, its JSON, a .sig from h_resign) and points latest.json at it;
#                                   sets CODEX_BUILDS_URL to the channel
#          h_resign FILE            writes FILE.sig for FILE's current bytes
#          h_fake_verify            a CODEX_ED25519_VERIFY that exits 0 only when the signature argument is the sha256 of the file argument (h_resign writes such .sig files)
#          h_fake_pkg VERSION       a CODEX_PKG_ROOT whose mavergreen.plist says version VERSION, with a public key
#          h_fake_open              a CODEX_PKG_UPDATER_OPEN that records each call in $H/open-calls

h_url() {
  printf 'file://%s' "$(printf %s "$1" | sed "s/%/%25/g; s/ /%20/g; s/#/%23/g; s/?/%3F/g")"
}

h_channel() {
  _c_id="$1"
  _c_min="${2-}"
  _c_dir="$H/channel"
  _c_asset="codex-package-x86_64-apple-darwin-$_c_id.tar.gz"
  _c_art="$H/artifact-$_c_id"
  mkdir -p "$_c_dir" "$_c_art"
  # --version reports OpenAI's x.y.z like the real binary; with no arguments it names the build
  printf '#!/bin/sh\nif [ "${1-}" = --version ]; then echo "codex-cli %s"; else echo "fake codex %s"; fi\n' "${_c_id%%-*}" "$_c_id" > "$_c_art/codex"
  printf '#!/bin/sh\necho fake host\n' > "$_c_art/codex-code-mode-host"
  chmod 0755 "$_c_art/codex" "$_c_art/codex-code-mode-host"
  printf 'license\n' > "$_c_art/LICENSE"
  printf 'notice\n' > "$_c_art/NOTICE"
  printf 'manifest\n' > "$_c_art/build-manifest"
  _c_tb="$(sh "$H_REPO/packaging/build-codex-package.sh" "$_c_art" "$_c_id" "$H/channel-build-$_c_id")"
  cp "$_c_tb" "$_c_dir/$_c_asset"
  _c_sha="$(shasum -a 256 "$_c_dir/$_c_asset" | awk '{print $1}')"
  printf '{"tag_name":"rust-v%s","mavergreen_build":"%s","mavergreen_codex_version":"%s","mavergreen_min_pkg":"%s","mavergreen_state":"%s","assets":[{"name":"%s","digest":"sha256:%s"}]}' \
    "$_c_id" "$_c_id" "${_c_id%%-*}" "$_c_min" "0000000000000000000000000000000000000000000000000000000000000000" "$_c_asset" "$_c_sha" \
    > "$_c_dir/codex-build-$_c_id.json"
  h_resign "$_c_dir/codex-build-$_c_id.json"
  cp "$_c_dir/codex-build-$_c_id.json" "$_c_dir/latest.json"
  cp "$_c_dir/codex-build-$_c_id.json.sig" "$_c_dir/latest.json.sig"
  CODEX_BUILDS_URL="$(h_url "$_c_dir")"
  export CODEX_BUILDS_URL
}

# the fake signature of FILE is the sha256 of FILE's bytes, written to FILE.sig
h_resign() {
  shasum -a 256 "$1" | awk '{print $1}' > "$1.sig"
}

h_fake_verify() {
  cat > "$H/bin/fake-verify" <<'VERIFY'
#!/bin/sh
# ed25519-verify -p PUBKEY FILE SIGNATURE
[ "$1" = -p ] && [ $# -eq 4 ] || exit 2
printf '%s|%s\n' "$2" "$4" >> "$H/verify-calls"
[ "$4" = "$(shasum -a 256 "$3" | awk '{print $1}')" ]
VERIFY
  chmod +x "$H/bin/fake-verify"
  CODEX_ED25519_VERIFY="$H/bin/fake-verify"
  export CODEX_ED25519_VERIFY
}

h_fake_pkg() {
  CODEX_PKG_ROOT="$H/pkg root"
  mkdir -p "$CODEX_PKG_ROOT/share/codex-cli"
  printf 'fake-public-key\n' > "$CODEX_PKG_ROOT/share/codex-cli/ed25519_key.pub"
  cat > "$CODEX_PKG_ROOT/mavergreen.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>version</key>
	<string>$1</string>
</dict>
</plist>
PLIST
  export CODEX_PKG_ROOT
}

h_fake_open() {
  cat > "$H/bin/fake open" <<'OPEN'
#!/bin/sh
echo "$*" >> "$H/open-calls"
OPEN
  chmod +x "$H/bin/fake open"
  CODEX_PKG_UPDATER_OPEN="'$H/bin/fake open' --args --user"
  export CODEX_PKG_UPDATER_OPEN
}
