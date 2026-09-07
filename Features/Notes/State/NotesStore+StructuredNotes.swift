//
//  NotesStore+StructuredNotes.swift
//

// NotesStore state and actions for structured daily notes.

import Foundation
import OSLog
import SwiftUI

nonisolated struct StructuredNoteSaveKey: Hashable, Sendable {
  let repositoryKind: StructuredNoteRepositoryKind
  let documentID: String
}

extension NotesStore {
  var activeDailySelectedNoteID: DayNote.ID? {
    selectedStructuredNoteID
  }

  var activeDailySearchText: String {
    structuredSearchText
  }

  var activeDailySearchBarExpanded: Bool {
    isStructuredSearchBarExpanded
  }

  var activeDailyCalendarBrowseYear: Int {
    structuredCalendarBrowseYear
  }

  var selectedStructuredNote: StructuredNoteDocument? {
    if sidebarMode == .list {
      return selectedStructuredListNote
    }
    guard let selectedStructuredNoteID else { return nil }
    return structuredNotes.first(where: { $0.id == selectedStructuredNoteID })
  }

  var activeStructuredSelectedNoteID: String? {
    sidebarMode == .list ? selectedStructuredListNoteID : selectedStructuredNoteID
  }

  var activeStructuredSearchText: String {
    sidebarMode == .list ? listSearchText : structuredSearchText
  }

  private var activeStructuredRepositoryKind: StructuredNoteRepositoryKind {
    sidebarMode == .list ? .list : .daily
  }

  var legacyDailyNotesStorageURL: URL {
    libraryLocation.legacyNotesDirectoryURL
  }

  var structuredDailyNotesStorageURL: URL {
    structuredNoteRepository.storageDirectoryURL
  }

  var activeDailyNotesStorageURL: URL {
    structuredDailyNotesStorageURL
  }

  // Converts validated structured documents into sidebar and calendar summaries.
  var structuredNoteSummaries: [DayNote] {
    structuredNotes.map { document in
      DayNote(
        date: document.date,
        id: document.id,
        title: document.title,
        tags: document.tags,
        body: structuredSummaryBody(for: document)
      )
    }
  }

  // Returns the daily-note summary used by shared sidebar dialogs.
  func activeDailyNoteSummary(withID noteID: DayNote.ID) -> DayNote? {
    structuredNoteSummaries.first(where: { $0.id == noteID })
  }

  // Loads structured documents once and restores the current selection when possible.
  func loadStructuredDailyNotesIfNeeded() throws {
    guard !hasLoadedStructuredNotes else { return }
    let loadedDocuments = try structuredNoteRepository.loadDocuments()
    structuredNotes = loadedDocuments
    cachedMonthSections = nil
    if !loadedDocuments.contains(where: { $0.id == selectedStructuredNoteID }) {
      selectedStructuredNoteID = loadedDocuments.first?.id
    }
    hasLoadedStructuredNotes = true
  }

  // Selects a structured daily note and flushes the note being left.
  func selectStructuredNote(_ noteID: DayNote.ID?) {
    guard noteID == nil || structuredNotes.contains(where: { $0.id == noteID }) else { return }
    if selectedStructuredNoteID != noteID, let selectedStructuredNoteID {
      flushPendingStructuredNoteSave(for: selectedStructuredNoteID)
    }
    selectedStructuredNoteID = noteID
    if let selectedStructuredNote {
      structuredCalendarBrowseYear = calendar.component(.year, from: selectedStructuredNote.date)
    }
  }

  // Returns the nearest older and newer structured notes for editor header navigation.
  func adjacentStructuredNoteIDs(
    for documentID: String
  ) -> (previous: String?, next: String?) {
    guard let currentIndex = structuredNotes.firstIndex(where: { $0.id == documentID }) else {
      return (nil, nil)
    }

    let previousID =
      structuredNotes.indices.contains(currentIndex + 1)
      ? structuredNotes[currentIndex + 1].id
      : nil
    let nextID =
      currentIndex > structuredNotes.startIndex ? structuredNotes[currentIndex - 1].id : nil
    return (previousID, nextID)
  }

  // Two-way binding for an editable structured note title.
  func structuredTitleBinding(for documentID: String) -> Binding<String> {
    let repositoryKind = activeStructuredRepositoryKind
    return Binding(
      get: {
        self.structuredDocument(withID: documentID, repositoryKind: repositoryKind)?.title ?? ""
      },
      set: { title in
        self.updateStructuredDocument(documentID, repositoryKind: repositoryKind) { document in
          document.title = title
        }
      }
    )
  }

