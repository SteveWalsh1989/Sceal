# StoreKit Preparation

Scéal is prepared for a local StoreKit paid unlock, but it is not connected to App Store Connect yet.

## Current Product Model

The current paid tier should be treated as one non-consumable unlock:

```text
Reference name: Scéal Paid Unlock
Product ID: com.stevewalsh.sceal.paidUnlock
Type: Non-Consumable In-App Purchase
Suggested local price: 14.99
Family sharing: off until explicitly decided
```

The product ID is intentionally isolated in `StoreEntitlement.paidUnlock.productID`. If App Store Connect later requires a different identifier, update that value and the local StoreKit configuration together.

## Code Boundary

- `StoreEntitlement` maps durable purchase identifiers to app entitlements.
- `StorePurchaseServicing` defines product loading, purchase, entitlement refresh, and restore.
- `LocalStorePurchaseService` lets tests and developer workflows simulate purchases without StoreKit.
- `StoreKitPurchaseService` is the real StoreKit adapter for local Xcode testing and later App Store builds.
- `PlanAccessStore` maps entitlement state into `AppPlan` and `AppFeatureAccess`.

Do not import StoreKit in note, template, theme, backup, import, export, markdown, or storage code.

## Local Xcode Setup

You do not need an Apple Developer account for this local setup.

1. In Xcode, choose `File > New > File from Template`.
2. Search for `StoreKit Configuration File`.
3. Create a local, unsynced configuration file.
4. Add one non-consumable in-app purchase with the product details above.
5. Open the `Sceal` scheme, then `Run > Options`.
6. Select the StoreKit configuration file for `StoreKit Configuration`.
7. Build and run the app from Xcode when testing purchase flows.

The configuration file is local test data. It does not upload to App Store Connect and does not appear in App Store-signed apps.

## What Still Needs App Store Connect

- Real app record.
- Real in-app purchase record.
- Final product ID confirmation.
- Paid Apps Agreement.
- Sandbox/TestFlight validation.
- App Review metadata for the unlock.
- Production purchase and restore QA.

## Manual QA Once A Purchase UI Exists

- Free launch with no entitlement shows paid-only features as locked.
- Paid purchase grants custom themes, extra templates, and automatic backup schedules.
- Restore purchases restores paid access after reinstall.
- User cancellation leaves the app on Free without errors.
- Pending purchase leaves the app usable and does not grant paid access early.
- Refund or revocation removes paid-only runtime access without deleting saved settings or notes.
