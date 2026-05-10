//
//  ListNotesStore.swift
//

// Feature store for list-note state, manifest state, and fast note lookup.

import Combine
import Foundation

@MainActor
final class ListNotesStore: ObservableObject {
  @Published private(set) var notes: [DayNote]
  @Published private(set) var manifest: ListNotesManifest
  @Published private(set) var selectedNoteID: DayNote.ID?
  @Published private(set) var searchText: String
  @Published private(set) var isSearchBarExpanded: Bool

  private var noteIndex: [DayNote.ID: Int]

  init(
    notes: [DayNote] = [],
    manifest: ListNotesManifest = .empty,
    selectedNoteID: DayNote.ID? = nil,
    searchText: String = "",
    isSearchBarExpanded: Bool = false
  ) {
    self.notes = notes
    self.manifest = manifest
    self.selectedNoteID = selectedNoteID
    self.searchText = searchText
    self.isSearchBarExpanded = isSearchBarExpanded
    self.noteIndex = Dictionary(uniqueKeysWithValues: notes.enumerated().map { ($1.id, $0) })
  }

  // Replaces list notes and refreshes the lookup index.
  func replaceNotes(_ notes: [DayNote]) {
    self.notes = notes
    rebuildNoteIndex()
  }

  // Replaces the saved list-note grouping manifest.
  func replaceManifest(_ manifest: ListNotesManifest) {
    self.manifest = manifest
  }

  // Updates the selected list note ID.
  func selectNote(_ noteID: DayNote.ID?) {
    selectedNoteID = noteID
  }

  // Updates list-mode search text.
  func updateSearchText(_ text: String) {
    searchText = text
  }

  // Updates whether the list-mode search field is expanded.
  func updateSearchBarExpanded(_ isExpanded: Bool) {
    isSearchBarExpanded = isExpanded
  }

  // Rebuilds the note ID-to-index lookup for fast access.
  func rebuildNoteIndex() {
    noteIndex = Dictionary(uniqueKeysWithValues: notes.enumerated().map { ($1.id, $0) })
  }

  // Looks up a list note by ID using the fast index, falling back to linear search.
  func note(withID noteID: DayNote.ID) -> DayNote? {
    if let index = noteIndex[noteID], notes.indices.contains(index), notes[index].id == noteID {
      return notes[index]
    }

    return notes.first(where: { $0.id == noteID })
  }
}