  // Two-way binding for normalized structured note tags.
  func structuredTagsBinding(for documentID: String) -> Binding<String> {
    let repositoryKind = activeStructuredRepositoryKind
    return Binding(
      get: {
        self.structuredDocument(withID: documentID, repositoryKind: repositoryKind)?
          .tags.joined(separator: ", ") ?? ""
      },
      set: { rawTags in
        self.updateStructuredDocument(documentID, repositoryKind: repositoryKind) { document in
          document.tags = self.normalizedTags(from: rawTags)
        }
      }
    )
  }

  // Two-way binding for one stable section's Markdown, regardless of group placement.
  func structuredSectionMarkdownBinding(
    documentID: String,
    sectionID: UUID
  ) -> Binding<String> {
    let repositoryKind = activeStructuredRepositoryKind
    return Binding(
      get: {
        self.structuredSection(
          withID: sectionID,
          inDocumentID: documentID,
          repositoryKind: repositoryKind
        )?.markdown ?? ""
      },
      set: { markdown in
        self.updateStructuredDocument(documentID, repositoryKind: repositoryKind) { document in
          try document.setSectionMarkdown(markdown, sectionID: sectionID)
        }
      }
    )
  }

  // Replaces one validated document snapshot for structural edits and undo/redo.
  func replaceStructuredDocument(_ document: StructuredNoteDocument) {
    updateStructuredDocument(document.id) { storedDocument in
      storedDocument = document
    }
  }

  // Updates the structured search query.
  func updateStructuredSearchText(_ text: String) {
    structuredSearchText = text
    cachedMonthSections = nil
  }

  // Updates the structured search expansion state.
  func updateStructuredSearchBarExpanded(_ isExpanded: Bool) {
    isStructuredSearchBarExpanded = isExpanded
  }

  // Opens an existing structured day or creates a blank structured document for that date.
  func selectStructuredDailyDate(_ date: Date) {
    do {
      let document = try ensureStructuredDailyNoteExists(
        for: date,
        applyDefault: calendar.isDateInToday(date)
      )
      selectStructuredNote(document.id)
      userMessage = nil
    } catch {
      report(error, context: "Creating structured note failed")
    }
  }

  // Moves a structured note while preserving section identity and retained Markdown.
  func changeStructuredNoteDate(noteID: DayNote.ID, to newDate: Date) {
    let targetDate = calendar.startOfDay(for: newDate)
    let targetID = NoteDateFormatters.storageDate.string(from: targetDate)
    guard
      let sourceDocument = structuredDocument(withID: noteID, repositoryKind: .daily)
    else { return }

    if structuredDocument(withID: targetID, repositoryKind: .daily) != nil {
      let formatted = NoteDateFormatters.editorDate.string(from: targetDate)
      userMessage = (text: "A note already exists for \(formatted).", kind: .error)
      return
    }

    flushPendingStructuredNoteSave(for: noteID)
    let movedDocument = rewritingStructuredDocument(
      sourceDocument,
      id: targetID,
      date: targetDate,
      regeneratesNodeIDs: false
    )

    do {
      try structuredNoteRepository.save(movedDocument)
      do {
        try libraryRepository.copyAttachments(from: sourceDocument.id, to: targetID)
        try structuredNoteRepository.delete(documentID: sourceDocument.id)
      } catch {
        try? structuredNoteRepository.delete(documentID: targetID)
        throw error
      }
    } catch {
      report(error, context: "Changing structured note date failed")
      return
    }

    structuredNotes.removeAll(where: { $0.id == noteID })
    structuredNotes.append(movedDocument)
    structuredNotes.sort(by: { $0.date > $1.date })
    cachedMonthSections = nil
    selectedStructuredNoteID = movedDocument.id
  }

  // Deletes one structured document without removing attachments shared by the legacy library.
  func deleteStructuredNote(noteID: DayNote.ID) {
    guard structuredDocument(withID: noteID, repositoryKind: .daily) != nil else { return }
    let adjacentNoteIDs = adjacentStructuredNoteIDs(for: noteID)
    flushPendingStructuredNoteSave(for: noteID)

    do {
      try structuredNoteRepository.delete(documentID: noteID)
    } catch {
      report(error, context: "Deleting structured note failed")
      return
    }

    structuredNotes.removeAll(where: { $0.id == noteID })
    cachedMonthSections = nil
    selectedStructuredNoteID =
      adjacentNoteIDs.previous ?? adjacentNoteIDs.next ?? structuredNotes.first?.id
  }

  // Immediately persists every debounced structured document save.
  func flushAllPendingStructuredNoteSaves() {
    for saveKey in Array(pendingStructuredNoteSaveTasks.keys) {
      flushPendingStructuredNoteSave(for: saveKey)
    }
  }

