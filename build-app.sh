#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="${SCRIPT_DIR}/.cache"
APP_DIR="${SCRIPT_DIR}/dist/Shorty.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-${CACHE_DIR}/clang}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-${CACHE_DIR}/swiftpm}"

cd "${SCRIPT_DIR}"
mkdir -p "${CLANG_MODULE_CACHE_PATH}" "${SWIFTPM_MODULECACHE_OVERRIDE}"

BUILD_FLAGS=("$@")

"${SCRIPT_DIR}/build.sh" -c release "${BUILD_FLAGS[@]}"

BIN_DIR="$(swift build -c release "${BUILD_FLAGS[@]}" --show-bin-path)"
SHORTY_BIN="${BIN_DIR}/Shorty"

if [[ ! -x "${SHORTY_BIN}" ]]; then
  echo "Expected built binary at ${SHORTY_BIN}" >&2
  exit 1
fi

mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"
cp "${SHORTY_BIN}" "${MACOS_DIR}/Shorty"
cp "${SCRIPT_DIR}/Packaging/Shorty-Info.plist" "${CONTENTS_DIR}/Info.plist"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --sign - "${APP_DIR}" >/dev/null 2>&1 || true
fi

echo "Built ${APP_DIR}"
