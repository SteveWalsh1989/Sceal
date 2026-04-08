//
//  ListNotesManifest.swift
//

// Tracks ordering and group membership for list notes, persisted as groups.json.

import Foundation

struct ListNotesManifest: Codable, Equatable, Sendable {
  var ungroupedNoteIDs: [String]
  var groups: [NoteGroup]

  static let empty = ListNotesManifest(ungroupedNoteIDs: [], groups: [])

  // Returns true when there are no notes in any location.
  var isEmpty: Bool {
    ungroupedNoteIDs.isEmpty && groups.allSatisfy { $0.noteIDs.isEmpty }
  }

  // All note IDs across ungrouped and all groups.
  var allNoteIDs: Set<String> {
    var ids = Set(ungroupedNoteIDs)
    for group in groups {
      ids.formUnion(group.noteIDs)
    }
    return ids
  }

  // Removes a note ID from wherever it appears (ungrouped or any group).
  mutating func removeNoteID(_ noteID: String) {
    ungroupedNoteIDs.removeAll { $0 == noteID }
    for index in groups.indices {
      groups[index].noteIDs.removeAll { $0 == noteID }
    }
  }
}