  // Flushes every matching ID safely when daily and list libraries use the same stable ID.
  func flushPendingStructuredNoteSave(for documentID: String) {
    let matchingKeys = pendingStructuredNoteSaveTasks.keys.filter {
      $0.documentID == documentID
    }
    for saveKey in matchingKeys {
      flushPendingStructuredNoteSave(for: saveKey)
    }
  }

  // Cancels one debounce task and writes the matching library's latest in-memory document.
  private func flushPendingStructuredNoteSave(for saveKey: StructuredNoteSaveKey) {
    guard let pendingTask = pendingStructuredNoteSaveTasks[saveKey] else { return }
    pendingTask.cancel()
    persistPendingStructuredNoteSave(for: saveKey)
  }

  // Keeps identical daily and list storage IDs isolated during editing and debounced saves.
  private func structuredDocument(
    withID documentID: String,
    repositoryKind: StructuredNoteRepositoryKind
  ) -> StructuredNoteDocument? {
    switch repositoryKind {
    case .daily:
      return structuredNotes.first(where: { $0.id == documentID })
    case .list:
      return structuredListNotes.first(where: { $0.id == documentID })
    }
  }

  // Finds a stable section without requiring callers to know whether it belongs to a group.
  private func structuredSection(
    withID sectionID: UUID,
    inDocumentID documentID: String,
    repositoryKind: StructuredNoteRepositoryKind
  ) -> StructuredNoteSection? {
    guard
      let document = structuredDocument(withID: documentID, repositoryKind: repositoryKind)
    else { return nil }

    for node in document.nodes {
      switch node {
      case .section(let section) where section.id == sectionID:
        return section
      case .group(let group):
        if let section = group.sections.first(where: { $0.id == sectionID }) {
          return section
        }
      default:
        continue
      }
    }
    return nil
  }

  // Applies and validates one in-memory document edit before scheduling an atomic save.
  private func updateStructuredDocument(
    _ documentID: String,
    repositoryKind: StructuredNoteRepositoryKind? = nil,
    mutate: (inout StructuredNoteDocument) throws -> Void
  ) {
    let resolvedKind = repositoryKind ?? activeStructuredRepositoryKind
    let dailyIndex =
      resolvedKind == .daily
      ? structuredNotes.firstIndex(where: { $0.id == documentID }) : nil
    let listIndex =
      resolvedKind == .list
      ? structuredListNotes.firstIndex(where: { $0.id == documentID }) : nil
    guard
      let originalDocument = structuredDocument(
        withID: documentID,
        repositoryKind: resolvedKind
      )
    else { return }
    var updatedDocument = originalDocument
    do {
      try mutate(&updatedDocument)
      try updatedDocument.validate()
    } catch {
      report(error, context: "Updating structured note failed")
      return
    }

    guard updatedDocument != originalDocument else { return }
    if let dailyIndex {
      var updatedDocuments = structuredNotes
      updatedDocuments[dailyIndex] = updatedDocument
      structuredNotes = updatedDocuments
      cachedMonthSections = nil
    } else if let listIndex {
      var updatedDocuments = structuredListNotes
      updatedDocuments[listIndex] = updatedDocument
      structuredListNotes = updatedDocuments
    }
    scheduleStructuredNoteSave(for: documentID, repositoryKind: resolvedKind)
  }

