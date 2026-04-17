import XCTest

@testable import Sceal

@MainActor
final class NotesStoreDailyTests: NotesStoreTestCase {
  // Prevents date navigation helpers from returning the wrong neighboring notes.
  func testAdjacentNoteIDsFollowDateOrder() {
    let notes = [
      makeDailyNote(year: 2026, month: 4, day: 3, title: "Newest"),
      makeDailyNote(year: 2026, month: 4, day: 2, title: "Middle"),
      makeDailyNote(year: 2026, month: 4, day: 1, title: "Oldest"),
    ]
    let store = makeStore(previewNotes: notes)

    let adjacent = store.adjacentNoteIDs(for: notes[1].id)

    XCTAssertEqual(adjacent.previous, notes[2].id)
    XCTAssertEqual(adjacent.next, notes[0].id)
  }

  // Prevents sidebar month sections from mixing months or scrambling note order.
  func testMonthSectionsGroupByMonth() {
    let april2 = makeDailyNote(year: 2026, month: 4, day: 2, title: "April 2")
    let april1 = makeDailyNote(year: 2026, month: 4, day: 1, title: "April 1")
    let march31 = makeDailyNote(year: 2026, month: 3, day: 31, title: "March 31")
    let store = makeStore(previewNotes: [april2, april1, march31])

    let sections = store.monthSections

    XCTAssertEqual(sections.count, 2)
    XCTAssertEqual(sections[0].notes.map(\.id), [april2.id, april1.id])
    XCTAssertEqual(sections[1].notes.map(\.id), [march31.id])
  }

  // Prevents hidden section directives from polluting daily search matches.
  func testSearchableBodyStripsSectionDirectives() {
    let body = "<!-- section bullet:blue usesectioncolor:true -->\nVisible text"

    XCTAssertEqual(NotesStore.searchableBody(body), "\nVisible text")
  }

  // Prevents clearing search from leaving the expanded search UI stuck open.
  func testClearSearchResetsTextAndCollapsedState() {
    let store = makeStore(previewNotes: [makeDailyNote(year: 2026, month: 4, day: 1)])
    store.searchText = "query"
    store.isSearchBarExpanded = true

    store.clearSearch()

    XCTAssertEqual(store.searchText, "")
    XCTAssertFalse(store.isSearchBarExpanded)
  }

  // Prevents calendar taps on missing days from failing to create/select a new daily note.
  func testOpenDailyDateCreatesMissingNoteAndSelectsIt() {
    let existing = makeDailyNote(year: 2026, month: 4, day: 3, title: "Existing")
    let targetDate = makeDate(year: 2025, month: 2, day: 14)
    let store = makeStore(previewNotes: [existing])

    store.openDailyDate(targetDate)

    let createdID = NoteDateFormatters.storageDate.string(from: targetDate)
    XCTAssertEqual(store.selectedNoteID, createdID)
    XCTAssertEqual(store.dailyNote(on: targetDate)?.id, createdID)
    XCTAssertEqual(store.notes.count, 2)
    XCTAssertEqual(store.calendarBrowseYear, 2025)
  }

  // Prevents calendar taps on existing days from creating duplicate notes.
  func testOpenDailyDateSelectsExistingNoteWithoutCreatingDuplicate() {
    let existing = makeDailyNote(year: 2025, month: 2, day: 14, title: "Saved")
    let store = makeStore(previewNotes: [existing])

    store.openDailyDate(existing.date)

    XCTAssertEqual(store.selectedNoteID, existing.id)
    XCTAssertEqual(store.notes.count, 1)
    XCTAssertEqual(store.calendarBrowseYear, 2025)
  }

  // Prevents the calendar year browser from excluding the current year when all notes are older.
  func testCalendarYearBoundsIncludeCurrentYear() {
    let currentYear = Calendar.current.component(.year, from: .now)
    let store = makeStore(previewNotes: [makeDailyNote(year: 2021, month: 1, day: 1)])

    XCTAssertEqual(store.calendarYearBounds.lowerBound, 2021)
    XCTAssertEqual(store.calendarYearBounds.upperBound, currentYear)
  }
}
