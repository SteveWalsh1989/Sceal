//
//  DayNote.swift
//
//

// Core data model representing a single day's note with date, title, tags, and body.

import Foundation

struct DayNote: Identifiable, Equatable, Sendable {
  typealias ID = String

  let date: Date
  let id: ID
  var title: String
  var tags: [String]
  var body: String

  nonisolated init(date: Date, title: String, tags: [String], body: String) {
    self.date = date
    self.id = NoteDateFormatters.storageDate.string(from: date)
    self.title = title
    self.tags = tags
    self.body = body
  }

  nonisolated init(date: Date, id: ID, title: String, tags: [String], body: String) {
    self.date = date
    self.id = id
    self.title = title
    self.tags = tags
    self.body = body
  }

  nonisolated static func == (lhs: DayNote, rhs: DayNote) -> Bool {
    lhs.date == rhs.date
      && lhs.id == rhs.id
      && lhs.title == rhs.title
      && lhs.tags == rhs.tags
      && lhs.body == rhs.body
  }

  // Markdown filename derived from the date-based ID.
  nonisolated var fileName: String {
    "\(id).md"
  }

  // Falls back to 'Untitled note' when the title is blank.
  var displayTitle: String {
    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmedTitle.isEmpty ? "Untitled note" : trimmedTitle
  }

  // Two-digit day number for sidebar card display.
  var dayNumberText: String {
    NoteDateFormatters.dayNumber.string(from: date)
  }

  // Short weekday name (e.g. 'Mon') for sidebar cards.
  var weekdayText: String {
    NoteDateFormatters.weekday.string(from: date)
  }

  // Full date string shown in the editor header.
  var editorDateText: String {
    NoteDateFormatters.editorDate.string(from: date)
  }

  // Formats the date using the user's chosen sidebar date format.
  func sidebarDateText(using format: SidebarDateFormat) -> String {
    format.string(from: date)
  }

  // Comma-separated tag string for sidebar card display.
  var sidebarTagsText: String {
    tags.joined(separator: ", ")
  }

  // Creates a blank note for the given date.
  static func empty(for date: Date, calendar: Calendar = .current) -> DayNote {
    DayNote(
      date: calendar.startOfDay(for: date),
      title: "",
      tags: [],
      body: ""
    )
  }
}

extension DayNote {
  private struct SampleSeedDefinition {
    let offset: Int
    let title: String
    let tags: [String]
    let body: String
  }

  private static let sampleSeedDefinitions: [SampleSeedDefinition] = [
    SampleSeedDefinition(
      offset: -1,
      title: "Starter note: sections, colors, lists, and a few calm moments",
      tags: ["starter", "demo", "journal"],
      body: [
        MarkdownEditorHeadingColorMarkdown.marker(colorName: "turquoise"),
        "# Morning reset",
        "",
        "A longer sample note that shows how the editor looks once a day has some shape.",
        "",
        "- Opened the windows",
        "- Wrote the demo beats in **tiny, clear chunks**",
        "- Kept the plan *light enough to finish*",
        "",
        "",
        "<!-- section -->",
        "",
        MarkdownEditorHeadingColorMarkdown.marker(colorName: "pink"),
        "## Practical list",
        "",
        "- [x] Pack charger",
        "- [x] Reply to Aoife",
        "- [ ] Move the `release-notes` draft into today's plan",
        "",
        "~~Missed the first tram~~ The quieter second one was better anyway.",
        "",
        "",
        "<!-- section -->",
        "",
        MarkdownEditorHeadingColorMarkdown.marker(colorName: "blue"),
        "## Sunday reset",
        "",
        "> The best kind of plan was the one that fit on half a page.",
        "",
        "1. Open the windows",
        "2. Water the plants",
        "3. Bookmark [that cafe](https://example.com) for Friday",
        "",
        "",
        "<!-- section -->",
        "",
        MarkdownEditorHeadingColorMarkdown.marker(colorName: "green"),
        "## Prompt area",
        "",
        "Use `/prompt` when a thought needs to become a reusable instruction:",
        "",
        MarkdownEditorPromptBlockMarkdown.startMarker,
        "Write a warm, concise check-in note from these rough bullets.",
        "",
        "Keep it human, keep the structure easy to scan, and include one clear next action. This prompt area grows as the text gets longer, the Copy button sends the full prompt to the clipboard, and the x button removes it when the draft is finished.",
        MarkdownEditorPromptBlockMarkdown.endMarker,
        "",
        "",
        "<!-- section -->",
        "",
        MarkdownEditorHeadingColorMarkdown.marker(colorName: "purple"),
        "## Quick capture",
        "",
        "Saved the tiny script before bed:",
        "",
        "```swift",
        "print(\"Back up the note before sleep\")",
        "```",
        "",
        "",
        "<!-- section -->",
        "",
        MarkdownEditorHeadingColorMarkdown.marker(colorName: "grey"),
        "### Tomorrow",
        "",
        "Leave the title simple and let the note do the work.",
      ].joined(separator: "\n")
    )
  ]

