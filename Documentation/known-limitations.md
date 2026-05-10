# Known Limitations

These are the release-readiness limitations to keep visible before broader distribution.

## Distribution

- Direct-download signing and notarization infrastructure exists, but a public build still requires local Apple Developer setup: Developer ID Application certificate, notary profile, accepted notarization, stapling, and Gatekeeper verification.
- Mac App Store setup, App Store Connect metadata, sandbox review, and production StoreKit paid features are not implemented in this pass. Local StoreKit architecture and product-id preparation exist.
- Auto-update support, such as Sparkle for direct downloads, is not implemented in this pass.

## Product

- There is no cloud sync.
- There is no account system.
- Paid feature gates exist, but production purchase UI and App Store entitlement validation are not complete.
- Restore is replace-style, not merge-style.

## Import And Export

- Date-range export covers daily notes only.
- Full-library export and restore are the correct paths for list notes, groups, attachments, and metadata.
- Day One media is skipped by the current importer.

## Support

The final public support channel depends on the chosen release route:

- Open source GitHub release: GitHub Issues.
- Website/direct download: support email or support form.
- Mac App Store: Support URL/contact page with real contact information.

TODO: Choose and publish the final support channel before public release.
