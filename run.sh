#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_BIN="${SCRIPT_DIR}/.build/arm64-apple-macosx/debug/Shorty"

if [[ ! -x "${BUILD_BIN}" ]]; then
  "${SCRIPT_DIR}/build.sh"
fi

exec "${BUILD_BIN}" 
