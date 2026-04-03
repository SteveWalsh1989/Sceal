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

  init(date: Date, title: String, tags: [String], body: String) {
    self.date = date
    self.id = ScealDateFormatters.storageDate.string(from: date)
    self.title = title
    self.tags = tags
    self.body = body
  }

  init(date: Date, id: ID, title: String, tags: [String], body: String) {
    self.date = date
    self.id = id
    self.title = title
    self.tags = tags
    self.body = body
  }

  // Markdown filename derived from the date-based ID.
  var fileName: String {
    "\(id).md"
  }

  // Falls back to 'Untitled note' when the title is blank.
  var displayTitle: String {
    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmedTitle.isEmpty ? "Untitled note" : trimmedTitle
  }

  // Two-digit day number for sidebar card display.
  var dayNumberText: String {
    ScealDateFormatters.dayNumber.string(from: date)
  }

  // Short weekday name (e.g. 'Mon') for sidebar cards.
  var weekdayText: String {
    ScealDateFormatters.weekday.string(from: date)
  }

  // Full date string shown in the editor header.
  var editorDateText: String {
    ScealDateFormatters.editorDate.string(from: date)
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

  // Duplicates this note's content onto today's date for the "copy previous" new-note default.
  func copyForToday(calendar: Calendar = .current) -> DayNote {
    DayNote(
      date: calendar.startOfDay(for: .now),
      title: title,
      tags: tags,
      body: body
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
        "<!-- hcolor:turquoise -->",
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
        "<!-- hcolor:pink -->",
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
        "<!-- hcolor:blue -->",
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
        "<!-- hcolor:purple -->",
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
        "<!-- hcolor:grey -->",
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

  // Static preview data for SwiftUI previews and testing.
  static let previewNotes: [DayNote] = {
    let previewDate = ScealDateFormatters.storageDate.date(from: "2026-04-01") ?? .now
    return sampleSeedNotes(relativeTo: previewDate)
  }()
}
