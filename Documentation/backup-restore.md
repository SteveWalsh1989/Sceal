# Backup And Restore

Scéal supports both ongoing backups and full-library archive restore.

## Automatic Backups

The Backup settings screen lets users choose a backup folder. Scéal creates a managed `Sceal Backup` folder inside that selected folder and writes zip archives there.

Automatic backups can run hourly, daily, or weekly. Manual backups are never pruned automatically. Automatic backups are pruned according to the selected schedule.

## Full-Library Export

The Export settings screen includes a full-library export. It writes a zip archive containing:

```text
Sceal Backup/
  Notes/
  ListNotes/
    groups.json
  Attachments/
  backup-metadata.json
```

The archive includes daily notes, list notes, list-note groups, attachments, and metadata.

## Restore Behavior

Restore is replace-style, not merge-style.

Before replacing the live library, Scéal validates the selected archive. Validation checks metadata, backup format version, required folders, note decoding, list-note groups, and metadata counts.

After validation and before replacement, Scéal writes a safety archive of the current library to:

```text
~/Library/Application Support/Sceal/Restore Safety Backups/
```

Only after that safety archive is written does Scéal replace:

- `Notes/`
- `ListNotes/`
- `Attachments/`

## Restore Limitations

- Restore accepts full-library Scéal zip archives, not generic Markdown folders.
- Restore replaces the current library snapshot.
- Existing non-destructive imports remain available for Markdown, Diarly, Day One, and unzipped Scéal folder imports.
- Signing/notarization, Sparkle, StoreKit, and paid-feature work are separate from the restore implementation.
