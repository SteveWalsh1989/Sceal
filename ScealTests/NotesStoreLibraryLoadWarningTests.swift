import Foundation
import XCTest

@testable import Sceal

@MainActor
final class NotesStoreLibraryLoadWarningTests: NotesStoreTestCase {
  // Shows a non-blocking warning when startup skips corrupt files but still loads valid notes.
  func testLoadIfNeededShowsLibraryWarningForSkippedDailyNote() throws {
    let libraryLocation = makeLibraryLocation()
    let repository = LibraryRepository(libraryLocation: libraryLocation)
    try repository.saveDailyNote(
      DayNote(
        date: makeDate(year: 2026, month: 5, day: 10),
        title: "Valid",
        tags: [],
        body: "Body"
      )
    )
    try "not front matter".write(
      to: try repository.dailyNotesDirectoryURL().appendingPathComponent("2026-05-11.md"),
      atomically: true,
      encoding: .utf8
    )
    let store = makeStore(libraryLocation: libraryLocation)

    store.loadIfNeeded()

    XCTAssertEqual(store.notes.map(\.id), ["2026-05-10"])
    XCTAssertEqual(store.libraryLoadWarnings.count, 1)
    XCTAssertEqual(store.libraryLoadWarnings.first?.kind, .dailyNote)
    XCTAssertEqual(store.userMessage?.kind, .warning)
    XCTAssertTrue(store.userMessage?.text.contains("1 daily note") == true)
  }
}
