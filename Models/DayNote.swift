//
//  DayNote.swift
//  dayra
//
//

import Foundation

struct DayNote: Identifiable, Equatable {
  typealias ID = String

  let date: Date
  var title: String
  var tags: [String]
  var body: String

  var id: ID {
    DayraDateFormatters.storageDate.string(from: date)
  }

  var fileName: String {
    "\(id).md"
  }

  var displayTitle: String {
    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmedTitle.isEmpty ? "Untitled note" : trimmedTitle
  }

  var dayNumberText: String {
    DayraDateFormatters.dayNumber.string(from: date)
  }

  var weekdayText: String {
    DayraDateFormatters.weekday.string(from: date)
  }

  var editorDateText: String {
    DayraDateFormatters.editorDate.string(from: date)
  }

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
      title: "Soft launch prep and one neat little win",
      tags: ["work", "demo"],
      body: [
        "<!-- hcolor:turquoise -->",
        "# Morning reset",
        "",
        "- Opened the app with tea and a clean desk",
        "- Wrote the demo beats in **tiny, clear chunks**",
        "",
        "---",
        "",
        "<!-- hcolor:orange -->",
        "## Nice surprise",
        "",
        "The new section cards make the day feel calmer to scan.",
      ].joined(separator: "\n")
    ),
    SampleSeedDefinition(
      offset: -2,
      title: "Rain on the tram and a very practical list",
      tags: ["routine", "commute"],
      body: [
        "<!-- hcolor:pink -->",
        "## On the way in",
        "",
        "*Grey skies, warm coffee, zero rush.*",
        "",
        "- [x] Pack charger",
        "- [x] Reply to Aoife",
        "- [ ] Move the `release-notes` draft into today's plan",
        "",
        "~~Missed the first tram~~ The second one was quieter anyway.",
      ].joined(separator: "\n")
    ),
    SampleSeedDefinition(
      offset: -3,
      title: "Sunday reset and a slow walk by the river",
      tags: ["weekend", "reset"],
      body: [
        "<!-- hcolor:blue -->",
        "# Sunday reset",
        "",
        "> The best kind of plan was the one that fit on half a page.",
        "",
        "1. Open the windows",
        "2. Water the plants",
        "3. Bookmark [that cafe](https://example.com) for Friday",
      ].joined(separator: "\n")
    ),
    SampleSeedDefinition(
      offset: -4,
      title: "Late tidy-up before the month turned",
      tags: ["home", "quiet"],
      body: [
        "<!-- hcolor:purple -->",
        "## Quick capture",
        "",
        "Saved the tiny script before bed:",
        "",
        "```swift",
        "print(\"Back up the note before sleep\")",
        "```",
        "",
        "---",
        "",
        "<!-- hcolor:grey -->",
        "### Tomorrow",
        "",
        "Leave the title simple and let the note do the work.",
      ].joined(separator: "\n")
    ),
  ]

  // Seeds a short four-day history so an empty library shows the editor features immediately.
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

  static let previewNotes: [DayNote] = {
    let previewDate = DayraDateFormatters.storageDate.date(from: "2026-04-01") ?? .now
    return sampleSeedNotes(relativeTo: previewDate)
  }()
}
