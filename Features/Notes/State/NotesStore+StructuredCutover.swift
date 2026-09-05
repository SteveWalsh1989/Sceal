//
//  NotesStore+StructuredCutover.swift
//

// Coordinates the blocking production launch gate and safety-backed structured conversion.

import Foundation

extension NotesStore {
  var isStructuredCutoverPromptPresented: Bool {
    guard !isPerformingFileOperation else { return false }
    return structuredNotesCutoverStatus == .conversionRequired
      || structuredNotesCutoverStatus == .failedValidation
      || structuredNotesCutoverStatus == .recoveryRequired
  }

  // Inspects storage before a production launch can create or expose editable notes.
  func prepareStructuredCutoverForProductionLaunch() {
    guard !hasLoaded else { return }

    do {
      let hasCompletionRecord = try StructuredLibraryState.isCompleted(at: libraryLocation)
      if hasCompletionRecord || structuredNotesCutoverStatus == .completed
        || structuredNotesCutoverStatus == .recoveryRequired
      {
        // Retain known authority even if validation fails before an older library gets its record.
        structuredNotesCutoverStatus = .recoveryRequired
        try validateCompletedStructuredCutover()
        if !hasCompletionRecord {
          try StructuredLibraryState.markCompleted(at: libraryLocation)
        }
        setStructuredCutoverStatus(.completed)
        dailyNoteStorageMode =
          settingsRepository.loadSavedDailyNoteStorageMode()
          ?? .structuredExperimental
        loadIfNeeded()
        return
      }

      let legacySnapshot = try libraryRepository.loadArchiveSourceSnapshot()
      let structuredDailyDocuments = try structuredNoteRepository.loadDocuments()
      let structuredListDocuments = try structuredListNoteRepository.loadDocuments()
      let hasLegacyNotes = !legacySnapshot.dailyNotes.isEmpty || !legacySnapshot.listNotes.isEmpty
      guard hasLegacyNotes else {
        try validateCompletedStructuredCutover()
        try StructuredLibraryState.markCompleted(at: libraryLocation)
        setStructuredCutoverStatus(.completed)
        activateStructuredLibraryAfterCutover()
        loadIfNeeded()
        return
      }

      guard structuredDailyDocuments.isEmpty, structuredListDocuments.isEmpty else {
        throw StructuredLibraryStateError.ambiguousLibraries
      }
      setStructuredCutoverStatus(.conversionRequired)
      dailyNoteStorageMode = .legacyMarkdown
      settingsRepository.saveDailyNoteStorageMode(.legacyMarkdown)
    } catch {
      markStructuredCutoverFailed(error)
    }
  }

  // Keeps the current legacy editor available without treating conversion as complete.
  func continueUsingLegacyForNow() {
    dailyNoteStorageMode = .legacyMarkdown
    settingsRepository.saveDailyNoteStorageMode(.legacyMarkdown)
    structuredNotesCutoverFailureDescription = nil
    loadIfNeeded()
  }

  // Records that a full-library restore installed and reloaded valid structured storage.
  func completeStructuredCutoverAfterValidatedRestore() throws {
    try validateCompletedStructuredCutover()
    try StructuredLibraryState.markCompleted(at: libraryLocation)
    setStructuredCutoverStatus(.completed)
    activateStructuredLibraryAfterCutover()
  }

