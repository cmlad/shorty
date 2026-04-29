#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="${SCRIPT_DIR}/.cache"

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-${CACHE_DIR}/clang}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-${CACHE_DIR}/swiftpm}"

cd "${SCRIPT_DIR}"
mkdir -p "${CLANG_MODULE_CACHE_PATH}" "${SWIFTPM_MODULECACHE_OVERRIDE}"

if swift build "$@"; then
  exit 0
fi

echo "Initial build failed; cleaning SwiftPM build artifacts and retrying..." >&2
swift package clean
rm -rf "${SCRIPT_DIR}/.cache/swiftpm" "${SCRIPT_DIR}/.cache/clang"
mkdir -p "${CLANG_MODULE_CACHE_PATH}" "${SWIFTPM_MODULECACHE_OVERRIDE}"
exec swift build "$@"
