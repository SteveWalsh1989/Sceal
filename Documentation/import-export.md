# Import And Export

Scéal has two different concepts: non-destructive import/export and full-library restore.

## Date-Range Export

Date-range export writes selected daily notes into a year-organized zip archive. This is useful for sharing or inspecting a subset of daily notes.

This export is daily-note focused. It does not include list notes or list-note groups.

## Full-Library Export

Full-library export writes a complete Scéal archive with daily notes, list notes, groups, attachments, and metadata. Use this when moving the whole library between Macs or before testing a release build.

## Non-Destructive Imports

The Import settings screen keeps the existing import flows:

- Markdown folders from apps such as Obsidian, Logseq, Joplin, Bear, Apple Notes, or similar apps
- Unzipped Scéal export folders
- Unzipped Diarly Markdown exports
- Day One JSON exports

These imports add new daily notes and skip existing dates. They do not replace the full library.

## Restore

Restore accepts a full-library Scéal zip archive and replaces the current library after validation and safety backup creation.

## Current Limitations

- Day One media is skipped in the current importer.
- Generic Markdown import depends on dated Markdown files.
- Unzipped Scéal folder import is non-destructive and daily-note focused.
- Full-library restore is intentionally destructive after confirmation; use full-library export or automatic backup first if you need a recovery point.
