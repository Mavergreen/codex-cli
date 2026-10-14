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

if(MAVERICKS_MODE STREQUAL "cross")
  execute_process(
    COMMAND sh "${CMAKE_SOURCE_DIR}/build/check-build-manifests.sh"
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

# The shipyard helper attaches POST_BUILD to compiled targets; CMake forbids that on an imported
# executable. Run the same shipyard guard directly against each exact imported Codex artifact.
add_custom_target(codex_compat ALL
  COMMAND "${CMAKE_COMMAND}" -E env
    "MAVERICKS_DEVIATIONS_ROOT=${CMAKE_SOURCE_DIR}"
    "MAVERICKS_ALLOW_ARCHS=x86_64"
    sh "${MavericksShipyard_SCRIPTS}/assert_binary_compatible.sh" "$<TARGET_FILE:codex>"
  COMMAND "${CMAKE_COMMAND}" -E env
    "MAVERICKS_DEVIATIONS_ROOT=${CMAKE_SOURCE_DIR}"
    "MAVERICKS_ALLOW_ARCHS=x86_64"
    sh "${MavericksShipyard_SCRIPTS}/assert_binary_compatible.sh" "$<TARGET_FILE:codex-code-mode-host>"
  # Interim, until shipyard's guard checks load paths: it passed a codex that loaded /opt/pkg dylibs.
  COMMAND sh "${CMAKE_SOURCE_DIR}/build/check-load-paths.sh"
    "$<TARGET_FILE:codex>" "$<TARGET_FILE:codex-code-mode-host>"
  VERBATIM
  COMMENT "Checking the imported Codex executables for Mavericks compatibility")
