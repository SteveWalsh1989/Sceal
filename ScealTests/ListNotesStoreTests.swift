import Foundation
import XCTest

@testable import Sceal

@MainActor
final class ListNotesStoreTests: NotesStoreTestCase {
  // Keeps list-note lookup behavior stable after moving state out of NotesStore.
  func testReplacingNotesRebuildsLookupIndex() {
    let first = makeListNote(id: "2026-05-10-aaaaaa", year: 2026, month: 5, day: 10)
    let second = makeListNote(id: "2026-05-11-bbbbbb", year: 2026, month: 5, day: 11)
    let store = ListNotesStore(notes: [first])

    XCTAssertEqual(store.note(withID: first.id)?.id, first.id)

    store.replaceNotes([second])

    XCTAssertNil(store.note(withID: first.id))
    XCTAssertEqual(store.note(withID: second.id)?.id, second.id)
  }

  // Keeps manifest, selection, and search state together in the list-note feature store.
  func testUpdatesListModeState() {
    let manifest = ListNotesManifest(
      ungroupedNoteIDs: ["2026-05-10-aaaaaa"],
      groups: [NoteGroup(name: "Work", noteIDs: ["2026-05-11-bbbbbb"])]
    )
    let store = ListNotesStore()

    store.replaceManifest(manifest)
    store.selectNote("2026-05-10-aaaaaa")
    store.updateSearchText("meeting")
    store.updateSearchBarExpanded(true)

    XCTAssertEqual(store.manifest, manifest)
    XCTAssertEqual(store.selectedNoteID, "2026-05-10-aaaaaa")
    XCTAssertEqual(store.searchText, "meeting")
    XCTAssertTrue(store.isSearchBarExpanded)
  }
}
