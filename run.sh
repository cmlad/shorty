#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_BIN="${SCRIPT_DIR}/.build/arm64-apple-macosx/debug/Shorty"

if [[ ! -x "${BUILD_BIN}" ]]; then
  (cd "${SCRIPT_DIR}" && swift build)
fi

exec "${BUILD_BIN}" --config "${SCRIPT_DIR}/config.json"
