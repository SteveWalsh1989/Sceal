# Scéal

Scéal is a local-first macOS notes app built to make everyday writing feel beautiful.

It is for people who want more than a blank editor, but less than an overbuilt workspace app. Scéal gives you a focused place to journal, think, plan, and collect ideas, while still making your notes feel structured, expressive, and fully your own.


<img width="1284" height="1175" alt="image" src="https://github.com/user-attachments/assets/476b2721-e491-4a83-9edc-c3e1dd15d7db" />


## A notes app that feels crafted

Scéal is designed around a simple idea: writing tools should disappear when you need focus, but still give you enough shape and personality to make the experience enjoyable.

That means daily notes that are easy to return to, freeform notes that are flexible enough for real use, and an editor that feels far more intentional than a plain markdown field.

## What can Scéal do

- Daily notes give journaling and reflection a natural home without adding friction
- Calendar and list views make it easy to move between recent writing and older entries
- Freeform list notes give you space for ideas, planning, working notes, and long-running reference material
- Search keeps your notes useful over time instead of letting them disappear into an archive
- Local-first storage keeps your writing on your Mac and under your control

## A richer writing experience

Scéal is built to make writing feel clearer, more visual, and more rewarding.

- Markdown-based editing with support for headings, lists, checkboxes, links, quotes, code blocks, and inline formatting
- Visual section dividers that break long notes into cleaner, more readable sections
- Slash commands for quickly inserting dividers, headings, and code blocks without breaking writing flow
- Section-level styling that lets headings, bullets, and checkboxes carry their own colour identity
- A note editor that feels polished and expressive rather than raw and mechanical

This is one of the things that makes Scéal stand out: it does not just store text well, it helps your notes look and feel better while you are writing them.




## Personalisation that actually matters

Scéal is not locked into a single look. It gives you meaningful control over how the app feels day to day.

<img width="849" height="803" alt="image" src="https://github.com/user-attachments/assets/ec5d63af-1554-4146-9a27-2fb4f432c012" />


- Choose the writing font that suits you
- Adjust body text size and sidebar text size
- Fine-tune line height, list spacing, bullet size, and section gap spacing
- Pick from built-in light and dark themes
- Set the accent colour used throughout the app
- Customise core interface colours including the editor background, sidebar, cards, divider styling, and note borders
- Choose whether tags appear in the sidebar
- Change the sidebar date format

The result is an app that can feel minimal, warm, sharp, soft, dense, airy, dark, light, or somewhere in between. 

## Built for ownership

Scéal is for people who do not want their notes trapped inside a cloud-first product.

- Notes are stored locally
- Export is built in
- Local backups are supported
- Import from Diarly is supported

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
- Local-first storage
- Notes are stored as markdown on disk
