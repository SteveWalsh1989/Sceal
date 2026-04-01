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
  static let previewNotes: [DayNote] = [
    DayNote(
      date: DayraDateFormatters.storageDate.date(from: "2026-04-01") ?? .now,
      title: "Q1-C2-S2: polish sidebar cards and validate import flow",
      tags: ["sprint-14", "feature"],
      body: "# Planning\n\n- Finish sidebar shell\n- Verify markdown file persistence"
    ),
    DayNote(
      date: DayraDateFormatters.storageDate.date(from: "2026-03-31") ?? .now,
      title: "Retro notes and loose ends from the last sprint review",
      tags: ["retro"],
      body: "## Retro\n\n- What worked\n- What to change"
    ),
  ]
}
