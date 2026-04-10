import Foundation
import SwiftUI
import XCTest

@testable import Sceal

@MainActor
class NotesStoreTestCase: XCTestCase {
  // Uses a clean UserDefaults suite so settings tests never leak state across runs.
  func makeUserDefaults(file: StaticString = #filePath, line: UInt = #line) -> UserDefaults {
    let suiteName = "ScealTests.\(UUID().uuidString)"
    guard let userDefaults = UserDefaults(suiteName: suiteName) else {
      XCTFail("Expected isolated test user defaults.", file: file, line: line)
      return .standard
    }

    addTeardownBlock {
      userDefaults.removePersistentDomain(forName: suiteName)
    }

    return userDefaults
  }

  // Builds a stable local date so note-order tests do not depend on the current clock.
  func makeDate(year: Int, month: Int, day: Int) -> Date {
    var components = DateComponents()
    components.calendar = Calendar(identifier: .gregorian)
    components.timeZone = TimeZone(secondsFromGMT: 0)
    components.year = year
    components.month = month
    components.day = day
    components.hour = 12
    return components.date!
  }

  // Builds a daily note with predictable IDs and content for store tests.
  func makeDailyNote(
    year: Int,
    month: Int,
    day: Int,
    title: String = "",
    tags: [String] = [],
    body: String = ""
  ) -> DayNote {
    DayNote(
      date: makeDate(year: year, month: month, day: day), title: title, tags: tags, body: body)
  }

  // Builds a list note with a custom ID so list order tests can model grouped notes.
  func makeListNote(
    id: String,
    year: Int,
    month: Int,
    day: Int,
    title: String = "",
    tags: [String] = [],
    body: String = ""
  ) -> DayNote {
    DayNote(
      date: makeDate(year: year, month: month, day: day),
      id: id,
      title: title,
      tags: tags,
      body: body
    )
  }

  // Builds a store with injected notes and defaults while avoiding disk-backed loading.
  func makeStore(
    previewNotes: [DayNote] = [],
    userDefaults: UserDefaults? = nil
  ) -> NotesStore {
    NotesStore(
      calendar: Calendar(identifier: .gregorian),
      userDefaults: userDefaults ?? .standard,
      previewNotes: previewNotes
    )
  }
}
