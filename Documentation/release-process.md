# Release Process

Scéal has two build paths:

- `scripts/build-mac-app.sh` creates a local Release build zip for development testing.
- `scripts/build-distribution-zip.sh` creates a Developer ID signed, notarized direct-download zip.

The distribution script is for website/direct-download beta releases. It is not an App Store submission flow.

## Required Apple Setup

Before running the distribution script, the local Mac needs:

- Apple Developer Program membership.
- A valid Developer ID Application certificate installed in Keychain Access.
- A saved `notarytool` keychain profile.

Check available signing identities:

```bash
security find-identity -p codesigning -v
```

The output should include a `Developer ID Application` identity for the Apple Developer Team ID used for Scéal.

## Notary Profile

Create a notary profile with `xcrun notarytool store-credentials`. Use a profile name that can be referenced from `SCEAL_NOTARY_PROFILE`.

```bash
xcrun notarytool store-credentials "sceal-direct" \
  --apple-id "you@example.com" \
  --team-id "YOURTEAMID"
```

Use an app-specific password if prompted. Do not commit Apple IDs, passwords, API keys, or notary credentials to the repository.

## Local Build

Use the existing local build script for development builds:

```bash
scripts/build-mac-app.sh
```

This produces:

- `dist/Sceal.app`
- `dist/Sceal-mac.zip`

This output is for local testing. It is not the public download artifact.

## Distribution Build

Set the required environment variables:

```bash
export SCEAL_DEVELOPMENT_TEAM="YOURTEAMID"
export SCEAL_NOTARY_PROFILE="sceal-direct"
```

Then run:

```bash
scripts/build-distribution-zip.sh
```

The script:

- Archives Scéal in Release configuration.
- Exports a Developer ID signed app.
- Verifies signing, Hardened Runtime, sandbox entitlements, and absence of `get-task-allow`.
- Submits a temporary zip to Apple notarization.
- Staples and validates the notarization ticket.
- Runs Gatekeeper assessment with `spctl`.
- Writes the final download zip to `dist/Sceal-<version>-<build>-macOS.zip`.
- Preserves the release dSYM in `dist/`.

## Expected Verification

Signing inspection should show:

- `Authority=Developer ID Application: ...`
- `TeamIdentifier=YOURTEAMID`
- Hardened Runtime enabled.
- `com.apple.security.app-sandbox = true`
- `com.apple.security.files.user-selected.read-write = true`
- `com.apple.security.files.bookmarks.app-scope = true`
- No `com.apple.security.get-task-allow` entitlement.

Gatekeeper should accept the stapled app:

```bash
spctl -a -vv --type execute dist/Sceal.app
```

## Deferred Work

This direct-download process intentionally does not include:

- Sparkle auto-updates.
- DMG packaging.
- StoreKit or paid unlocks.
- Mac App Store archive/export/submission.
- App Store Connect metadata.
