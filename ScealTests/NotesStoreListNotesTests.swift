import Foundation
import XCTest

@testable import Sceal

@MainActor
final class NotesStoreListNotesTests: NotesStoreTestCase {
  // Prevents failed group drops from removing a note from its current manifest location.
  func testMovingUngroupedNoteToMissingGroupPreservesManifest() {
    let note = makeListNote(id: "2026-05-10-aaaaaa", year: 2026, month: 5, day: 10)
    let group = NoteGroup(name: "Work")
    let manifest = ListNotesManifest(ungroupedNoteIDs: [note.id], groups: [group])
    let store = makeStore()
    store.listNotes = [note]
    store.rebuildListNoteIndex()
    store.listNoteManifest = manifest

    store.moveNoteToGroup(noteID: note.id, groupID: "missing-group")

    XCTAssertEqual(store.listNoteManifest, manifest)
  }

  // Prevents indexed group drops from mutating the manifest before destination validation.
  func testMovingGroupedNoteToMissingGroupAtIndexPreservesManifest() {
    let note = makeListNote(id: "2026-05-10-bbbbbb", year: 2026, month: 5, day: 10)
    let group = NoteGroup(name: "Work", noteIDs: [note.id])
    let manifest = ListNotesManifest(ungroupedNoteIDs: [], groups: [group])
    let store = makeStore()
    store.listNotes = [note]
    store.rebuildListNoteIndex()
    store.listNoteManifest = manifest

    store.moveNoteToGroup(noteID: note.id, groupID: "missing-group", atIndex: 0)

    XCTAssertEqual(store.listNoteManifest, manifest)
  }

  // Keeps new list-note IDs from reusing an existing date/suffix pair.
  func testListNoteIDGeneratorRetriesCollidingSuffix() {
    var suffixes = ["aaaaaa", "bbbbbb"]
    let noteID = ListNoteIDGenerator.makeID(
      for: makeDate(year: 2026, month: 5, day: 10),
      existingIDs: ["2026-05-10-aaaaaa"]
    ) {
      suffixes.removeFirst()
    }

    XCTAssertEqual(noteID, "2026-05-10-bbbbbb")
  }
}
