#!/bin/zsh

set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
CONFIG_PATH="$PROJECT_ROOT/.swift-format"
SWIFT_PATHS=(
  "$PROJECT_ROOT/App"
  "$PROJECT_ROOT/Features"
  "$PROJECT_ROOT/Shared"
  "$PROJECT_ROOT/ScealTests"
)

xcrun swift-format lint \
  --strict \
  --recursive \
  --parallel \
  --configuration "$CONFIG_PATH" \
  "${SWIFT_PATHS[@]}"
