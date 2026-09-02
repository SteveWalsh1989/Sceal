//
//  NotesStore+ListNotes.swift
//

// NotesStore extension for list note CRUD, group management, search, and navigation.

import Foundation
import OSLog
import SwiftUI

// MARK: - List Notes

extension NotesStore {

  private static let listNotesLogger = Logger(subsystem: "com.sceal.app", category: "listNotes")

  // MARK: - Loading

  // Loads all list notes and the manifest from disk, reconciling any mismatches.
  func loadListNotesIfNeeded() {
    if isStructuredDailyNoteMode {
      do {
        try loadStructuredListNotesIfNeeded()
        Self.listNotesLogger.info("Loaded \(self.structuredListNotes.count) structured list notes")
      } catch {
        Self.listNotesLogger.error(
          "Loading structured list notes failed: \(error.localizedDescription)"
        )
        structuredListNotes = []
        structuredListNoteManifest = .empty
      }
      return
    }

    do {
      let snapshot = try libraryRepository.loadListNotes()
      listNotes = snapshot.notes
      rebuildListNoteIndex()
      listNoteManifest = snapshot.manifest
      Self.listNotesLogger.info("Loaded \(snapshot.notes.count) list notes")
    } catch {
      Self.listNotesLogger.error("Loading list notes failed: \(error.localizedDescription)")
      listNotes = []
      listNoteManifest = .empty
    }
  }

  // Writes the current manifest to disk.
  func saveManifest() {
    saveActiveListManifest()
  }

  // MARK: - Index

  // Rebuilds the list note ID-to-index lookup for fast access.
  func rebuildListNoteIndex() {
    listNotesStore.rebuildNoteIndex()
  }

  // Looks up a list note by ID using the fast index.
  func listNote(withID noteID: DayNote.ID) -> DayNote? {
    if isStructuredDailyNoteMode {
      return structuredListNoteSummaries.first(where: { $0.id == noteID })
    }
    return listNotesStore.note(withID: noteID)
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
    if isStructuredDailyNoteMode {
      createStructuredListNote(id: noteID, date: now)
      return
    }
    let note = DayNote(date: now, id: noteID, title: "", tags: [], body: "")

    listNotes.insert(note, at: 0)
    rebuildListNoteIndex()

    listNoteManifest.ungroupedNoteIDs.insert(noteID, at: 0)
    saveManifest()

    do {
      try saveListNote(note)
    } catch {
      report(error, context: "Creating list note failed")
    }

    selectedListNoteID = noteID
  }

  // Deletes a list note from disk and the manifest.
  func deleteListNote(noteID: DayNote.ID) {
    if isStructuredDailyNoteMode {
      deleteStructuredListNote(noteID: noteID)
      return
    }
    flushPendingListNoteSave(for: noteID)

    guard let note = listNote(withID: noteID) else { return }

    // Find the adjacent note for selection after delete.
    let flatOrder = flattenedListNoteIDs()
    let currentIndex = flatOrder.firstIndex(of: noteID)
    let nextSelection: DayNote.ID?
    if let idx = currentIndex {
      if idx + 1 < flatOrder.count {
        nextSelection = flatOrder[idx + 1]
      } else if idx > 0 {
        nextSelection = flatOrder[idx - 1]
      } else {
        nextSelection = nil
      }
    } else {
      nextSelection = nil
    }

    do {
      try libraryRepository.deleteListNoteFile(for: note)
      try libraryRepository.deleteAttachments(for: note.id)
    } catch {
      report(error, context: "Deleting list note failed")
      return
    }

    listNotes.removeAll { $0.id == noteID }
    rebuildListNoteIndex()

    listNoteManifest.removeNoteID(noteID)
    saveManifest()

    selectedListNoteID = nextSelection
  }

  // Writes a list note to disk.
  func saveListNote(_ note: DayNote) throws {
    try libraryRepository.saveListNote(note)
  }

  // Returns note IDs in display order: ungrouped first, then each group's notes.
  private func flattenedListNoteIDs() -> [String] {
    activeListNoteManifest.flattenedNoteIDs(includingCollapsedGroups: false)
  }

  // MARK: - Bindings

  // Two-way binding for a list note's title, with debounced save.
  func listNoteTitleBinding(for noteID: DayNote.ID) -> Binding<String> {
    Binding(
      get: { self.listNote(withID: noteID)?.title ?? "" },
      set: { self.updateListNote(noteID: noteID) { $0.title = $1 }($0) }
    )
  }

  // Two-way binding for a list note's tags, with debounced save.
  func listNoteTagsBinding(for noteID: DayNote.ID) -> Binding<String> {
    Binding(
      get: { self.listNote(withID: noteID)?.tags.joined(separator: ", ") ?? "" },
      set: { newValue in
        self.updateListNote(noteID: noteID) { note, _ in
          note.tags = newValue.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        }(newValue)
      }
    )
  }

