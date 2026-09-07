//
//  NotesStore+StructuredListNotes.swift
//

// Isolated structured list-note state, persistence, migration, and sidebar summaries.

import Foundation

extension NotesStore {
  var selectedStructuredListNote: StructuredNoteDocument? {
    guard let selectedStructuredListNoteID else { return nil }
    return structuredListNotes.first(where: { $0.id == selectedStructuredListNoteID })
  }

  var structuredListNoteSummaries: [DayNote] {
    structuredListNotes.map { document in
      DayNote(
        date: document.date,
        id: document.id,
        title: document.title,
        tags: document.tags,
        body: structuredSummaryBody(for: document)
      )
    }
  }

  var activeListNoteSummaries: [DayNote] {
    isStructuredDailyNoteMode ? structuredListNoteSummaries : listNotes
  }

  var activeListNoteManifest: ListNotesManifest {
    get { isStructuredDailyNoteMode ? structuredListNoteManifest : listNoteManifest }
    set {
      if isStructuredDailyNoteMode {
        structuredListNoteManifest = newValue
      } else {
        listNoteManifest = newValue
      }
    }
  }

  var activeListSelectedNoteID: DayNote.ID? {
    get { isStructuredDailyNoteMode ? selectedStructuredListNoteID : selectedListNoteID }
    set {
      if isStructuredDailyNoteMode {
        selectStructuredListNote(newValue)
      } else {
        selectedListNoteID = newValue
      }
    }
  }

  // Loads structured list documents and reconciles their independent sidebar manifest.
  func loadStructuredListNotesIfNeeded() throws {
    guard !hasLoadedStructuredListNotes else { return }
    let documents = try structuredListNoteRepository.loadDocuments()
    let manifest = try libraryRepository.loadStructuredListNotesManifest(
      noteIDs: Set(documents.map(\.id))
    )
    structuredListNotes = documents
    structuredListNoteManifest = manifest
    if !documents.contains(where: { $0.id == selectedStructuredListNoteID }) {
      selectedStructuredListNoteID =
        manifest.ungroupedNoteIDs.first
        ?? manifest.groups.lazy.compactMap { $0.noteIDs.first }.first
        ?? documents.first?.id
    }
    hasLoadedStructuredListNotes = true
  }

  // Copies legacy list notes and their top-level library grouping without changing either source.
  func copyLegacyListNotesToStructuredLibrary() throws -> StructuredNoteImportResult {
    guard !isPerformingFileOperation, !isBackupRunning else {
      throw LibraryOperationError.operationInProgress
    }
    try flushPendingSavesForLibraryOperation()
    let legacySnapshot = try libraryRepository.loadArchiveSourceSnapshot()
    let preparedDocuments = try structuredListNoteRepository.prepareLegacyDocuments()
    let existingDocuments = try structuredListNoteRepository.loadDocuments()
    var manifest = try libraryRepository.loadStructuredListNotesManifestForArchive(
      noteIDs: Set(existingDocuments.map(\.id))
    )
    let result = try structuredListNoteRepository.importPreparedDocuments(preparedDocuments)
    let importedIDs = Set(preparedDocuments.map(\.id)).subtracting(
      Set(existingDocuments.map(\.id))
    )
    manifest.appendImportedNotes(from: legacySnapshot.listManifest, importedIDs: importedIDs)
    try libraryRepository.saveStructuredListNotesManifest(manifest)
    hasLoadedStructuredListNotes = false
    try loadStructuredListNotesIfNeeded()
    return result
  }

  // Selects one structured list note while retaining the legacy list selection for rollback.
  func selectStructuredListNote(_ noteID: DayNote.ID?) {
    guard noteID == nil || structuredListNotes.contains(where: { $0.id == noteID }) else { return }
    if selectedStructuredListNoteID != noteID, let selectedStructuredListNoteID {
      flushPendingStructuredNoteSave(for: selectedStructuredListNoteID)
    }
    selectedStructuredListNoteID = noteID
  }

  // Creates and persists one blank structured list note with a stable list-note ID.
  func createStructuredListNote(id: String, date: Date) {
    let document = StructuredNoteDocument.empty(id: id, date: date)
    do {
      try structuredListNoteRepository.save(document)
      structuredListNotes.insert(document, at: 0)
      structuredListNoteManifest.ungroupedNoteIDs.insert(id, at: 0)
      try libraryRepository.saveStructuredListNotesManifest(structuredListNoteManifest)
      selectedStructuredListNoteID = id
    } catch {
      report(error, context: "Creating structured list note failed")
    }
  }

  // Deletes one structured list document while leaving any same-ID legacy attachment source intact.
  func deleteStructuredListNote(noteID: DayNote.ID) {
    flushPendingStructuredNoteSave(for: noteID)
    guard structuredListNotes.contains(where: { $0.id == noteID }) else { return }
    let order = structuredListNoteManifest.flattenedNoteIDs(includingCollapsedGroups: true)
    let adjacentID = order.adjacentSelection(afterRemoving: noteID)

    do {
      try structuredListNoteRepository.delete(documentID: noteID)
      structuredListNotes.removeAll(where: { $0.id == noteID })
      structuredListNoteManifest.removeNoteID(noteID)
      try libraryRepository.saveStructuredListNotesManifest(structuredListNoteManifest)
      selectedStructuredListNoteID = adjacentID
    } catch {
      report(error, context: "Deleting structured list note failed")
    }
  }

  // Persists the active list-library grouping to its matching legacy or structured store.
  func saveActiveListManifest() {
    do {
      if isStructuredDailyNoteMode {
        try libraryRepository.saveStructuredListNotesManifest(structuredListNoteManifest)
      } else {
        try libraryRepository.saveListNotesManifest(listNoteManifest)
      }
    } catch {
      report(error, context: "Saving list notes manifest failed")
    }
  }
}

extension ListNotesManifest {
  // Adds only newly imported notes while preserving existing structured grouping and order.
  mutating func appendImportedNotes(
    from sourceManifest: ListNotesManifest,
    importedIDs: Set<String>
  ) {
    for noteID in sourceManifest.ungroupedNoteIDs where importedIDs.contains(noteID) {
      ungroupedNoteIDs.append(noteID)
    }
    for sourceGroup in sourceManifest.groups {
      let groupNoteIDs = sourceGroup.noteIDs.filter(importedIDs.contains)
      guard !groupNoteIDs.isEmpty else { continue }

      if let groupIndex = groups.firstIndex(where: { $0.id == sourceGroup.id }) {
        groups[groupIndex].noteIDs.append(contentsOf: groupNoteIDs)
      } else {
        var importedGroup = sourceGroup
        importedGroup.noteIDs = groupNoteIDs
        groups.append(importedGroup)
      }
    }
  }

  // Returns display order without conflating sidebar groups with within-note section groups.
  func flattenedNoteIDs(includingCollapsedGroups: Bool) -> [String] {
    ungroupedNoteIDs
      + groups
      .filter { includingCollapsedGroups || !$0.isCollapsed }
      .flatMap(\.noteIDs)
  }
}

extension Array where Element == String {
  // Chooses the next visible item, then the previous item, after a deletion.
  func adjacentSelection(afterRemoving id: String) -> String? {
    guard let index = firstIndex(of: id) else { return nil }
    if indices.contains(index + 1) { return self[index + 1] }
    if index > startIndex { return self[index - 1] }
    return nil
  }
}
