#!/bin/zsh

set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
PROJECT_PATH="$PROJECT_ROOT/Sceal.xcodeproj"
SCHEME="Sceal"
CONFIGURATION="Release"
APP_NAME="Sceal.app"
ARCHIVE_NAME="Sceal.xcarchive"
DIST_DIR="$PROJECT_ROOT/dist"
DEVELOPER_DIR_PATH="${DEVELOPER_DIR_PATH:-/Applications/Xcode.app/Contents/Developer}"
WORK_DIR="${WORK_DIR:-${TMPDIR:-/tmp}/sceal-distribution-$$}"
ARCHIVE_PATH="$WORK_DIR/$ARCHIVE_NAME"
EXPORT_PATH="$WORK_DIR/export"
EXPORT_OPTIONS_PATH="$WORK_DIR/ExportOptions.plist"
SIGNED_ENTITLEMENTS_PATH="$WORK_DIR/signed-entitlements.plist"
UPLOAD_ZIP_PATH="$WORK_DIR/Sceal-notary-upload.zip"
APP_OUTPUT_PATH="$DIST_DIR/$APP_NAME"

fail() {
  echo "error: $1" >&2
  exit 1
}

section() {
  echo
  echo "==> $1"
}

require_command() {
  command -v "$1" >/dev/null || fail "Expected '$1' to be available on PATH."
}

require_entitlement_true() {
  local key="$1"
  local value
  value="$(/usr/libexec/PlistBuddy -c "Print :$key" "$SIGNED_ENTITLEMENTS_PATH" 2>/dev/null || true)"

  if [[ "$value" != "true" ]]; then
    fail "Expected signed entitlement '$key' to be true."
  fi
}

if [[ -z "${SCEAL_DEVELOPMENT_TEAM:-}" ]]; then
  fail "Set SCEAL_DEVELOPMENT_TEAM to your Apple Developer Team ID."
fi

if [[ -z "${SCEAL_NOTARY_PROFILE:-}" ]]; then
  fail "Set SCEAL_NOTARY_PROFILE to the notarytool keychain profile name."
fi

if [[ ! -d "$DEVELOPER_DIR_PATH" ]]; then
  fail "Expected Xcode at $DEVELOPER_DIR_PATH."
fi

require_command security
require_command xcrun
require_command xcodebuild
require_command codesign
require_command spctl
require_command ditto

section "Checking Developer ID certificate"
IDENTITY_OUTPUT="$(security find-identity -p codesigning -v || true)"
if ! /usr/bin/grep -E "Developer ID Application: .*\\($SCEAL_DEVELOPMENT_TEAM\\)" >/dev/null <<< "$IDENTITY_OUTPUT"; then
  echo "$IDENTITY_OUTPUT"
  fail "No valid Developer ID Application identity was found for team '$SCEAL_DEVELOPMENT_TEAM'."
fi

section "Checking notarytool profile"
if ! xcrun notarytool history --keychain-profile "$SCEAL_NOTARY_PROFILE" >/dev/null; then
  fail "Could not use notarytool profile '$SCEAL_NOTARY_PROFILE'. Create it with xcrun notarytool store-credentials."
fi

rm -rf "$DIST_DIR" "$WORK_DIR"
mkdir -p "$DIST_DIR" "$WORK_DIR" "$EXPORT_PATH"

section "Archiving $APP_NAME"
DEVELOPER_DIR="$DEVELOPER_DIR_PATH" \
  xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  DEVELOPMENT_TEAM="$SCEAL_DEVELOPMENT_TEAM" \
  CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  archive

cat > "$EXPORT_OPTIONS_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>developer-id</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>signingCertificate</key>
  <string>Developer ID Application</string>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>teamID</key>
  <string>$SCEAL_DEVELOPMENT_TEAM</string>
</dict>
</plist>
PLIST

section "Exporting Developer ID app"
DEVELOPER_DIR="$DEVELOPER_DIR_PATH" \
  xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PATH"

if [[ ! -d "$EXPORT_PATH/$APP_NAME" ]]; then
  fail "Export completed, but $EXPORT_PATH/$APP_NAME was not created."
fi

ditto "$EXPORT_PATH/$APP_NAME" "$APP_OUTPUT_PATH"

section "Verifying signing and entitlements"
codesign --verify --strict --verbose=4 "$APP_OUTPUT_PATH"
codesign -d --entitlements :- "$APP_OUTPUT_PATH" > "$SIGNED_ENTITLEMENTS_PATH" 2>/dev/null

SIGNING_DETAILS="$(codesign -dvvv "$APP_OUTPUT_PATH" 2>&1)"
if [[ "$SIGNING_DETAILS" != *"Authority=Developer ID Application:"* ]]; then
  echo "$SIGNING_DETAILS"
  fail "Expected the app to be signed with a Developer ID Application certificate."
fi

if [[ "$SIGNING_DETAILS" != *"TeamIdentifier=$SCEAL_DEVELOPMENT_TEAM"* ]]; then
  echo "$SIGNING_DETAILS"
  fail "Expected TeamIdentifier to be '$SCEAL_DEVELOPMENT_TEAM'."
fi

if [[ "$SIGNING_DETAILS" != *"runtime"* && "$SIGNING_DETAILS" != *"Runtime Version"* ]]; then
  echo "$SIGNING_DETAILS"
  fail "Expected Hardened Runtime to be enabled."
fi

require_entitlement_true "com.apple.security.app-sandbox"
require_entitlement_true "com.apple.security.files.user-selected.read-write"
require_entitlement_true "com.apple.security.files.bookmarks.app-scope"

if /usr/libexec/PlistBuddy -c "Print :com.apple.security.get-task-allow" "$SIGNED_ENTITLEMENTS_PATH" >/dev/null 2>&1; then
  fail "Distribution entitlements must not include com.apple.security.get-task-allow."
fi

section "Submitting for notarization"
ditto -c -k --sequesterRsrc --keepParent "$APP_OUTPUT_PATH" "$UPLOAD_ZIP_PATH"
xcrun notarytool submit "$UPLOAD_ZIP_PATH" \
  --keychain-profile "$SCEAL_NOTARY_PROFILE" \
  --wait

section "Stapling notarization ticket"
xcrun stapler staple "$APP_OUTPUT_PATH"
xcrun stapler validate "$APP_OUTPUT_PATH"

section "Running Gatekeeper assessment"
spctl -a -vv --type execute "$APP_OUTPUT_PATH"

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_OUTPUT_PATH/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_OUTPUT_PATH/Contents/Info.plist")"
FINAL_ZIP_PATH="$DIST_DIR/Sceal-$VERSION-$BUILD-macOS.zip"
DSYM_SOURCE_PATH="$ARCHIVE_PATH/dSYMs/Sceal.app.dSYM"
DSYM_OUTPUT_PATH="$DIST_DIR/Sceal-$VERSION-$BUILD.app.dSYM"

section "Creating final zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_OUTPUT_PATH" "$FINAL_ZIP_PATH"

if [[ -d "$DSYM_SOURCE_PATH" ]]; then
  ditto "$DSYM_SOURCE_PATH" "$DSYM_OUTPUT_PATH"
fi

echo
echo "Distribution app: $APP_OUTPUT_PATH"
echo "Distribution zip: $FINAL_ZIP_PATH"
if [[ -d "$DSYM_OUTPUT_PATH" ]]; then
  echo "dSYM: $DSYM_OUTPUT_PATH"
fi