  // Two-way binding for a list note's body, with debounced save.
  func listNoteBodyBinding(for noteID: DayNote.ID) -> Binding<String> {
    Binding(
      get: { self.listNote(withID: noteID)?.body ?? "" },
      set: { self.updateListNote(noteID: noteID) { $0.body = $1 }($0) }
    )
  }

  // Applies a mutation to a list note and schedules a debounced save.
  private func updateListNote(noteID: DayNote.ID, mutate: @escaping (inout DayNote, String) -> Void)
    -> (String) -> Void
  {
    return { [weak self] newValue in
      guard let self, let index = self.listNotes.firstIndex(where: { $0.id == noteID }) else {
        return
      }
      mutate(&self.listNotes[index], newValue)
      self.rebuildListNoteIndex()
      self.scheduleListNoteSave(for: noteID)
    }
  }

  // Debounces list note saves at 350ms, matching the daily note pattern.
  private func scheduleListNoteSave(for noteID: DayNote.ID) {
    pendingListNoteSaveTasks[noteID]?.cancel()
    pendingListNoteSaveTasks[noteID] = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 350_000_000)
      guard !Task.isCancelled else { return }
      self?.persistPendingListNoteSave(for: noteID)
    }
  }

  // Writes a single pending list note to disk.
  private func persistPendingListNoteSave(for noteID: DayNote.ID) {
    pendingListNoteSaveTasks[noteID] = nil
    guard let note = listNote(withID: noteID) else { return }
    do {
      try saveListNote(note)
    } catch {
      report(error, context: "Saving list note failed")
    }
  }

  // Cancels debounce and immediately writes a single list note.
  func flushPendingListNoteSave(for noteID: DayNote.ID) {
    let hadPending = pendingListNoteSaveTasks[noteID] != nil
    pendingListNoteSaveTasks[noteID]?.cancel()
    pendingListNoteSaveTasks[noteID] = nil
    guard hadPending, let note = listNote(withID: noteID) else { return }
    do {
      try saveListNote(note)
    } catch {
      report(error, context: "Flushing list note save failed")
    }
  }

  // Immediately writes all pending list note saves.
  func flushAllPendingListNoteSaves() {
    let noteIDs = Array(pendingListNoteSaveTasks.keys)
    for noteID in noteIDs {
      flushPendingListNoteSave(for: noteID)
    }
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
    ActiveNoteRouting.route(for: sidebarMode, isDemoModeEnabled: isDemoModeEnabled)
  }

  // The selected note ID for the current sidebar mode.
  var activeSelectedNoteID: DayNote.ID? {
    ActiveNoteRouting.selectedNoteID(
      route: activeNoteRoute,
      dailyNoteID: activeDailySelectedNoteID,
      listNoteID: activeListSelectedNoteID
    )
  }

  // The currently active note for the editor.
  var activeNote: DayNote? {
    guard let noteID = activeSelectedNoteID else { return nil }

    switch activeNoteRoute {
    case .daily:
      guard !isStructuredDailyNoteMode else { return nil }
      return note(withID: noteID)
    case .list: return listNote(withID: noteID)
    }
  }

  // Two-way binding for the active mode's search text.
  var activeSearchTextBinding: Binding<String> {
    switch activeNoteRoute {
    case .daily:
      return Binding(
        get: { self.activeDailySearchText },
        set: { value in
          if self.isStructuredDailyNoteMode {
            self.updateStructuredSearchText(value)
          } else {
            self.searchText = value
          }
        }
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
        set: { isExpanded in
          if self.isStructuredDailyNoteMode {
            self.updateStructuredSearchBarExpanded(isExpanded)
          } else {
            self.isSearchBarExpanded = isExpanded
          }
        }
      )
    case .list:
      return Binding(
        get: { self.isListSearchBarExpanded },
        set: { self.isListSearchBarExpanded = $0 }
      )
    }
  }

  // Title binding that routes to daily or list note by ID.
  func activeTitleBinding(for noteID: DayNote.ID) -> Binding<String> {
    switch activeNoteRoute {
    case .daily: return titleBinding(for: noteID)
    case .list: return listNoteTitleBinding(for: noteID)
    }
  }

  // Tags binding that routes to daily or list note by ID.
  func activeTagsBinding(for noteID: DayNote.ID) -> Binding<String> {
    switch activeNoteRoute {
    case .daily: return tagsBinding(for: noteID)
    case .list: return listNoteTagsBinding(for: noteID)
    }
  }

  // Body binding that routes to daily or list note by ID.
  func activeBodyBinding(for noteID: DayNote.ID) -> Binding<String> {
    switch activeNoteRoute {
    case .daily: return bodyBinding(for: noteID)
    case .list: return listNoteBodyBinding(for: noteID)
    }
  }
}
