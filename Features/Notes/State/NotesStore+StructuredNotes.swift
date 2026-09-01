//
//  NotesStore+StructuredNotes.swift
//

// NotesStore state and actions for the isolated experimental structured daily-note mode.

import Foundation
import OSLog
import SwiftUI

extension NotesStore {
  var isStructuredDailyNoteMode: Bool {
    #if DEBUG
      if isDemoModeEnabled {
        return false
      }
    #endif
    return dailyNoteStorageMode == .structuredExperimental
  }

  var isStructuredDailyModeActive: Bool {
    isStructuredDailyNoteMode && sidebarMode.usesDailyNotes
  }

  var activeDailySelectedNoteID: DayNote.ID? {
    isStructuredDailyNoteMode ? selectedStructuredNoteID : selectedNoteID
  }

  var activeDailySearchText: String {
    isStructuredDailyNoteMode ? structuredSearchText : searchText
  }

  var activeDailySearchBarExpanded: Bool {
    isStructuredDailyNoteMode ? isStructuredSearchBarExpanded : isSearchBarExpanded
  }

  var activeDailyCalendarBrowseYear: Int {
    isStructuredDailyNoteMode ? structuredCalendarBrowseYear : calendarBrowseYear
  }

  var selectedStructuredNote: StructuredNoteDocument? {
    guard let selectedStructuredNoteID else { return nil }
    return structuredNotes.first(where: { $0.id == selectedStructuredNoteID })
  }

  var legacyDailyNotesStorageURL: URL {
    libraryLocation.legacyNotesDirectoryURL
  }

  var structuredDailyNotesStorageURL: URL {
    structuredNoteRepository.storageDirectoryURL
  }

  var activeDailyNotesStorageURL: URL {
    isStructuredDailyNoteMode ? structuredDailyNotesStorageURL : legacyDailyNotesStorageURL
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

  // Switches daily-note storage without resetting or rewriting either isolated library.
  func updateDailyNoteStorageMode(_ mode: DailyNoteStorageMode) {
    guard dailyNoteStorageMode != mode else { return }

    flushPendingSaves()

    #if DEBUG
      if mode == .structuredExperimental, isDemoModeEnabled {
        setDemoModeEnabled(false)
      }
    #endif

    dailyNoteStorageMode = mode
    settingsRepository.saveDailyNoteStorageMode(mode)
    cachedMonthSections = nil

    guard hasLoaded else { return }
    do {
      switch mode {
      case .legacyMarkdown:
        try loadLegacyDailyNotesIfNeeded()
      case .structuredExperimental:
        try loadStructuredDailyNotesIfNeeded()
      }
      userMessage = nil
    } catch {
      report(error, context: "Switching daily-note storage failed")
    }
  }

  // Explicitly copies legacy Markdown notes into the isolated structured repository.
  func copyLegacyDailyNotesToStructuredLibrary() {
    guard !isPerformingFileOperation else {
      userMessage = (text: "Wait for the current file operation to finish.", kind: .info)
      return
    }

    isPerformingFileOperation = true
    progressMessage = "Copying legacy notes into Structured Notes V2..."
    defer {
      isPerformingFileOperation = false
      progressMessage = nil
    }

    flushPendingSaves()

    do {
      let result = try structuredNoteRepository.copyLegacyDailyNotes()
      hasLoadedStructuredNotes = false
      try loadStructuredDailyNotesIfNeeded()
      userMessage = (
        text:
          "Copied \(result.imported) legacy notes into Structured Notes V2; \(result.skipped) existing copies were kept.",
        kind: .info
      )
    } catch {
      report(error, context: "Copying legacy notes into Structured Notes V2 failed")
    }
  }

  // Loads structured documents once and restores their independent selection when possible.
  func loadStructuredDailyNotesIfNeeded() throws {
    guard !hasLoadedStructuredNotes else { return }
    let loadedDocuments = try structuredNoteRepository.loadDocuments()
    structuredNotes = loadedDocuments
    if !loadedDocuments.contains(where: { $0.id == selectedStructuredNoteID }) {
      selectedStructuredNoteID = loadedDocuments.first?.id
    }
    hasLoadedStructuredNotes = true
  }

  // Selects a structured note without changing the retained legacy selection.
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
    Binding(
      get: { self.structuredDocument(withID: documentID)?.title ?? "" },
      set: { title in
        self.updateStructuredDocument(documentID) { document in
          document.title = title
        }
      }
    )
  }

