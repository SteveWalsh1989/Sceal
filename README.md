# Scéal

Scéal is a local-first macOS notes app for daily writing, planning, and reusable working notes.

It stores notes as markdown on your Mac, then adds a native editor on top: visual sections, slash commands, reusable templates, prompt blocks with one-click copy, editable tables, checkboxes, images, and per-section colour.

## What Scéal is

- Daily notes for journaling, reflection, planning, and end-of-day capture
- Freeform list notes for projects, reference material, and longer-running ideas
- Calendar and list views for moving between recent writing and older entries
- Search across titles, tags, and note content
- Local markdown storage under `~/Library/Application Support/Sceal/`
- Import, export, backup, and restore tools for keeping ownership of your notes

<img width="1463" height="921" alt="image" src="https://github.com/user-attachments/assets/a92e5692-053d-463a-965f-528b7b316e7f" />

## Editor features

Scéal keeps the underlying notes markdown-based, but the editor renders common structures into a cleaner writing surface.

- Headings, bullet lists, numbered lists, checkboxes, links, quotes, inline formatting, and fenced code blocks
- Visual section dividers for splitting longer notes into readable blocks
- Per-section colours for headings, bullets, and checkboxes
- Prompt blocks that keep reusable instructions beside the rest of the note, with Copy and delete controls
- Editable table blocks with row and column controls, header toggling, full-width mode, and resizable columns
- Image attachments stored alongside the note library
- Paste handling for links, markdown, images, and table-like content

## Slash commands

Type `/` in the editor to insert structure without leaving the keyboard.

| Command | Inserts |
| --- | --- |
| `/div` | Visual section divider |
| `/heading-1` | Level 1 heading |
| `/heading-2` | Level 2 heading |
| `/heading-3` | Level 3 heading |
| `/code` | Fenced code block |
| `/prompt` | Copyable prompt block |
| `/table` | Editable table |
| Custom template commands | User-created note structures, such as `/meeting` |

<img width="723" height="564" alt="image" src="https://github.com/user-attachments/assets/e0fc763b-65b1-4e2d-899b-1f1ad48b5178" />

## Sections and colour

Sections are more than separators. A section can carry colour through the headings, bullets, and checkboxes that belong to it, which makes long notes easier to scan without turning the editor into a design tool.

Section colour can be edited directly in the note, and templates can apply a single section colour when they are inserted.

<img width="1359" height="536" alt="image" src="https://github.com/user-attachments/assets/dce13b32-0a1d-48a0-822a-7d300f1855b0" />

## Reusable templates

Templates are custom slash commands managed from Settings. They are useful for repeated structures such as meetings, daily reviews, project updates, planning notes, or prompt libraries.

- Give each template a title, slash command, and optional menu description
- Build the template content in a compact version of the note editor
- Choose whether insertion starts or ends with a section divider
- Apply one section colour across the inserted template
- Pick where the cursor lands after insertion, such as after the first heading or on the first empty bullet
- Use a template as the default for new notes, alongside blank notes and copying the previous note

For example, a Meeting template can be inserted with `/meeting`, add a `Meeting:` heading, create empty bullets, and leave the cursor where the next detail should be typed.

<img width="837" height="751" alt="image" src="https://github.com/user-attachments/assets/96f0bb2e-1d16-4adf-af2d-7f28100f9fc7" />

## Prompt blocks

Prompt blocks are for reusable instructions that belong inside a note: summary prompts, review prompts, research prompts, rewrite instructions, or any repeatable text you want to keep close to the surrounding context.

Use `/prompt` to insert a prompt block, edit it inline, copy the full prompt with one click, then delete the block when it is no longer needed.

<img width="1094" height="296" alt="image" src="https://github.com/user-attachments/assets/2af1bda7-1645-4ae4-9f3c-6b4e11323afd" />

## Tables

Use `/table` to insert a table without leaving the editor. Tables support editable cells, row and column actions, optional headers, full-width layout, and manual column resizing.

Tables are stored in Scéal's markdown-backed document format so they remain part of the note file while still behaving like rich editor blocks inside the app.

## Personalisation

- Choose the writing font
- Adjust body text size and sidebar text size
- Fine-tune line height, list spacing, bullet size, and section gap spacing
- Pick from built-in light and dark themes
- Set the accent colour used throughout the app
- Customise interface colours including the editor background, sidebar, cards, divider styling, and note borders
- Choose whether tags appear in the sidebar
- Change the sidebar date format
- Hide weekends in the calendar
- Enable or disable spell checking while typing

<img width="970" height="857" alt="image" src="https://github.com/user-attachments/assets/86f04ee2-750d-4850-863b-eb34e0630193" />

## Local data and portability

Scéal is built around local ownership rather than cloud-first storage.

- Notes are stored locally on your Mac
- Date-range export and full-library export are built in
- Full-library restore validates the archive and writes a pre-restore safety backup
- Local backups are supported
- Import from Markdown folders, Scéal exports, Diarly, and Day One is supported

Public docs:

- [Privacy](Documentation/privacy.md)
- [Data storage](Documentation/data-storage.md)
- [Backup and restore](Documentation/backup-restore.md)
- [Import and export](Documentation/import-export.md)
- [Uninstall](Documentation/uninstall.md)
- [Known limitations](Documentation/known-limitations.md)
- [Support routes](Documentation/support.md)

Support is still release-route dependent: GitHub Issues for an open-source release, support email or form for website/direct download, or a Support URL/contact page for Mac App Store.

## Requirements

- macOS 14 or newer
- Xcode installed locally when building from source

## Build the app locally

From the repository root, run:

```bash
./scripts/build-mac-app.sh
```

You will need Xcode installed locally for the build script to complete successfully.

## Find the built app

After the build finishes, the output is placed in `dist`:

- `dist/Sceal.app` - the macOS app bundle
- `dist/Sceal-mac.zip` - a zipped copy of the app bundle

To install it locally, drag `dist/Sceal.app` into `/Applications`.

## Technical details

- Native macOS app
- SwiftUI and AppKit editor implementation
- Local-first storage
- Notes are stored as markdown on disk
