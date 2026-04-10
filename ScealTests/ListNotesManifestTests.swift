import XCTest

@testable import Sceal

final class ListNotesManifestTests: XCTestCase {
  // Prevents empty list-note state from being reported as non-empty.
  func testEmptyManifestIsEmpty() {
    XCTAssertTrue(ListNotesManifest.empty.isEmpty)
  }

  // Prevents group-held notes from being ignored when checking for content.
  func testManifestWithGroupNotesIsNotEmpty() {
    let manifest = ListNotesManifest(
      ungroupedNoteIDs: [],
      groups: [NoteGroup(name: "Work", noteIDs: ["note-1"])]
    )

    XCTAssertFalse(manifest.isEmpty)
  }

  // Prevents grouped and ungrouped notes from falling out of the tracked ID set.
  func testAllNoteIDsIncludesUngroupedAndGroupedNotes() {
    let manifest = ListNotesManifest(
      ungroupedNoteIDs: ["note-1"],
      groups: [NoteGroup(name: "Work", noteIDs: ["note-2", "note-3"])]
    )

    XCTAssertEqual(manifest.allNoteIDs, Set(["note-1", "note-2", "note-3"]))
  }

  // Prevents note removal from leaving duplicates behind in another section.
  func testRemoveNoteIDRemovesEveryOccurrence() {
    var manifest = ListNotesManifest(
      ungroupedNoteIDs: ["note-1", "note-2"],
      groups: [
        NoteGroup(name: "Work", noteIDs: ["note-2", "note-3"]),
        NoteGroup(name: "Home", noteIDs: ["note-2"]),
      ]
    )

    manifest.removeNoteID("note-2")

    XCTAssertEqual(manifest.ungroupedNoteIDs, ["note-1"])
    XCTAssertEqual(manifest.groups[0].noteIDs, ["note-3"])
    XCTAssertTrue(manifest.groups[1].noteIDs.isEmpty)
  }
}
