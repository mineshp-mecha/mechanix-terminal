cmake_minimum_required(VERSION 3.15)
# stop cmake from taking make from CMAKE_SYSROOT
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
project(runner LANGUAGES CXX)

set(BINARY_NAME "mechanix_terminal")

cmake_policy(SET CMP0063 NEW)

set(CMAKE_INSTALL_RPATH "$ORIGIN/lib")

# Basically we use this include when we got the following error:
#  fatal error: 'bits/c++config.h' file not found
include_directories(SYSTEM ${FLUTTER_SYSTEM_INCLUDE_DIRECTORIES})
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)

# Configure build options.
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE "Debug" CACHE
    STRING "Flutter build mode" FORCE)
  set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
    "Debug" "Profile" "Release")
endif()

# Configure build option to target backend.
if (NOT FLUTTER_TARGET_BACKEND_TYPE)
  set(FLUTTER_TARGET_BACKEND_TYPE "wayland" CACHE
    STRING "Flutter target backend type" FORCE)
  set_property(CACHE FLUTTER_TARGET_BACKEND_TYPE PROPERTY STRINGS
    "wayland" "gbm" "eglstream" "x11")
endif()

# Compilation settings that should be applied to most targets.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE -Wall -Werror)
  target_compile_options(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:-O3>")
  target_compile_definitions(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:NDEBUG>")
endfunction()

set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")

# Flutter library and tool build rules.
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build
add_subdirectory("runner")

# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)

# === Installation ===
# By default, "installing" just makes a relocatable bundle in the build
# directory.
set(BUILD_BUNDLE_DIR "${PROJECT_BINARY_DIR}/bundle")
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

# Start with a clean build bundle directory every time.
install(CODE "
  file(REMOVE_RECURSE \"${BUILD_BUNDLE_DIR}/\")
  " COMPONENT Runtime)

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}/lib")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}"
  DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)
install(FILES "${FLUTTER_EMBEDDER_LIBRARY}"
  DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
if(NOT CMAKE_BUILD_TYPE MATCHES "Debug")
  install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# Install the Rust library for eLinux
set(RUST_LIB_NAME "librust_lib_mechanix_terminal.so")

# --- ObjectBox Library Setup ---
set(OBX_VERSION "5.3.2")
if(CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64|arm64")
    set(OBX_ARCH "aarch64")
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64|AMD64")
    set(OBX_ARCH "x64")
else()
    message(FATAL_ERROR "Unsupported architecture for ObjectBox: ${CMAKE_SYSTEM_PROCESSOR}")
endif()

set(OBX_NAME "objectbox-linux-${OBX_ARCH}")
set(OBX_TARBALL "${OBX_NAME}.tar.gz")
set(OBX_URL "https://github.com/objectbox/objectbox-c/releases/download/v${OBX_VERSION}/${OBX_TARBALL}")

# Version-scoped cache dir so a version bump always triggers a fresh download
set(OBX_LIB_DIR "${CMAKE_CURRENT_BINARY_DIR}/objectbox-${OBX_VERSION}-${OBX_ARCH}")
set(OBX_SO_FILE "${OBX_LIB_DIR}/lib/libobjectbox.so")

if(NOT EXISTS "${OBX_SO_FILE}")
    message(STATUS "Downloading ObjectBox ${OBX_VERSION} for ${OBX_ARCH}...")

    set(OBX_TARBALL_PATH "${CMAKE_CURRENT_BINARY_DIR}/${OBX_TARBALL}")

    file(DOWNLOAD "${OBX_URL}" "${OBX_TARBALL_PATH}"
        SHOW_PROGRESS
        STATUS OBX_DL_STATUS
        TLS_VERIFY ON
        TIMEOUT 120
    )

    list(GET OBX_DL_STATUS 0 OBX_DL_ERR)
    list(GET OBX_DL_STATUS 1 OBX_DL_MSG)
    if(OBX_DL_ERR)
        file(REMOVE "${OBX_TARBALL_PATH}")
        message(FATAL_ERROR "Failed to download ObjectBox from ${OBX_URL}: ${OBX_DL_MSG}")
    endif()

    file(MAKE_DIRECTORY "${OBX_LIB_DIR}")
    execute_process(
        COMMAND ${CMAKE_COMMAND} -E tar xzf "${OBX_TARBALL_PATH}"
        WORKING_DIRECTORY "${OBX_LIB_DIR}"
        RESULT_VARIABLE OBX_TAR_ERR
    )
    if(OBX_TAR_ERR)
        message(FATAL_ERROR "Failed to extract ObjectBox tarball")
    endif()

    file(REMOVE "${OBX_TARBALL_PATH}")

    if(NOT EXISTS "${OBX_SO_FILE}")
        message(FATAL_ERROR "ObjectBox archive extracted but ${OBX_SO_FILE} was not found")
    endif()
endif()

# Expose as a proper imported target instead of a raw path
add_library(objectbox SHARED IMPORTED GLOBAL)
set_target_properties(objectbox PROPERTIES
    IMPORTED_LOCATION "${OBX_SO_FILE}"
    INTERFACE_INCLUDE_DIRECTORIES "${OBX_LIB_DIR}/include"
)
# Check if we are cross-compiling for ARM64
if(CMAKE_SYSTEM_PROCESSOR STREQUAL "aarch64" OR CMAKE_LIBRARY_ARCHITECTURE STREQUAL "aarch64-linux-gnu")
    set(RUST_TARGET "aarch64-unknown-linux-gnu")
else()
    set(RUST_TARGET ".") # Default/Host
endif()

if(CMAKE_BUILD_TYPE MATCHES "Release")
    set(RUST_LIB_SOURCE "${CMAKE_CURRENT_SOURCE_DIR}/../rust/target/${RUST_TARGET}/release/${RUST_LIB_NAME}")
else()
    set(RUST_LIB_SOURCE "${CMAKE_CURRENT_SOURCE_DIR}/../rust/target/${RUST_TARGET}/debug/${RUST_LIB_NAME}")
endif()

install(FILES "${RUST_LIB_SOURCE}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}" COMPONENT Runtime)

# Add ObjectBox library installation
install(FILES "${OBX_SO_FILE}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}" COMPONENT Runtime)
