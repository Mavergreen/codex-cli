#!/bin/sh
# platform: macOS-only -- compiles with /usr/bin/clang against the pinned 10.9 SDK and archives with libtool
#   usage: . "$PRODUCT_ROOT/tests/lib/objc-provider-fixture.sh"
#          objc_fixture_prefix DIR SDK   a provider prefix at DIR shaped as Recaulk's build/build-objc.sh
#                                        stages one: lib/librecaulk-objc.a (C stand-ins for the activation
#                                        root and the implementation it reaches) and
#                                        share/recaulk/objc-providers.json declaring
#                                        recaulk.nsworkspace.open-urls.v1 over that archive's exact bytes.
#                                        It passes shipyard's declaration check. Scratch files go to DIR.objects.
#          objc_fixture_mutate DIR SED   the declaration of DIR rewritten by the sed expression SED
# spec: build/fetch-recaulk-objc.sh header -- the provider Codex needs, by id, class, kind, selector, ABI and root.

objc_fixture_sha() { shasum -a 256 "$1" | cut -c1-64; }

objc_fixture_prefix() {
  _p=$1 _sdk=$2
  mkdir -p "$_p/lib" "$_p/share/recaulk" "$_p.objects"
  printf '%s\n' 'void __recaulk_objc_workspace_open_urls(void) {}' \
    'void *__recaulk_objc_activate(void) { return (void *)__recaulk_objc_workspace_open_urls; }' > "$_p.objects/provider.c"
  env -i PATH=/usr/bin:/bin /usr/bin/clang -arch x86_64 -isysroot "$_sdk" -mmacosx-version-min=10.9 \
    -c "$_p.objects/provider.c" -o "$_p.objects/provider.o" || return 1
  /usr/bin/libtool -static -o "$_p/lib/librecaulk-objc.a" "$_p.objects/provider.o" 2>/dev/null || return 1
  printf '%s  src/objc/provider.c\n' "$(objc_fixture_sha "$_p.objects/provider.c")" > "$_p.objects/receipt"
  # platform: each value is computed before the here-document: 10.9's bash 3.2 misparses a quoted
  #           command substitution inside one.
  _archive_sha=$(objc_fixture_sha "$_p/lib/librecaulk-objc.a")
  _sdk_sha=$(objc_fixture_sha "$_sdk/SDKSettings.plist")
  _compiler=$(/usr/bin/clang --version 2>&1 | head -1)
  _receipt=$(sed 's/$/\\n/' "$_p.objects/receipt" | tr -d '\n')
  _receipt_sha=$(objc_fixture_sha "$_p.objects/receipt")
  cat > "$_p/share/recaulk/objc-providers.json" <<EOF
{
  "schema" : 1,
  "providers" : [
    {
      "provider_id" : "recaulk.nsworkspace.open-urls.v1",
      "class" : "NSWorkspace",
      "method_kind" : "-",
      "selector" : "openURLs:withApplicationAtURL:options:configuration:error:",
      "encoding" : "@56@0:8@16@24Q32@40^@48",
      "implementation_symbol" : "__recaulk_objc_workspace_open_urls",
      "activation_root" : "__recaulk_objc_activate",
      "required_frameworks" : [
        "AppKit",
        "Carbon"
      ],
      "framework_policy" : "strong-linked-before-root"
    }
  ],
  "build" : {
    "archive_path" : "lib/librecaulk-objc.a",
    "archive_sha256" : "$_archive_sha",
    "architecture" : "x86_64",
    "artifact_role" : "shipping",
    "minimum_macos" : "10.9",
    "sdk_settings_sha256" : "$_sdk_sha",
    "compiler_identity" : "$_compiler",
    "source_inputs_receipt" : "$_receipt",
    "source_inputs_sha256" : "$_receipt_sha"
  }
}
EOF
}

objc_fixture_mutate() {
  sed "$2" "$1/share/recaulk/objc-providers.json" > "$1/decl.new" &&
    mv "$1/decl.new" "$1/share/recaulk/objc-providers.json"
}