  // Seeds a longer starter note so an empty library shows the editor features immediately.
  static func sampleSeedNotes(relativeTo referenceDate: Date, calendar: Calendar = .current)
    -> [DayNote]
  {
    let baseDate = calendar.startOfDay(for: referenceDate)

    return
      sampleSeedDefinitions
      .compactMap { definition in
        guard let date = calendar.date(byAdding: .day, value: definition.offset, to: baseDate)
        else {
          return nil
        }

        return DayNote(
          date: calendar.startOfDay(for: date),
          title: definition.title,
          tags: definition.tags,
          body: definition.body
        )
      }
      .sorted(by: { $0.date > $1.date })
  }
}

#if DEBUG
  extension DayNote {
    private struct DemoModeDefinition {
      let offset: Int
      let title: String
      let tags: [String]
      let body: String
    }

    private static func demoSectionMarker(colorName: String) -> String {
      MarkdownEditorSectionDirectiveMarkdown.marker(
        headingColorName: colorName,
        bulletColorName: colorName,
        usesSectionColor: true
      )
    }

    private static let demoModeDefinitions: [DemoModeDefinition] = [
      DemoModeDefinition(
        offset: 0,
        title: "Welcome to Scéal",
        tags: ["demo", "showcase", "daily"],
        body: [
          MarkdownEditorHeadingColorMarkdown.marker(colorName: "turquoise"),
          "# Welcome to Scéal",
          "",
          "Scéal is a local-first notes app for daily writing, planning, and collecting ideas without turning your notes into a full workspace system.",
          "",
          "- Daily notes for reflection and planning",
          "- Freeform notes for projects and reference material",
          "- Search across your writing",
          "- Local markdown storage",
          "- Custom themes, fonts, spacing, colours, cards, and dividers",
          "",
          "[Read the project README](https://github.com/) when you want the technical details.",
          "",
          demoSectionMarker(colorName: "pink"),
          "",
          "## Today's Focus",
          "",
          "A good note should be easy to scan later. Scéal gives plain markdown a more visual structure without hiding the text underneath.",
          "",
          "- [x] Capture the main idea",
          "- [x] Break the note into clear sections",
          "- [ ] Add a few links worth revisiting",
          "- [ ] Turn rough thoughts into next actions",
          "",
          "> Notes should feel calm while you write, but useful when you return to them.",
          "",
          demoSectionMarker(colorName: "orange"),
          "",
          "## Prompt Block",
          "",
          "Prompt blocks are useful when a reusable instruction belongs beside the rest of the note.",
          "",
          MarkdownEditorPromptBlockMarkdown.startMarker,
          "Turn these daily notes into a short end-of-day summary.",
          "",
          "Keep the tone practical, mention what moved forward, call out one open question, and finish with the next action. Copy this whole prompt with one click, then remove the block with the x button when it is no longer needed.",
          MarkdownEditorPromptBlockMarkdown.endMarker,
          "",
          demoSectionMarker(colorName: "orange"),
          "",
          "## Project Plan",
          "",
          "### Build",
          "",
          "- Sketch the rough direction",
          "- Keep the first version small",
          "- Use headings to give the note shape",
          "- Add bullets when the order does not matter",
          "",
          "### Review",
          "",
          "1. Check the note still reads clearly",
          "2. Move loose ideas into the right section",
          "3. Mark completed actions",
          "4. Link out to anything useful",
          "",
          demoSectionMarker(colorName: "blue"),
          "",
          "## End Of Day",
          "",
          "- [ ] What moved forward today?",
          "- [ ] What should I pick up next?",
          "- [ ] Is there anything worth saving as a reusable note?",
          "",
          "A note does not need to be perfect. It just needs to be clear enough to come back to.",
        ].joined(separator: "\n")
      ),
      DemoModeDefinition(
        offset: -1,
        title: "Design QA and screenshot prep",
        tags: ["demo", "design", "qa"],
        body: [
          MarkdownEditorHeadingColorMarkdown.marker(colorName: "orange"),
          "# Design QA",
          "",
          "Use this note to check how a denser workday looks with headings, lists, links, and section colour.",
          "",
          "- Review card spacing in the sidebar",
          "- Check divider gaps at the current font size",
          "- Keep the screenshot crop focused on the editor",
          "",
          demoSectionMarker(colorName: "purple"),
          "",
          "## Capture Checklist",
          "",
          "- [x] Pick a theme with clear card contrast",
          "- [x] Show at least three section cards",
          "- [ ] Try the same note with a warmer accent colour",
          "- [ ] Export a clean screenshot for the README",
          "",
          "Useful reference: [Apple screenshots guidance](https://developer.apple.com/design/human-interface-guidelines/).",
          "",
          demoSectionMarker(colorName: "grey"),
          "",
          "## Notes",
          "",
          "The current setup works best when the title is short and the first section starts high enough to show the card shape.",
          "",
          "`/div` inserts a divider while writing; saved notes store it as `<!-- section -->`.",
        ].joined(separator: "\n")
      ),
      DemoModeDefinition(
        offset: -2,
        title: "Research notes: local-first writing",
        tags: ["demo", "research", "links"],
        body: [
          MarkdownEditorHeadingColorMarkdown.marker(colorName: "blue"),
          "# Local-first writing",
          "",
          "A quick research note for links, quotes, and small observations.",
          "",
          "> Local notes should feel owned, portable, and easy to revisit.",
          "",
          "- [Local-first software](https://www.inkandswitch.com/local-first/)",
          "- [Markdown guide](https://www.markdownguide.org/basic-syntax/)",
          "- [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)",
          "",
          demoSectionMarker(colorName: "turquoise"),
          "",
          "## What matters",
          "",
          "- Files should stay readable outside the app",
          "- Export should be obvious",
          "- The editor should add polish without hiding markdown",
          "- Search keeps older notes from disappearing",
          "",
          demoSectionMarker(colorName: "pink"),
          "",
          "## Tiny Example",
          "",
          "```swift",
          "let storage = \"markdown on disk\"",
          "let sync = \"optional, not required\"",
          "```",
          "",
          "~~Cloud-first by default~~ Local-first by default.",
        ].joined(separator: "\n")
      ),
      DemoModeDefinition(
        offset: -3,
        title: "Weekly reset",
        tags: ["demo", "planning", "reset"],
        body: [
          MarkdownEditorHeadingColorMarkdown.marker(colorName: "green"),
          "# Weekly reset",
          "",
          "A calm planning note with enough structure for real use.",
          "",
          "- Clear the open loops",
          "- Pick the next important thing",
          "- Leave future context in plain language",
          "",
          demoSectionMarker(colorName: "orange"),
          "",
          "## This Week",
          "",
          "- [x] Tidy the sample note",
          "- [x] Check dark theme contrast",
          "- [ ] Capture the README image",
          "- [ ] Write a short release note",
          "",
          demoSectionMarker(colorName: "purple"),
          "",
          "## Parking Lot",
          "",
          "- Add a keyboard shortcut for the demo toggle later",
          "- Try a lighter theme screenshot",
          "- Keep the default note concise",
          "",
          "**Rule:** if the note looks busy, remove text before adding more styling.",
        ].joined(separator: "\n")
      ),
    ]

    // Builds the canonical in-memory demo library without writing sample files to disk.
    static func demoModeNotes(relativeTo referenceDate: Date, calendar: Calendar = .current)
      -> [DayNote]
    {
      let baseDate = calendar.startOfDay(for: referenceDate)

      return
        demoModeDefinitions
        .compactMap { definition in
          guard let date = calendar.date(byAdding: .day, value: definition.offset, to: baseDate)
          else {
            return nil
          }

          return DayNote(
            date: calendar.startOfDay(for: date),
            title: definition.title,
            tags: definition.tags,
            body: definition.body
          )
        }
        .sorted(by: { $0.date > $1.date })
    }
  }
#endif
