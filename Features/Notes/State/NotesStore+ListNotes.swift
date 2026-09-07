//
//  NotesStore+ListNotes.swift
//

// NotesStore extension for list note CRUD, group management, search, and navigation.

import Foundation
import SwiftUI

// MARK: - List Notes

extension NotesStore {
  // Writes the current manifest to disk.
  func saveManifest() {
    saveActiveListManifest()
  }

  // Looks up a list note by ID.
  func listNote(withID noteID: DayNote.ID) -> DayNote? {
    structuredListNoteSummaries.first(where: { $0.id == noteID })
  }

  // MARK: - CRUD

  // Generates a unique ID for a new list note (date + 6-char hex suffix).
  func generateListNoteID(for date: Date = .now) -> String {
    let datePrefix = NoteDateFormatters.storageDate.string(from: date)
    let hexChars = "abcdef0123456789"
    let suffix = String((0..<6).map { _ in hexChars.randomElement()! })
    return "\(datePrefix)-\(suffix)"
  }

  // Creates a new blank list note, saves it, and selects it.
  func createListNote() {
    let now = calendar.startOfDay(for: .now)
    let noteID = generateListNoteID(for: now)
    createStructuredListNote(id: noteID, date: now)
  }

  // Deletes a list note from disk and the manifest.
  func deleteListNote(noteID: DayNote.ID) {
    deleteStructuredListNote(noteID: noteID)
  }

  // Returns note IDs in display order: ungrouped first, then each group's notes.
  private func flattenedListNoteIDs() -> [String] {
    activeListNoteManifest.flattenedNoteIDs(includingCollapsedGroups: false)
  }

  // MARK: - Group Management

  // Creates a new named group and saves the manifest.
  func createGroup(name: String) {
    let group = NoteGroup(name: name)
    activeListNoteManifest.groups.append(group)
    saveManifest()
  }

  // Renames an existing group.
  func renameGroup(groupID: String, name: String) {
    guard let index = activeListNoteManifest.groups.firstIndex(where: { $0.id == groupID }) else {
      return
    }
    activeListNoteManifest.groups[index].name = name
    saveManifest()
  }

  // Deletes a group, moving its notes to ungrouped.
  func deleteGroup(groupID: String) {
    guard let index = activeListNoteManifest.groups.firstIndex(where: { $0.id == groupID }) else {
      return
    }
    let orphanedNoteIDs = activeListNoteManifest.groups[index].noteIDs
    activeListNoteManifest.groups.remove(at: index)
    activeListNoteManifest.ungroupedNoteIDs.append(contentsOf: orphanedNoteIDs)
    saveManifest()
  }

  // Moves a note into a specific group.
  func moveNoteToGroup(noteID: String, groupID: String) {
    activeListNoteManifest.removeNoteID(noteID)
    guard let groupIndex = activeListNoteManifest.groups.firstIndex(where: { $0.id == groupID })
    else {
      return
    }
    activeListNoteManifest.groups[groupIndex].noteIDs.append(noteID)
    saveManifest()
  }

  // Moves a note out of its group to the ungrouped section.
  func moveNoteToUngrouped(noteID: String) {
    activeListNoteManifest.removeNoteID(noteID)
    activeListNoteManifest.ungroupedNoteIDs.insert(noteID, at: 0)
    saveManifest()
  }

  // Toggles the collapsed state of a group in the sidebar.
  func toggleGroupCollapsed(groupID: String) {
    guard let index = activeListNoteManifest.groups.firstIndex(where: { $0.id == groupID }) else {
      return
    }
    activeListNoteManifest.groups[index].isCollapsed.toggle()
    saveManifest()
  }

  // MARK: - Reordering

