#!/bin/sh
# platform: host-agnostic -- plain sh
#   usage: . "$PRODUCT_ROOT/tests/lib/feature-table.sh"
#          feature_table FILE FILLERS [ENTRY...]
#              writes FILE in the shape of Codex's codex-rs/features/src/lib.rs: a FeatureSpec struct
#              definition, then a FEATURES list holding each ENTRY followed by FILLERS entries
#              filler_1, filler_2, ... (UnderDevelopment, off). An ENTRY is "key Stage on|off",
#              written multi-line; Experimental is written with its multi-line body.
#          feature_entry KEY STAGE on|off   prints one multi-line FeatureSpec entry

feature_entry() {
  case "$3" in on) _fe_default=true ;; *) _fe_default=false ;; esac
  printf '    FeatureSpec {\n        id: Feature::X,\n        key: "%s",\n' "$1"
  case "$2" in
    Experimental)
      printf '        stage: Stage::Experimental {\n            name: "N",\n'
      printf '            menu_description: "d",\n            announcement: "",\n        },\n' ;;
    *) printf '        stage: Stage::%s,\n' "$2" ;;
  esac
  printf '        default_enabled: %s,\n    },\n' "$_fe_default"
}

feature_table() {
  _ft_file=$1 _ft_fillers=$2
  shift 2
  {
    printf 'pub struct FeatureSpec {\n    pub id: Feature,\n    pub key: &'"'"'static str,\n}\n\n'
    printf 'pub const FEATURES: &[FeatureSpec] = &[\n'
    for _ft_entry in "$@"; do
      # shellcheck disable=SC2086
      feature_entry $_ft_entry
    done
    _ft_n=1
    while [ "$_ft_n" -le "$_ft_fillers" ]; do
      feature_entry "filler_$_ft_n" UnderDevelopment off
      _ft_n=$((_ft_n + 1))
    done
    printf '];\n'
  } > "$_ft_file"
}
