#!/bin/zsh

set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
CONFIG_PATH="$PROJECT_ROOT/.swiftlint.yml"
CACHE_PATH="$PROJECT_ROOT/.build/swiftlint-cache"

if ! command -v swiftlint >/dev/null 2>&1; then
  print -u2 "error: swiftlint is not installed. Install it with: brew install swiftlint"
  exit 127
fi

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

cd "$PROJECT_ROOT"
swiftlint lint --strict --config "$CONFIG_PATH" --cache-path "$CACHE_PATH"
