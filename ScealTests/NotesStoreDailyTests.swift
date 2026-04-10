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
}
