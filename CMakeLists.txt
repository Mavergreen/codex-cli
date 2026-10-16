cmake_minimum_required(VERSION 3.25)
project(CodexMavericks LANGUAGES NONE)

find_package(MavericksShipyard REQUIRED)
include(MavericksMode)
include(MavericksCompatGuard)

mavericks_resolve_version(MAVERICKS_CODEX_VERSION)
execute_process(
  COMMAND sh "${CMAKE_SOURCE_DIR}/build/resolve-build-root.sh"
  OUTPUT_VARIABLE _build_root OUTPUT_STRIP_TRAILING_WHITESPACE
  RESULT_VARIABLE _build_root_result)
if(NOT _build_root_result EQUAL 0)
  message(FATAL_ERROR "Could not resolve the host-local Mavericks build root")
endif()

# spec: build/check-build-manifests.sh --cross-only -- CI has no native build to compare with, so it checks
#       the cross manifest against the pins alone. Comparing both is an out-of-band check (INGREDIENTS.md
#       "Releasing"), run with the native artifact transferred from ultimate-hat
option(CODEX_CROSS_ONLY_MANIFEST "Check only the cross build manifest (CI has no native one)" OFF)
set(_manifest_args)
if(CODEX_CROSS_ONLY_MANIFEST)
  set(_manifest_args --cross-only)
endif()

if(MAVERICKS_MODE STREQUAL "cross")
  execute_process(
    COMMAND sh "${CMAKE_SOURCE_DIR}/build/check-build-manifests.sh" ${_manifest_args}
    RESULT_VARIABLE _manifest_result)
  if(NOT _manifest_result EQUAL 0)
    message(FATAL_ERROR "Native and cross Codex build manifests do not match")
  endif()
  set(_codex_mode cross)
else()
  set(_codex_mode native)
endif()

foreach(_codex_name codex codex-code-mode-host)
  set(_codex_path "${_build_root}/codex-${_codex_mode}/${_codex_name}")
  if(NOT EXISTS "${_codex_path}")
    message(FATAL_ERROR "Run sh build/build-codex.sh ${_codex_mode} first; missing ${_codex_path}")
  endif()
  add_executable(${_codex_name} IMPORTED GLOBAL)
  set_target_properties(${_codex_name} PROPERTIES IMPORTED_LOCATION "${_codex_path}")
endforeach()

enable_testing()

# platform: shipyard's mavericks_assert_binary_compatible() attaches POST_BUILD to a compiled target,
#           which CMake forbids on an imported executable. Run the same shipyard guard as a CTest
#           test against each exact imported Codex artifact, as mavergreen-gh does (compat_guard_gh).
#           It runs once, under `shipyard-ctest`, not also at build time.
foreach(_codex_name codex codex-code-mode-host)
  add_test(NAME compat_guard_${_codex_name}
    COMMAND "${CMAKE_COMMAND}" -E env
      "MAVERICKS_DEVIATIONS_ROOT=${CMAKE_SOURCE_DIR}"
      "MAVERICKS_ALLOW_ARCHS=x86_64"
      sh "${MavericksShipyard_SCRIPTS}/assert_binary_compatible.sh" "$<TARGET_FILE:${_codex_name}>")
  # Interim, until shipyard's guard checks load paths: it passed a codex that loaded /opt/pkg dylibs.
  add_test(NAME load_paths_${_codex_name}
    COMMAND sh "${CMAKE_SOURCE_DIR}/build/check-load-paths.sh" "$<TARGET_FILE:${_codex_name}>")
endforeach()


option(CODEX_BUILD_UPDATER "Build the Sparkle updater (needs codex-cli in the installed shipyard's product registry)" OFF)

if(CODEX_BUILD_UPDATER)
  # The updater is the only compiled code here; the Codex binaries are imported.
  enable_language(OBJC)
  include(MavericksSparkle)
  # spec: updater/ICON-CREDIT.txt -- the generic icon on purpose, with its reason and its exit
  mavericks_add_updater_app(
    PRODUCT codex-cli
    PRODUCT_NAME "Mavericks Codex CLI"
    ALLOW_GENERIC
    VERSION "${MAVERICKS_CODEX_VERSION}"
    CONFIRM_TITLE "Codex CLI for Mavericks updated"
    CONFIRM_BODY "codex was updated. New shells and agents get the new version.")
endif()
