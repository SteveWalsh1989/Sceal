#!/bin/zsh

set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"

if ! command -v periphery >/dev/null 2>&1; then
  print -u2 "error: periphery is not installed. Install it with: brew install periphery"
  exit 127
fi

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

cd "$PROJECT_ROOT"
periphery scan \
  --project Sceal.xcodeproj \
  --schemes Sceal \
  --format xcode \
  --relative-results \
  --strict \
  --retain-objc-accessible \
  --retain-codable-properties \
  --retain-swift-ui-previews \
  --retain-assign-only-properties \
  --disable-update-check \
  --skip-schemes-validation \
  -- -destination 'platform=macOS'