  // Debounces structured document writes using the same cadence as legacy notes.
  private func scheduleStructuredNoteSave(
    for documentID: String,
    repositoryKind: StructuredNoteRepositoryKind
  ) {
    let saveKey = StructuredNoteSaveKey(
      repositoryKind: repositoryKind,
      documentID: documentID
    )
    pendingStructuredNoteSaveTasks[saveKey]?.cancel()
    pendingStructuredNoteSaveTasks[saveKey] = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 350_000_000)
      guard !Task.isCancelled else { return }
      self?.persistPendingStructuredNoteSave(for: saveKey)
    }
  }

  // Writes the latest validated structured document to its isolated repository.
  private func persistPendingStructuredNoteSave(for saveKey: StructuredNoteSaveKey) {
    guard
      let document = structuredDocument(
        withID: saveKey.documentID,
        repositoryKind: saveKey.repositoryKind
      )
    else {
      pendingStructuredNoteSaveTasks[saveKey] = nil
      return
    }

    do {
      if saveKey.repositoryKind == .list {
        try structuredListNoteRepository.save(document)
      } else {
        try structuredNoteRepository.save(document)
      }
      pendingStructuredNoteSaveTasks[saveKey] = nil
    } catch {
      report(error, context: "Saving structured note failed")
    }
  }

  // Creates one valid blank structured daily note and persists it before displaying it.
  private func ensureStructuredDailyNoteExists(
    for date: Date,
    applyDefault: Bool
  ) throws -> StructuredNoteDocument {
    let startOfDay = calendar.startOfDay(for: date)
    let documentID = NoteDateFormatters.storageDate.string(from: startOfDay)
    if let existingDocument = structuredDocument(withID: documentID, repositoryKind: .daily) {
      return existingDocument
    }

    let document = try makeStructuredDailyNote(
      id: documentID,
      date: startOfDay,
      applyDefault: applyDefault
    )
    try structuredNoteRepository.save(document)

    if applyDefault, case .copyPrevious = effectiveNewNoteDefault,
      let sourceDocument = structuredNotes.first
    {
      do {
        try libraryRepository.copyAttachments(from: sourceDocument.id, to: document.id)
      } catch {
        try? structuredNoteRepository.delete(documentID: document.id)
        throw error
      }
    }

    structuredNotes = (structuredNotes + [document]).sorted(by: { $0.date > $1.date })
    cachedMonthSections = nil
    return document
  }

  // Builds a blank, copied, or template-backed structured note using the shared daily preference.
  private func makeStructuredDailyNote(
    id: String,
    date: Date,
    applyDefault: Bool
  ) throws -> StructuredNoteDocument {
    guard applyDefault else { return .empty(id: id, date: date) }

    if case .copyPrevious = effectiveNewNoteDefault, let previousDocument = structuredNotes.first {
      return rewritingStructuredDocument(
        previousDocument,
        id: id,
        date: date,
        regeneratesNodeIDs: true
      )
    }

    if case .template(let templateID) = effectiveNewNoteDefault,
      let template = noteTemplate(withID: templateID)
    {
      let insertion = try StructuredNoteTemplateAdapter.insert(
        StructuredTemplateInsertionRequest(
          leadingMarkdown: "",
          trailingMarkdown: "",
          template: template,
          preservesReplacedLineBreak: false
        ),
        replacing: StructuredNoteSection()
      )
      return StructuredNoteDocument(
        id: id,
        date: date,
        title: "",
        tags: [],
        nodes: insertion.sections.map(StructuredNoteNode.section)
      )
    }

    return .empty(id: id, date: date)
  }

  // Rewrites attachment paths and optionally refreshes node IDs for a copied daily document.
  private func rewritingStructuredDocument(
    _ document: StructuredNoteDocument,
    id: String,
    date: Date,
    regeneratesNodeIDs: Bool
  ) -> StructuredNoteDocument {
    let nodes = document.nodes.map { node -> StructuredNoteNode in
      switch node {
      case .section(let section):
        return .section(
          rewrittenStructuredSection(
            section,
            from: document.id,
            to: id,
            regeneratesID: regeneratesNodeIDs
          )
        )

      case .group(let group):
        return .group(
          StructuredSectionGroup(
            id: regeneratesNodeIDs ? UUID() : group.id,
            title: group.title,
            style: group.style,
            isCollapsed: group.isCollapsed,
            showsTypeLabel: group.showsTypeLabel,
            showsSectionCount: group.showsSectionCount,
            sections: group.sections.map {
              rewrittenStructuredSection(
                $0,
                from: document.id,
                to: id,
                regeneratesID: regeneratesNodeIDs
              )
            }
          )
        )
      }
    }

    return StructuredNoteDocument(
      id: id,
      date: date,
      title: document.title,
      tags: document.tags,
      nodes: nodes
    )
  }

  // Rewrites attachment references while retaining all section presentation state.
  private func rewrittenStructuredSection(
    _ section: StructuredNoteSection,
    from sourceID: String,
    to destinationID: String,
    regeneratesID: Bool
  ) -> StructuredNoteSection {
    StructuredNoteSection(
      id: regeneratesID ? UUID() : section.id,
      markdown: NoteImageAttachmentStore.rewritingAttachmentReferences(
        in: section.markdown,
        from: sourceID,
        to: destinationID
      ),
      styleOverrides: section.styleOverrides,
      isCollapsed: section.isCollapsed
    )
  }

  // Produces searchable sidebar text without invoking the throwing portable export boundary.
  func structuredSummaryBody(for document: StructuredNoteDocument) -> String {
    document.nodes.flatMap { node -> [String] in
      switch node {
      case .section(let section):
        return [section.markdown]
      case .group(let group):
        return ["## \(group.title)"] + group.sections.map(\.markdown)
      }
    }
    .joined(separator: "\n\n")
  }
}