  // Two-way binding for normalized structured note tags.
  func structuredTagsBinding(for documentID: String) -> Binding<String> {
    Binding(
      get: { self.structuredDocument(withID: documentID)?.tags.joined(separator: ", ") ?? "" },
      set: { rawTags in
        self.updateStructuredDocument(documentID) { document in
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
    Binding(
      get: {
        self.structuredSection(withID: sectionID, inDocumentID: documentID)?.markdown ?? ""
      },
      set: { markdown in
        self.updateStructuredDocument(documentID) { document in
          try document.setSectionMarkdown(markdown, sectionID: sectionID)
        }
      }
    )
  }

  // Updates the isolated structured search query.
  func updateStructuredSearchText(_ text: String) {
    structuredSearchText = text
  }

  // Updates the isolated structured search expansion state.
  func updateStructuredSearchBarExpanded(_ isExpanded: Bool) {
    isStructuredSearchBarExpanded = isExpanded
  }

  // Routes calendar browsing to the active daily-note store.
  func updateActiveDailyCalendarBrowseYear(_ year: Int) {
    if isStructuredDailyNoteMode {
      structuredCalendarBrowseYear = year
    } else {
      calendarBrowseYear = year
    }
  }

  // Loads the selected store during launch without touching the inactive daily-note library.
  func loadSelectedDailyNoteStore() {
    do {
      if isStructuredDailyNoteMode {
        try loadStructuredDailyNotesIfNeeded()
        Self.logger.info("Loaded \(self.structuredNotes.count) structured notes")
      } else {
        try loadLegacyDailyNotesIfNeeded()
        Self.logger.info("Loaded \(self.notes.count) notes")
      }
      userMessage = nil
    } catch {
      if isStructuredDailyNoteMode {
        structuredNotes = []
        selectedStructuredNoteID = nil
        report(error, context: "Loading structured notes failed")
      } else {
        recoverLegacyDailyNotes(after: error)
      }
    }
  }

  // Keeps the legacy recovery behavior isolated from structured-mode loading failures.
  private func recoverLegacyDailyNotes(after error: Error) {
    report(error, context: "Loading notes failed")
    notes = [DayNote.empty(for: .now, calendar: calendar)]
    rebuildNoteIndex()
    selectedNoteID = notes.first?.id

    do {
      try save(notes[0])
      hasLoadedLegacyNotes = true
    } catch {
      report(error, context: "Creating today's note failed")
    }
  }

  // Opens an existing structured day or creates a blank structured document for that date.
  func selectStructuredDailyDate(_ date: Date) {
    do {
      let document = try ensureStructuredDailyNoteExists(for: date)
      selectStructuredNote(document.id)
      userMessage = nil
    } catch {
      report(error, context: "Creating structured note failed")
    }
  }

  // Immediately persists every debounced structured document save.
  func flushAllPendingStructuredNoteSaves() {
    for documentID in Array(pendingStructuredNoteSaveTasks.keys) {
      flushPendingStructuredNoteSave(for: documentID)
    }
  }

  // Immediately persists one structured document when it has an outstanding save.
  func flushPendingStructuredNoteSave(for documentID: String) {
    let hadPendingSave = pendingStructuredNoteSaveTasks[documentID] != nil
    pendingStructuredNoteSaveTasks[documentID]?.cancel()
    pendingStructuredNoteSaveTasks[documentID] = nil

    guard hadPendingSave, let document = structuredDocument(withID: documentID) else { return }

    do {
      try structuredNoteRepository.save(document)
    } catch {
      report(error, context: "Saving structured note before leaving failed")
    }
  }

  // Looks up one structured document by its date-based storage ID.
  private func structuredDocument(withID documentID: String) -> StructuredNoteDocument? {
    structuredNotes.first(where: { $0.id == documentID })
  }

  // Finds a stable section without requiring callers to know whether it belongs to a group.
  private func structuredSection(
    withID sectionID: UUID,
    inDocumentID documentID: String
  ) -> StructuredNoteSection? {
    guard let document = structuredDocument(withID: documentID) else { return nil }

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
    mutate: (inout StructuredNoteDocument) throws -> Void
  ) {
    guard let documentIndex = structuredNotes.firstIndex(where: { $0.id == documentID }) else {
      return
    }

    var updatedDocument = structuredNotes[documentIndex]
    do {
      try mutate(&updatedDocument)
      try updatedDocument.validate()
    } catch {
      report(error, context: "Updating structured note failed")
      return
    }

    guard updatedDocument != structuredNotes[documentIndex] else { return }
    var updatedDocuments = structuredNotes
    updatedDocuments[documentIndex] = updatedDocument
    structuredNotes = updatedDocuments
    scheduleStructuredNoteSave(for: documentID)
  }

  // Debounces structured document writes using the same cadence as legacy notes.
  private func scheduleStructuredNoteSave(for documentID: String) {
    pendingStructuredNoteSaveTasks[documentID]?.cancel()
    pendingStructuredNoteSaveTasks[documentID] = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 350_000_000)
      guard !Task.isCancelled else { return }
      self?.persistPendingStructuredNoteSave(for: documentID)
    }
  }

  // Writes the latest validated structured document to its isolated repository.
  private func persistPendingStructuredNoteSave(for documentID: String) {
    pendingStructuredNoteSaveTasks[documentID] = nil
    guard let document = structuredDocument(withID: documentID) else { return }

    do {
      try structuredNoteRepository.save(document)
    } catch {
      report(error, context: "Saving structured note failed")
    }
  }

  // Creates one valid blank structured daily note and persists it before displaying it.
  private func ensureStructuredDailyNoteExists(for date: Date) throws -> StructuredNoteDocument {
    let startOfDay = calendar.startOfDay(for: date)
    let documentID = NoteDateFormatters.storageDate.string(from: startOfDay)
    if let existingDocument = structuredDocument(withID: documentID) {
      return existingDocument
    }

    let document = StructuredNoteDocument.empty(id: documentID, date: startOfDay)
    try structuredNoteRepository.save(document)
    structuredNotes = (structuredNotes + [document]).sorted(by: { $0.date > $1.date })
    return document
  }

  // Produces searchable sidebar text without invoking the throwing portable export boundary.
  private func structuredSummaryBody(for document: StructuredNoteDocument) -> String {
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
