#!/bin/zsh

set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
PROJECT_PATH="$PROJECT_ROOT/Sceal.xcodeproj"
SCHEME="Sceal"
CONFIGURATION="Release"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/sceal-derived-release}"
BUILD_DIR="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION"
APP_NAME="Sceal.app"
APP_SOURCE_PATH="$BUILD_DIR/$APP_NAME"
DIST_DIR="$PROJECT_ROOT/dist"
APP_OUTPUT_PATH="$DIST_DIR/$APP_NAME"
ZIP_OUTPUT_PATH="$DIST_DIR/Sceal-mac.zip"
DEVELOPER_DIR_PATH="${DEVELOPER_DIR_PATH:-/Applications/Xcode.app/Contents/Developer}"

if [[ ! -d "$DEVELOPER_DIR_PATH" ]]; then
  echo "Expected Xcode at $DEVELOPER_DIR_PATH"
  exit 1
fi

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

echo "Building $APP_NAME..."
DEVELOPER_DIR="$DEVELOPER_DIR_PATH" \
  xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

if [[ ! -d "$APP_SOURCE_PATH" ]]; then
  echo "Build finished, but $APP_SOURCE_PATH was not created."
  exit 1
fi

cp -R "$APP_SOURCE_PATH" "$APP_OUTPUT_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_OUTPUT_PATH" "$ZIP_OUTPUT_PATH"

echo
echo "App bundle: $APP_OUTPUT_PATH"
echo "Zip archive: $ZIP_OUTPUT_PATH"
echo "Drag $APP_OUTPUT_PATH into /Applications to install locally."
