import SwiftUI
import XCTest

@testable import Sceal

@MainActor
final class NotesStoreModeTests: NotesStoreTestCase {
  // Prevents stale daily search text from leaking into list mode.
  func testSwitchingToListClearsDailySearch() {
    let store = makeStore(previewNotes: [makeDailyNote(year: 2026, month: 4, day: 1)])
    store.searchText = "daily"
    store.isSearchBarExpanded = true

    store.sidebarMode = .list

    XCTAssertEqual(store.searchText, "")
    XCTAssertFalse(store.isSearchBarExpanded)
  }

  // Prevents stale list search text from leaking back into daily mode.
  func testSwitchingToDailyClearsListSearch() {
    let store = makeStore(previewNotes: [makeDailyNote(year: 2026, month: 4, day: 1)])
    store.sidebarMode = .list
    store.listSearchText = "list"
    store.isListSearchBarExpanded = true

    store.sidebarMode = .daily

    XCTAssertEqual(store.listSearchText, "")
    XCTAssertFalse(store.isListSearchBarExpanded)
  }

  // Prevents daily search state from being reset when switching between the two daily-note views.
  func testSwitchingBetweenDailyAndCalendarPreservesDailySearch() {
    let store = makeStore(previewNotes: [makeDailyNote(year: 2026, month: 4, day: 1)])
    store.searchText = "daily"
    store.isSearchBarExpanded = true

    store.sidebarMode = .calendar

    XCTAssertEqual(store.searchText, "daily")
    XCTAssertTrue(store.isSearchBarExpanded)

    store.sidebarMode = .daily

    XCTAssertEqual(store.searchText, "daily")
    XCTAssertTrue(store.isSearchBarExpanded)
  }

  // Prevents active selection routing from pointing the editor at the wrong daily note.
  func testActiveSelectedNoteIDUsesDailySelection() {
    let note = makeDailyNote(year: 2026, month: 4, day: 1)
    let store = makeStore(previewNotes: [note])

    store.sidebarMode = .daily
    store.selectedNoteID = note.id

    XCTAssertEqual(store.activeSelectedNoteID, note.id)
  }

  // Prevents calendar mode from routing the editor away from the selected daily note.
  func testActiveSelectedNoteIDUsesCalendarSelection() {
    let note = makeDailyNote(year: 2025, month: 2, day: 14)
    let store = makeStore(previewNotes: [note])

    store.sidebarMode = .calendar
    store.selectedNoteID = note.id

    XCTAssertEqual(store.activeSelectedNoteID, note.id)
  }

  // Prevents active selection routing from pointing the editor at the wrong list note.
  func testActiveSelectedNoteIDUsesListSelection() {
    let store = makeStore(previewNotes: [makeDailyNote(year: 2026, month: 4, day: 1)])
    let listNote = makeListNote(id: "2026-04-01-aaaaaa", year: 2026, month: 4, day: 1)
    store.listNotes = [listNote]
    store.rebuildListNoteIndex()
    store.sidebarMode = .list
    store.selectedListNoteID = listNote.id

    XCTAssertEqual(store.activeSelectedNoteID, listNote.id)
  }

  // Prevents the editor from resolving the wrong note when daily mode is active.
  func testActiveNoteUsesDailySelection() {
    let note = makeDailyNote(year: 2026, month: 4, day: 1, title: "Daily")
    let store = makeStore(previewNotes: [note])

    store.sidebarMode = .daily
    store.selectedNoteID = note.id

    XCTAssertEqual(store.activeNote?.id, note.id)
  }

  // Prevents the calendar sidebar from resolving the wrong daily note in the editor.
  func testActiveNoteUsesCalendarSelection() {
    let note = makeDailyNote(year: 2025, month: 2, day: 14, title: "Calendar")
    let store = makeStore(previewNotes: [note])

    store.sidebarMode = .calendar
    store.selectedNoteID = note.id

    XCTAssertEqual(store.activeNote?.id, note.id)
  }

  // Prevents the editor from resolving the wrong note when list mode is active.
  func testActiveNoteUsesListSelection() {
    let store = makeStore(previewNotes: [makeDailyNote(year: 2026, month: 4, day: 1)])
    let listNote = makeListNote(
      id: "2026-04-01-bbbbbb", year: 2026, month: 4, day: 1, title: "List")
    store.listNotes = [listNote]
    store.rebuildListNoteIndex()
    store.sidebarMode = .list
    store.selectedListNoteID = listNote.id

    XCTAssertEqual(store.activeNote?.id, listNote.id)
  }

  // Prevents the shared search bar from writing into the wrong daily search state.
  func testActiveSearchTextBindingUsesDailySearch() {
    let store = makeStore(previewNotes: [makeDailyNote(year: 2026, month: 4, day: 1)])

    store.sidebarMode = .daily
    store.activeSearchTextBinding.wrappedValue = "daily query"

    XCTAssertEqual(store.searchText, "daily query")
    XCTAssertEqual(store.activeSearchTextBinding.wrappedValue, "daily query")
  }

  // Prevents calendar mode from writing search text into the list-note search state.
  func testActiveSearchTextBindingUsesCalendarDailySearch() {
    let store = makeStore(previewNotes: [makeDailyNote(year: 2026, month: 4, day: 1)])

    store.sidebarMode = .calendar
    store.activeSearchTextBinding.wrappedValue = "calendar query"

    XCTAssertEqual(store.searchText, "calendar query")
    XCTAssertEqual(store.activeSearchTextBinding.wrappedValue, "calendar query")
  }

