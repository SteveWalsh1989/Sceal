# Data Storage

Scéal stores user data locally under:

```text
~/Library/Application Support/Sceal/
```

## Folder Layout

```text
Sceal/
  Notes/
  ListNotes/
    groups.json
  Attachments/
  Restore Safety Backups/
```

## Notes

Daily notes are stored as Markdown files in `Notes/`.

List notes are stored as Markdown files in `ListNotes/`. The `ListNotes/groups.json` file stores list-note ordering, group membership, group names, and collapsed state.

Markdown front matter uses JSON-encoded values for fields such as title and tags. This is intentional so titles and tags can round-trip safely.

## Attachments

Images copied or pasted into notes are stored in `Attachments/<note-id>/`. Markdown image links point at these local attachment folders.

## Preferences

Scéal stores appearance settings, editor preferences, new-note defaults, and backup configuration in macOS user defaults for the app bundle identifier `com.stevewalsh.sceal`.

Backup folder access uses a security-scoped bookmark so the sandboxed app can keep writing to the selected backup folder.
