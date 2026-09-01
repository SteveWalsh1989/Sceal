//
//  NotesStore+StructuredNotes.swift
//

// NotesStore state and actions for the isolated experimental structured daily-note mode.

import Foundation
import OSLog

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

  // Converts validated structured documents into read-only sidebar summaries for Stage 3.
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
    selectedStructuredNoteID = noteID
    if let selectedStructuredNote {
      structuredCalendarBrowseYear = calendar.component(.year, from: selectedStructuredNote.date)
    }
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

  // Selects an existing structured day while keeping creation deferred to the Stage 4 editor.
  func selectStructuredDailyDate(_ date: Date) {
    let documentID = NoteDateFormatters.storageDate.string(from: calendar.startOfDay(for: date))
    guard structuredNotes.contains(where: { $0.id == documentID }) else {
      userMessage = (
        text: "Creating and editing structured notes arrives in Stage 4.",
        kind: .info
      )
      return
    }
    selectStructuredNote(documentID)
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
