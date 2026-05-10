# Free And Paid Features

Scéal uses a capability policy layer for Free vs Paid behavior. StoreKit should only provide entitlement state; app code decides what each entitlement unlocks.

## Current Policy

| Area | Free | Paid |
| --- | --- | --- |
| Notes | Daily notes, list notes, markdown editing, imports, exports, and restore | Same |
| Templates | One editable template | Unlimited saved templates |
| New note defaults | Blank, copy previous, or the included template | Any saved template |
| Themes | Two dark themes and two light themes | Full built-in theme library |
| Custom colors | Built-in theme colors only | Fully custom theme color tokens |
| Backups | Manual backups | Manual, hourly, daily, weekly, and inactive-window backups |

## Runtime Rules

- Free gates paid write actions, not stored user data.
- Paid-only saved choices are preserved when the app is in Free mode.
- If Free cannot use a saved setting, Scéal applies a safe runtime fallback.
- Notes, attachments, imports, exports, restore, and markdown storage must not depend on the paid plan.

## Appearance Recommendation

Do not gate readability and accessibility controls:

- Body font.
- Body font size.
- Sidebar font size.
- Line height.
- List spacing.
- Section gap.
- Bullet size.
- Spell checking.
- Sidebar tags, weekend visibility, and date format.

These settings affect comfort, accessibility, and basic usability. The paid tier should focus on richer personalization and automation: premium themes, custom colors, extra templates, and backup scheduling.

## Upgrade UI

Paid-only controls should use the shared upgrade components:

- `UpgradeLockIndicator`
- `UpgradeLockedStatus`
- `UpgradeLockedBanner`

The upgrade button intentionally has a StoreKit TODO until the Mac App Store purchase flow is connected.