  // Prevents the shared search bar from writing into the wrong list search state.
  func testActiveSearchTextBindingUsesListSearch() {
    let store = makeStore(previewNotes: [makeDailyNote(year: 2026, month: 4, day: 1)])

    store.sidebarMode = .list
    store.activeSearchTextBinding.wrappedValue = "list query"

    XCTAssertEqual(store.listSearchText, "list query")
    XCTAssertEqual(store.activeSearchTextBinding.wrappedValue, "list query")
  }

  // Prevents list search from ignoring title, tag, or body matches.
  func testListSearchMatchesTitleTagsAndBody() {
    let titleNote = makeListNote(
      id: "2026-04-01-aaaaaa", year: 2026, month: 4, day: 1, title: "Alpha")
    let tagNote = makeListNote(
      id: "2026-04-01-bbbbbb", year: 2026, month: 4, day: 1, tags: ["beta"])
    let bodyNote = makeListNote(
      id: "2026-04-01-cccccc", year: 2026, month: 4, day: 1, body: "gamma")
    let store = makeStore(previewNotes: [makeDailyNote(year: 2026, month: 4, day: 1)])
    store.listNotes = [titleNote, tagNote, bodyNote]
    store.rebuildListNoteIndex()

    store.listSearchText = "beta"
    XCTAssertEqual(store.filteredListNotes.map(\.id), [tagNote.id])

    store.listSearchText = "gamma"
    XCTAssertEqual(store.filteredListNotes.map(\.id), [bodyNote.id])

    store.listSearchText = "Alpha"
    XCTAssertEqual(store.filteredListNotes.map(\.id), [titleNote.id])
  }

  // Prevents list search from matching hidden section directive markup.
  func testListSearchIgnoresSectionDirectiveMarkup() {
    let listNote = makeListNote(
      id: "2026-04-01-aaaaaa",
      year: 2026,
      month: 4,
      day: 1,
      body: "<!-- section bullet:blue usesectioncolor:true -->\nVisible text"
    )
    let store = makeStore(previewNotes: [makeDailyNote(year: 2026, month: 4, day: 1)])
    store.listNotes = [listNote]
    store.rebuildListNoteIndex()

    store.listSearchText = "bullet:blue"
    XCTAssertTrue(store.filteredListNotes.isEmpty)

    store.listSearchText = "Visible"
    XCTAssertEqual(store.filteredListNotes.map(\.id), [listNote.id])
  }

  // Prevents list keyboard navigation from using storage order instead of visible order.
  func testSelectNextListNoteUsesVisibleOrder() {
    let first = makeListNote(id: "2026-04-02-aaaaaa", year: 2026, month: 4, day: 2)
    let second = makeListNote(id: "2026-04-01-bbbbbb", year: 2026, month: 4, day: 1)
    let third = makeListNote(id: "2026-03-31-cccccc", year: 2026, month: 3, day: 31)
    let store = makeStore(previewNotes: [makeDailyNote(year: 2026, month: 4, day: 2)])
    store.listNotes = [first, second, third]
    store.rebuildListNoteIndex()
    store.listNoteManifest = ListNotesManifest(
      ungroupedNoteIDs: [first.id],
      groups: [NoteGroup(name: "Work", noteIDs: [second.id, third.id])]
    )
    store.selectedListNoteID = second.id

    store.selectNextListNote()

    XCTAssertEqual(store.selectedListNoteID, first.id)
  }

  // Prevents list keyboard navigation from skipping the next visible note.
  func testSelectPreviousListNoteUsesVisibleOrder() {
    let first = makeListNote(id: "2026-04-02-aaaaaa", year: 2026, month: 4, day: 2)
    let second = makeListNote(id: "2026-04-01-bbbbbb", year: 2026, month: 4, day: 1)
    let third = makeListNote(id: "2026-03-31-cccccc", year: 2026, month: 3, day: 31)
    let store = makeStore(previewNotes: [makeDailyNote(year: 2026, month: 4, day: 2)])
    store.listNotes = [first, second, third]
    store.rebuildListNoteIndex()
    store.listNoteManifest = ListNotesManifest(
      ungroupedNoteIDs: [first.id],
      groups: [NoteGroup(name: "Work", noteIDs: [second.id, third.id])]
    )
    store.selectedListNoteID = second.id

    store.selectPreviousListNote()

    XCTAssertEqual(store.selectedListNoteID, third.id)
  }

  // Prevents collapsed groups from staying in keyboard navigation order.
  func testCollapsedGroupsAreSkippedByNavigation() {
    let first = makeListNote(id: "2026-04-02-aaaaaa", year: 2026, month: 4, day: 2)
    let second = makeListNote(id: "2026-04-01-bbbbbb", year: 2026, month: 4, day: 1)
    let hidden = makeListNote(id: "2026-03-31-cccccc", year: 2026, month: 3, day: 31)
    let store = makeStore(previewNotes: [makeDailyNote(year: 2026, month: 4, day: 2)])
    store.listNotes = [first, second, hidden]
    store.rebuildListNoteIndex()
    store.listNoteManifest = ListNotesManifest(
      ungroupedNoteIDs: [first.id, second.id],
      groups: [NoteGroup(name: "Hidden", noteIDs: [hidden.id], isCollapsed: true)]
    )
    store.selectedListNoteID = second.id

    store.selectPreviousListNote()

    XCTAssertEqual(store.selectedListNoteID, second.id)
  }
}
