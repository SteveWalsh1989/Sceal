import Foundation

extension NotesStore {
  // Startup and same-process retry share the same idempotent recovery path.
  func recoverPendingLibraryInstallation() throws {
    guard
      var transaction = try LibraryInstallTransaction.read(
        at: libraryLocation.rootURL, fileManager: fileManager)
    else {
      isLibraryRecoveryBlocked = false
      return
    }
    switch transaction.record.phase {
    case .installing:
      setStructuredCutoverStatus(
        try StructuredLibraryState.isCompleted(at: libraryLocation) ? .completed : .notStarted)
      guard settingsRepository.userDefaults.synchronize() else {
        throw LibraryInstallTransactionError.pendingRecovery
      }
      try transaction.rollback()
    case .configuration:
      try transaction.validateInstalled()
      try validateCompletedStructuredCutover()
      if let settings = transaction.record.configuration.settings {
        try applyArchiveSettings(settings)
      }
      try replaceNoteTemplates(transaction.record.configuration.templates)
      try StructuredLibraryState.markCompleted(at: libraryLocation)
      setStructuredCutoverStatus(.completed)
      activateStructuredLibraryAfterCutover()
      // This rare cross-files/preferences commit must reach disk before its recovery record is removed.
      guard settingsRepository.userDefaults.synchronize() else {
        throw LibraryInstallTransactionError.pendingRecovery
      }
      try transaction.finish()
    case .committed:
      try transaction.discard()
    }
    hasLoadedLegacyNotes = false
    hasLoadedStructuredNotes = false
    hasLoadedStructuredListNotes = false
    isLibraryRecoveryBlocked = false
  }

  // A failed recovery never falls through into repositories that create missing storage.
  func recoverLibraryInstallationBeforeLoading() -> Bool {
    do {
      try recoverPendingLibraryInstallation()
      return true
    } catch {
      isLibraryRecoveryBlocked = true
      hasLoaded = false
      structuredNotesCutoverFailureDescription = error.localizedDescription
      setStructuredCutoverStatus(.recoveryRequired)
      report(error, context: "Recovering interrupted library installation failed")
      return false
    }
  }

  // Failed installs may leave a retryable journal even when the previous note remains selected.
  func blockEditingIfLibraryRecoveryIsPending() {
    if fileManager.fileExists(
      atPath: LibraryInstallTransaction.journalURL(in: libraryLocation.rootURL).path)
    {
      isLibraryRecoveryBlocked = true
      hasLoaded = false
      setStructuredCutoverStatus(.recoveryRequired)
    }
  }
}
