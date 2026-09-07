//
//  NotesStore+StructuredListNotes.swift
//

// Structured list-note state, persistence, and sidebar summaries.

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
    structuredListNoteSummaries
  }

  var activeListNoteManifest: ListNotesManifest {
    get { structuredListNoteManifest }
    set { structuredListNoteManifest = newValue }
  }

  var activeListSelectedNoteID: DayNote.ID? {
    get { selectedStructuredListNoteID }
    set { selectStructuredListNote(newValue) }
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

  // Selects one structured list note and flushes the note being left.
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

  // Deletes one structured list document while leaving any same-ID retained Markdown intact.
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

  // Persists list-library grouping to structured storage.
  func saveActiveListManifest() {
    do {
      try libraryRepository.saveStructuredListNotesManifest(structuredListNoteManifest)
    } catch {
      report(error, context: "Saving list notes manifest failed")
    }
  }
}

extension ListNotesManifest {
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
