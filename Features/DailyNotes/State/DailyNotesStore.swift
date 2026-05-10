//
//  DailyNotesStore.swift
//

// Feature store for daily-note state, selection, search, calendar browsing, and lookup.

import Combine
import Foundation

@MainActor
final class DailyNotesStore: ObservableObject {
  @Published private(set) var notes: [DayNote]
  @Published private(set) var selectedNoteID: DayNote.ID?
  @Published private(set) var searchText: String
  @Published private(set) var isSearchBarExpanded: Bool
  @Published private(set) var calendarBrowseYear: Int

  private var noteIndex: [DayNote.ID: Int]

  init(
    notes: [DayNote] = [],
    selectedNoteID: DayNote.ID? = nil,
    searchText: String = "",
    isSearchBarExpanded: Bool = false,
    calendarBrowseYear: Int
  ) {
    self.notes = notes
    self.selectedNoteID = selectedNoteID
    self.searchText = searchText
    self.isSearchBarExpanded = isSearchBarExpanded
    self.calendarBrowseYear = calendarBrowseYear
    self.noteIndex = Dictionary(uniqueKeysWithValues: notes.enumerated().map { ($1.id, $0) })
  }

  // Replaces daily notes and refreshes the lookup index.
  func replaceNotes(_ notes: [DayNote]) {
    self.notes = notes
    rebuildNoteIndex()
  }

  // Updates the selected daily note ID.
  func selectNote(_ noteID: DayNote.ID?) {
    selectedNoteID = noteID
  }

  // Updates daily-note search text.
  func updateSearchText(_ text: String) {
    searchText = text
  }

  // Updates whether the daily-note search field is expanded.
  func updateSearchBarExpanded(_ isExpanded: Bool) {
    isSearchBarExpanded = isExpanded
  }

  // Updates the visible calendar browser year.
  func updateCalendarBrowseYear(_ year: Int) {
    calendarBrowseYear = year
  }

  // Rebuilds the note ID-to-index lookup for fast access.
  func rebuildNoteIndex() {
    noteIndex = Dictionary(uniqueKeysWithValues: notes.enumerated().map { ($1.id, $0) })
  }

  // Looks up a daily note by ID using the fast index, falling back to linear search.
  func note(withID noteID: DayNote.ID) -> DayNote? {
    if let index = noteIndex[noteID], notes.indices.contains(index), notes[index].id == noteID {
      return notes[index]
    }

    return notes.first(where: { $0.id == noteID })
  }
}
