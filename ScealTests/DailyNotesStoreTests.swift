import Foundation
import XCTest

@testable import Sceal

@MainActor
final class DailyNotesStoreTests: NotesStoreTestCase {
  // Keeps daily-note lookup behavior stable after moving state out of NotesStore.
  func testReplacingNotesRebuildsLookupIndex() {
    let first = makeDailyNote(year: 2026, month: 5, day: 10)
    let second = makeDailyNote(year: 2026, month: 5, day: 11)
    let store = DailyNotesStore(notes: [first], calendarBrowseYear: 2026)

    XCTAssertEqual(store.note(withID: first.id)?.id, first.id)

    store.replaceNotes([second])

    XCTAssertNil(store.note(withID: first.id))
    XCTAssertEqual(store.note(withID: second.id)?.id, second.id)
  }

  // Keeps selection, search, and calendar state together in the daily-note feature store.
  func testUpdatesDailyModeState() {
    let store = DailyNotesStore(calendarBrowseYear: 2026)

    store.selectNote("2026-05-10")
    store.updateSearchText("meeting")
    store.updateSearchBarExpanded(true)
    store.updateCalendarBrowseYear(2025)

    XCTAssertEqual(store.selectedNoteID, "2026-05-10")
    XCTAssertEqual(store.searchText, "meeting")
    XCTAssertTrue(store.isSearchBarExpanded)
    XCTAssertEqual(store.calendarBrowseYear, 2025)
  }
}