  // Starts a conversion whose only live-library mutation is the validated structured-folder swap.
  func backUpAndConvertLegacyLibrary() {
    guard !isPerformingFileOperation, !isBackupRunning else {
      userMessage = (text: "Wait for the current file operation to finish.", kind: .info)
      return
    }

    do {
      try flushPendingSavesForLibraryOperation()
      guard try !StructuredLibraryState.isCompleted(at: libraryLocation),
        structuredNotesCutoverStatus != .completed,
        structuredNotesCutoverStatus != .recoveryRequired
      else {
        throw StructuredLibraryStateError.alreadyCompleted
      }
    } catch {
      report(error, context: "Preparing library conversion failed")
      return
    }

    let templates = noteTemplates
    let settings: ScealArchiveSettings
    do {
      settings = try makeArchiveSettings()
    } catch {
      markStructuredCutoverFailed(error)
      return
    }

    let libraryRepository = libraryRepository
    let structuredNoteRepository = structuredNoteRepository
    let structuredListNoteRepository = structuredListNoteRepository
    let libraryLocation = libraryLocation
    let fileManager = fileManager

    isPerformingFileOperation = true
    progressMessage = "Backing up and validating every note..."
    structuredNotesCutoverFailureDescription = nil

    Task { [weak self] in
      do {
        let result = try await Task.detached {
          let legacySnapshot = try libraryRepository.loadArchiveSourceSnapshot()
          let existingStructuredListNotes = try structuredListNoteRepository.loadDocuments()
          let snapshot = ScealLibrarySnapshot(
            legacyDailyNotes: legacySnapshot.dailyNotes,
            legacyListNotes: legacySnapshot.listNotes,
            legacyListManifest: legacySnapshot.listManifest,
            structuredDailyNotes: try structuredNoteRepository.loadDocuments(),
            structuredListNotes: existingStructuredListNotes,
            structuredListManifest:
              try libraryRepository
              .loadStructuredListNotesManifestForArchive(
                noteIDs: Set(existingStructuredListNotes.map(\.id))
              ),
            templates: templates,
            settings: settings,
            authority: .legacy,
            legacySourceFiles: try LegacyArchiveSourceFiles.read(
              dailyURL: libraryLocation.legacyNotesDirectoryURL,
              listURL: libraryLocation.rootURL.appendingPathComponent(
                ScealLibraryLocation.listNotesFolderName),
              fileManager: fileManager
            )
          )
          return try StructuredLibraryCutover.perform(
            snapshot: snapshot,
            sourceDailyDocuments: try structuredNoteRepository.prepareLegacyDocuments(),
            sourceListDocuments: try structuredListNoteRepository.prepareLegacyDocuments(),
            libraryLocation: libraryLocation,
            fileManager: fileManager
          )
        }.value

        guard let self else { return }
        self.structuredNotes = result.dailyDocuments
        self.structuredListNotes = result.listDocuments
        self.structuredListNoteManifest = result.listManifest
        self.hasLoadedStructuredNotes = true
        self.hasLoadedStructuredListNotes = true
        self.selectedStructuredNoteID = result.dailyDocuments.first?.id
        self.selectedStructuredListNoteID =
          result.listManifest.ungroupedNoteIDs.first ?? result.listDocuments.first?.id
        self.setStructuredCutoverStatus(.completed)
        self.activateStructuredLibraryAfterCutover()
        self.isPerformingFileOperation = false
        self.progressMessage = nil
        self.loadIfNeeded()
        self.userMessage = (
          text:
            "Converted and validated \(result.dailyDocuments.count) daily notes and \(result.listDocuments.count) list notes. Safety backup: \(result.safetyArchiveURL.lastPathComponent).",
          kind: .info
        )
      } catch {
        guard let self else { return }
        self.isPerformingFileOperation = false
        self.progressMessage = nil
        self.markStructuredCutoverFailed(error)
      }
    }
  }

  private func validateCompletedStructuredCutover() throws {
    try StructuredLibraryState.requireStorageDirectories(at: libraryLocation)
    let listDocuments = try structuredListNoteRepository.loadDocuments()
    _ = try structuredNoteRepository.loadDocuments()
    _ = try libraryRepository.loadStructuredListNotesManifestForArchive(
      noteIDs: Set(listDocuments.map(\.id))
    )
  }

  private func activateStructuredLibraryAfterCutover() {
    dailyNoteStorageMode = .structuredExperimental
    settingsRepository.saveDailyNoteStorageMode(.structuredExperimental)
  }

  private func setStructuredCutoverStatus(_ status: StructuredNotesCutoverStatus) {
    structuredNotesCutoverStatus = status
    settingsRepository.saveStructuredNotesCutoverStatus(status)
    if status != .failedValidation, status != .recoveryRequired {
      structuredNotesCutoverFailureDescription = nil
    }
  }

  private func markStructuredCutoverFailed(_ error: Error) {
    structuredNotesCutoverFailureDescription = error.localizedDescription
    let needsRecovery =
      structuredNotesCutoverStatus == .completed
      || structuredNotesCutoverStatus == .recoveryRequired
    setStructuredCutoverStatus(needsRecovery ? .recoveryRequired : .failedValidation)
    dailyNoteStorageMode = .legacyMarkdown
  }
}
