# Scéal

Scéal is a local-first macOS notes app for daily writing, planning, and reusable working notes.

It stores notes as markdown on your Mac, then adds a native editor on top: visual sections, slash commands, reusable templates, prompt blocks with one-click copy, editable tables, checkboxes, images, and per-section colour.

## What Scéal is

- Daily notes for journaling, reflection, planning, and end-of-day capture
- Freeform list notes for projects, reference material, and longer-running ideas
- Calendar and list views for moving between recent writing and older entries
- Search across titles, tags, and note content
- Optional GitHub integration for tracking your pull requests in daily notes
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

| Command                  | Inserts                                          |
| ------------------------ | ------------------------------------------------ |
| `/div`                   | Visual section divider                           |
| `/heading-1`             | Level 1 heading                                  |
| `/heading-2`             | Level 2 heading                                  |
| `/heading-3`             | Level 3 heading                                  |
| `/code`                  | Fenced code block                                |
| `/prompt`                | Copyable prompt block                            |
| `/table`                 | Editable table                                   |
| `/github`                | GitHub pull request section                      |
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

## GitHub pull requests

Use `/github` to add a pull request section to a daily note. Connect your GitHub account in **Settings → GitHub** using a personal access token with access to the repositories you want to track. The integration reads your authored PRs across accessible repositories; it does not create or modify anything on GitHub. The token is stored in macOS Keychain.

PRs are split into **Opened today** and **Carried forward**, with linked titles, repository details, and Open, Draft, Merged, or Closed status badges. Refresh today's note on demand using the refresh button. Scéal also refreshes when the section opens and every five minutes while the app is active.

### Daily history

Each note saves its own PR snapshot locally. Historical notes retain the status recorded for that day: a PR that was open on Monday stays open in Monday's note even if it merges on Friday.

When creating a note by copying the previous day, only unfinished PRs carry forward. Completed PRs remain in the original note as a record of that day's work. PR titles, links, and statuses are included in Markdown exports.

### Display and ordering

App-wide defaults in **Settings → GitHub** let you rename the PR section and its two groups, choose the section title colour, set which group appears first, and hide empty groups.

The GitHub section's **Section options** popover provides per-section controls that are saved with the note and carried forward when copying it:

- Choose which date group appears first
- Switch between Regular rows with repository details and Compact, single-line rows
- Show or hide PR icons and row dividers
- Set the section heading colour to the app default, match the section colour, or choose a custom colour; individual PR links keep a neutral text colour with a subtle hover effect
- Sort each group by Newest first, Title A–Z, or Manual order

In Manual mode, hover over a row to reveal a drag handle immediately left of its status badge on the right. Drag a PR onto another row in the same group to reorder it. Refresh preserves your arrangement and places newly discovered PRs at the top. Copying the previous note preserves manual ordering for unfinished PRs without rearranging older notes.

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

## Download and install

Download **Sceal-mac.zip** from the [latest release](https://github.com/SteveWalsh1989/Sceal/releases/latest). The app supports Apple Silicon and Intel Macs running macOS 14 or newer. You do not need Xcode or a clone of this repository.

1. Unzip the download.
2. Drag **Sceal.app** into **Applications**.
3. Open Scéal.

Scéal is distributed without an Apple Developer ID certificate or Apple notarization. macOS may block the first launch. After trying to open it, go to **System Settings → Privacy & Security**, find the message about Scéal, and click **Open Anyway**. Confirm the prompt, then open the app again if needed. Only approve a download you trust.

Release downloads are published separately from the source code; cloning the repository does not download the app. Download a newer release to update your installed copy.

## Build the app locally

From the repository root, run:

```bash
./scripts/build-mac-app.sh
```

You will need Xcode installed locally for the build script to complete successfully.

The script builds both Apple Silicon and Intel versions into one app and applies an ad hoc signature, which does not require a paid Apple Developer account. The resulting app is not notarized.

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
