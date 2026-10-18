cmake_minimum_required(VERSION 3.25)
# The pkg is its own upstream: VERSION (YYYYMMDD.N) if present, else UPSTREAM_VERSION
file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/UPSTREAM_VERSION" MAVERICKS_CODEX_VERSION LIMIT_COUNT 1)
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/VERSION")
  file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/VERSION" MAVERICKS_CODEX_VERSION LIMIT_COUNT 1)
endif()

project(CodexMavericks LANGUAGES NONE)

find_package(MavericksShipyard REQUIRED)
include(MavericksMode)
include(MavericksCompatGuard)

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
  set(_codex_mode cross)
else()
  set(_codex_mode native)
endif()

enable_testing()

# The pkg carries no Codex binary, so configuring for it needs none built. The builds stream does
# build them; when they are here, import them and run the guards against the exact artifacts.
if(EXISTS "${_build_root}/codex-${_codex_mode}/codex" AND EXISTS "${_build_root}/codex-${_codex_mode}/codex-code-mode-host")
  if(_codex_mode STREQUAL "cross")
    execute_process(
      COMMAND sh "${CMAKE_SOURCE_DIR}/build/check-build-manifests.sh" ${_manifest_args}
      RESULT_VARIABLE _manifest_result)
    if(NOT _manifest_result EQUAL 0)
      message(FATAL_ERROR "Native and cross Codex build manifests do not match")
    endif()
  endif()

  foreach(_codex_name codex codex-code-mode-host)
    add_executable(${_codex_name} IMPORTED GLOBAL)
    set_target_properties(${_codex_name} PROPERTIES
      IMPORTED_LOCATION "${_build_root}/codex-${_codex_mode}/${_codex_name}")
  endforeach()

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
else()
  message(STATUS "No Codex build under ${_build_root}/codex-${_codex_mode}: its compat-guard and load-path tests are not registered")
endif()

option(CODEX_BUILD_UPDATER "Build the Sparkle updater (needs codex-cli in the installed shipyard's product registry)" OFF)

if(CODEX_BUILD_UPDATER)
  # The updater is the only compiled code here; the Codex binaries, when present, are imported.
  enable_language(OBJC)
  include(MavericksSparkle)
  # spec: updater/ICON-CREDIT.txt -- the generic icon on purpose, with its reason and its exit
  mavericks_add_updater_app(
    PRODUCT codex-cli
    PRODUCT_NAME "Mavericks Codex CLI"
    ALLOW_GENERIC
    VERSION "${MAVERICKS_CODEX_VERSION}"
    CONFIRM_TITLE "Codex CLI for Mavericks updated"
    CONFIRM_BODY "The next codex you start uses the new launcher.")
endif()
