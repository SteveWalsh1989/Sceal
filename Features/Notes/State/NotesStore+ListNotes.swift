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
  private static let manifestFileName = "groups.json"

  // MARK: - Directory Management

  // Returns the list notes directory, creating it if needed.
  func listNotesDirectoryURL() throws -> URL {
    let appSupportURL = try fileManager.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )

    let directoryURL =
      appSupportURL
      .appendingPathComponent("Sceal", isDirectory: true)
      .appendingPathComponent("ListNotes", isDirectory: true)

    try fileManager.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true
    )

    return directoryURL
  }

  // URL for the groups.json manifest file.
  private func manifestFileURL() throws -> URL {
    try listNotesDirectoryURL().appendingPathComponent(Self.manifestFileName)
  }

  // MARK: - Loading

  // Loads all list notes and the manifest from disk, reconciling any mismatches.
  func loadListNotesIfNeeded() {
    do {
      let directoryURL = try listNotesDirectoryURL()
      let fileURLs = try fileManager.contentsOfDirectory(
        at: directoryURL,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      )

      let loadedNotes =
        fileURLs
        .filter { $0.pathExtension == "md" }
        .compactMap { url -> DayNote? in
          do {
            let contents = try String(contentsOf: url, encoding: .utf8)
            let noteID = url.deletingPathExtension().lastPathComponent
            return try MarkdownNoteCodec.decode(
              contents: contents,
              sourceURL: url,
              idOverride: noteID
            )
          } catch {
            Self.listNotesLogger.error(
              "Skipping corrupt list note \(url.lastPathComponent): \(error.localizedDescription)"
            )
            return nil
          }
        }
        .sorted(by: { $0.date > $1.date })

      listNotes = loadedNotes
      rebuildListNoteIndex()

      var manifest = loadManifest()
      reconcileManifest(&manifest, with: Set(loadedNotes.map(\.id)))
      listNoteManifest = manifest
      saveManifest()

      Self.listNotesLogger.info("Loaded \(loadedNotes.count) list notes")
    } catch {
      Self.listNotesLogger.error("Loading list notes failed: \(error.localizedDescription)")
      listNotes = []
      listNoteManifest = .empty
    }
  }

  // Reads the manifest from disk, returning empty if missing or corrupt.
  private func loadManifest() -> ListNotesManifest {
    guard
      let url = try? manifestFileURL(),
      let data = try? Data(contentsOf: url),
      let manifest = try? JSONDecoder().decode(ListNotesManifest.self, from: data)
    else {
      return .empty
    }
    return manifest
  }

  // Writes the current manifest to disk.
  func saveManifest() {
    do {
      let url = try manifestFileURL()
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(listNoteManifest)
      try data.write(to: url, options: .atomic)
    } catch {
      report(error, context: "Saving list notes manifest failed")
    }
  }

  // Ensures the manifest matches the notes on disk — removes orphan IDs, adds untracked notes.
  private func reconcileManifest(
    _ manifest: inout ListNotesManifest, with noteIDsOnDisk: Set<String>
  ) {
    let trackedIDs = manifest.allNoteIDs

    // Remove IDs from manifest that have no matching file.
    let orphanIDs = trackedIDs.subtracting(noteIDsOnDisk)
    for orphanID in orphanIDs {
      manifest.removeNoteID(orphanID)
    }

    // Add untracked files to ungrouped.
    let untrackedIDs = noteIDsOnDisk.subtracting(trackedIDs)
    for untrackedID in untrackedIDs {
      manifest.ungroupedNoteIDs.insert(untrackedID, at: 0)
    }
  }

  // MARK: - Index

  // Rebuilds the list note ID-to-index lookup for fast access.
  func rebuildListNoteIndex() {
    listNoteIndex = Dictionary(uniqueKeysWithValues: listNotes.enumerated().map { ($1.id, $0) })
  }

  // Looks up a list note by ID using the fast index.
  func listNote(withID noteID: DayNote.ID) -> DayNote? {
    if let index = listNoteIndex[noteID], listNotes.indices.contains(index),
      listNotes[index].id == noteID
    {
      return listNotes[index]
    }
    return listNotes.first(where: { $0.id == noteID })
  }

  // MARK: - CRUD

  // Generates a unique ID for a new list note (date + 6-char hex suffix).
  private func generateListNoteID(for date: Date = .now) -> String {
    let datePrefix = NoteDateFormatters.storageDate.string(from: date)
    let hexChars = "abcdef0123456789"
    let suffix = String((0..<6).map { _ in hexChars.randomElement()! })
    return "\(datePrefix)-\(suffix)"
  }

  // Creates a new blank list note, saves it, and selects it.
  func createListNote() {
    let now = calendar.startOfDay(for: .now)
    let noteID = generateListNoteID(for: now)
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
      let noteURL = try listNotesDirectoryURL().appendingPathComponent(note.fileName)
      if fileManager.fileExists(atPath: noteURL.path) {
        try fileManager.removeItem(at: noteURL)
      }
      try NoteImageAttachmentStore.deleteAttachments(for: note.id, fileManager: fileManager)
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
    let noteURL = try listNotesDirectoryURL().appendingPathComponent(note.fileName)
    let fileContents = try MarkdownNoteCodec.encode(note)
    try fileContents.write(to: noteURL, atomically: true, encoding: .utf8)
  }

  // Returns note IDs in display order: ungrouped first, then each group's notes.
  private func flattenedListNoteIDs() -> [String] {
    var ids = listNoteManifest.ungroupedNoteIDs
    for group in listNoteManifest.groups where !group.isCollapsed {
      ids.append(contentsOf: group.noteIDs)
    }
    return ids
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
    listNoteManifest.groups.append(group)
    saveManifest()
  }

  // Renames an existing group.
  func renameGroup(groupID: String, name: String) {
    guard let index = listNoteManifest.groups.firstIndex(where: { $0.id == groupID }) else {
      return
    }
    listNoteManifest.groups[index].name = name
    saveManifest()
  }

  // Deletes a group, moving its notes to ungrouped.
  func deleteGroup(groupID: String) {
    guard let index = listNoteManifest.groups.firstIndex(where: { $0.id == groupID }) else {
      return
    }
    let orphanedNoteIDs = listNoteManifest.groups[index].noteIDs
    listNoteManifest.groups.remove(at: index)
    listNoteManifest.ungroupedNoteIDs.append(contentsOf: orphanedNoteIDs)
    saveManifest()
  }

  // Moves a note into a specific group.
  func moveNoteToGroup(noteID: String, groupID: String) {
    listNoteManifest.removeNoteID(noteID)
    guard let groupIndex = listNoteManifest.groups.firstIndex(where: { $0.id == groupID }) else {
      return
    }
    listNoteManifest.groups[groupIndex].noteIDs.append(noteID)
    saveManifest()
  }

  // Moves a note out of its group to the ungrouped section.
  func moveNoteToUngrouped(noteID: String) {
    listNoteManifest.removeNoteID(noteID)
    listNoteManifest.ungroupedNoteIDs.insert(noteID, at: 0)
    saveManifest()
  }

  // Toggles the collapsed state of a group in the sidebar.
  func toggleGroupCollapsed(groupID: String) {
    guard let index = listNoteManifest.groups.firstIndex(where: { $0.id == groupID }) else {
      return
    }
    listNoteManifest.groups[index].isCollapsed.toggle()
    saveManifest()
  }

  // MARK: - Reordering

  // Moves a note to a specific index within the ungrouped list.
  func moveNoteToUngrouped(noteID: String, atIndex index: Int) {
    listNoteManifest.removeNoteID(noteID)
    let clampedIndex = min(index, listNoteManifest.ungroupedNoteIDs.count)
    listNoteManifest.ungroupedNoteIDs.insert(noteID, at: clampedIndex)
    saveManifest()
  }

  // Moves a note to a specific index within a group.
  func moveNoteToGroup(noteID: String, groupID: String, atIndex index: Int) {
    listNoteManifest.removeNoteID(noteID)
    guard let groupIndex = listNoteManifest.groups.firstIndex(where: { $0.id == groupID }) else {
      return
    }
    let clampedIndex = min(index, listNoteManifest.groups[groupIndex].noteIDs.count)
    listNoteManifest.groups[groupIndex].noteIDs.insert(noteID, at: clampedIndex)
    saveManifest()
  }

  // Moves a group to a new position in the groups array.
  func reorderGroup(groupID: String, toIndex targetIndex: Int) {
    guard let sourceIndex = listNoteManifest.groups.firstIndex(where: { $0.id == groupID }) else {
      return
    }
    let group = listNoteManifest.groups.remove(at: sourceIndex)
    let clampedIndex = min(targetIndex, listNoteManifest.groups.count)
    listNoteManifest.groups.insert(group, at: clampedIndex)
    saveManifest()
  }

  // MARK: - Search

  // Notes filtered by the list-mode search text.
  var filteredListNotes: [DayNote] {
    let query = listSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return listNotes }
    return listNotes.filter { note in
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
    guard let currentID = selectedListNoteID else { return }
    let order = flattenedListNoteIDs()
    guard let idx = order.firstIndex(of: currentID), idx > 0 else { return }
    selectedListNoteID = order[idx - 1]
  }

  // Selects the previous list note in flattened display order.
  func selectPreviousListNote() {
    guard let currentID = selectedListNoteID else { return }
    let order = flattenedListNoteIDs()
    guard let idx = order.firstIndex(of: currentID), idx + 1 < order.count else { return }
    selectedListNoteID = order[idx + 1]
  }

  // MARK: - Active Mode Helpers

  // The selected note ID for the current sidebar mode.
  var activeSelectedNoteID: DayNote.ID? {
    #if DEBUG
      if isDemoModeEnabled {
        return selectedNoteID
      }
    #endif

    switch sidebarMode {
    case .calendar, .daily: return selectedNoteID
    case .list: return selectedListNoteID
    }
  }

  // The currently active note for the editor.
  var activeNote: DayNote? {
    guard let noteID = activeSelectedNoteID else { return nil }
    #if DEBUG
      if isDemoModeEnabled {
        return note(withID: noteID)
      }
    #endif

    switch sidebarMode {
    case .calendar, .daily: return note(withID: noteID)
    case .list: return listNote(withID: noteID)
    }
  }

  // Two-way binding for the active mode's search text.
  var activeSearchTextBinding: Binding<String> {
    #if DEBUG
      if isDemoModeEnabled {
        return Binding(
          get: { self.searchText },
          set: { self.searchText = $0 }
        )
      }
    #endif

    switch sidebarMode {
    case .calendar, .daily:
      return Binding(
        get: { self.searchText },
        set: { self.searchText = $0 }
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
    #if DEBUG
      if isDemoModeEnabled {
        return Binding(
          get: { self.isSearchBarExpanded },
          set: { self.isSearchBarExpanded = $0 }
        )
      }
    #endif

    switch sidebarMode {
    case .calendar, .daily:
      return Binding(
        get: { self.isSearchBarExpanded },
        set: { self.isSearchBarExpanded = $0 }
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
    #if DEBUG
      if isDemoModeEnabled {
        return titleBinding(for: noteID)
      }
    #endif

    switch sidebarMode {
    case .calendar, .daily: return titleBinding(for: noteID)
    case .list: return listNoteTitleBinding(for: noteID)
    }
  }

  // Tags binding that routes to daily or list note by ID.
  func activeTagsBinding(for noteID: DayNote.ID) -> Binding<String> {
    #if DEBUG
      if isDemoModeEnabled {
        return tagsBinding(for: noteID)
      }
    #endif

    switch sidebarMode {
    case .calendar, .daily: return tagsBinding(for: noteID)
    case .list: return listNoteTagsBinding(for: noteID)
    }
  }

  // Body binding that routes to daily or list note by ID.
  func activeBodyBinding(for noteID: DayNote.ID) -> Binding<String> {
    #if DEBUG
      if isDemoModeEnabled {
        return bodyBinding(for: noteID)
      }
    #endif

    switch sidebarMode {
    case .calendar, .daily: return bodyBinding(for: noteID)
    case .list: return listNoteBodyBinding(for: noteID)
    }
  }
}