  // Moves a note to a specific index within the ungrouped list.
  func moveNoteToUngrouped(noteID: String, atIndex index: Int) {
    activeListNoteManifest.removeNoteID(noteID)
    let clampedIndex = min(index, activeListNoteManifest.ungroupedNoteIDs.count)
    activeListNoteManifest.ungroupedNoteIDs.insert(noteID, at: clampedIndex)
    saveManifest()
  }

  // Moves a note to a specific index within a group.
  func moveNoteToGroup(noteID: String, groupID: String, atIndex index: Int) {
    activeListNoteManifest.removeNoteID(noteID)
    guard let groupIndex = activeListNoteManifest.groups.firstIndex(where: { $0.id == groupID })
    else {
      return
    }
    let clampedIndex = min(index, activeListNoteManifest.groups[groupIndex].noteIDs.count)
    activeListNoteManifest.groups[groupIndex].noteIDs.insert(noteID, at: clampedIndex)
    saveManifest()
  }

  // Moves a group to a new position in the groups array.
  func reorderGroup(groupID: String, toIndex targetIndex: Int) {
    guard let sourceIndex = activeListNoteManifest.groups.firstIndex(where: { $0.id == groupID })
    else {
      return
    }
    let group = activeListNoteManifest.groups.remove(at: sourceIndex)
    let clampedIndex = min(targetIndex, activeListNoteManifest.groups.count)
    activeListNoteManifest.groups.insert(group, at: clampedIndex)
    saveManifest()
  }

  // MARK: - Search

  // Notes filtered by the list-mode search text.
  var filteredListNotes: [DayNote] {
    let query = listSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return activeListNoteSummaries }
    return activeListNoteSummaries.filter { note in
      note.title.localizedCaseInsensitiveContains(query)
        || note.tags.contains(where: { $0.localizedCaseInsensitiveContains(query) })
        || Self.searchableBody(note.body).localizedCaseInsensitiveContains(query)
    }
  }

  // Whether list search is active.
  var isListSearchActive: Bool {
    !listSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  // MARK: - Navigation

  // Selects the next list note in flattened display order.
  func selectNextListNote() {
    guard let currentID = activeListSelectedNoteID else { return }
    let order = flattenedListNoteIDs()
    guard let idx = order.firstIndex(of: currentID), idx > 0 else { return }
    activeListSelectedNoteID = order[idx - 1]
  }

  // Selects the previous list note in flattened display order.
  func selectPreviousListNote() {
    guard let currentID = activeListSelectedNoteID else { return }
    let order = flattenedListNoteIDs()
    guard let idx = order.firstIndex(of: currentID), idx + 1 < order.count else { return }
    activeListSelectedNoteID = order[idx + 1]
  }

  // MARK: - Active Mode Helpers

  private var activeNoteRoute: ActiveNoteRoute {
    ActiveNoteRouting.route(for: sidebarMode)
  }

  // The selected note ID for the current sidebar mode.
  var activeSelectedNoteID: DayNote.ID? {
    ActiveNoteRouting.selectedNoteID(
      route: activeNoteRoute,
      dailyNoteID: activeDailySelectedNoteID,
      listNoteID: activeListSelectedNoteID
    )
  }

  // Two-way binding for the active mode's search text.
  var activeSearchTextBinding: Binding<String> {
    switch activeNoteRoute {
    case .daily:
      return Binding(
        get: { self.activeDailySearchText },
        set: { self.updateStructuredSearchText($0) }
      )
    case .list:
      return Binding(
        get: { self.listSearchText },
        set: { self.listSearchText = $0 }
      )
    }
  }

  // Two-way binding for the active search bar expanded state.
  var activeSearchBarExpandedBinding: Binding<Bool> {
    switch activeNoteRoute {
    case .daily:
      return Binding(
        get: { self.activeDailySearchBarExpanded },
        set: { self.updateStructuredSearchBarExpanded($0) }
      )
    case .list:
      return Binding(
        get: { self.isListSearchBarExpanded },
        set: { self.isListSearchBarExpanded = $0 }
      )
    }
  }

}
