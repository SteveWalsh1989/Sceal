//
//  NotesStore+StructuredLibraryMigration.swift
//

// Explicit safety-backup-first upgrade from legacy Markdown into isolated structured storage.

import Foundation

extension NotesStore {
  // Upgrades both note libraries, writes a fidelity report, and leaves legacy rollback intact.
  func upgradeFullLibraryToStructured() {
    guard !isPerformingFileOperation, !isBackupRunning else {
      userMessage = (text: "Wait for the current file operation to finish.", kind: .info)
      return
    }

    #if DEBUG
      guard !isDemoModeEnabled else {
        userMessage = (
          text: "Turn off Demo Library before upgrading the file-backed library.",
          kind: .info
        )
        return
      }
    #endif

    isPerformingFileOperation = true
    progressMessage = "Creating safety backup and upgrading library..."
    defer {
      isPerformingFileOperation = false
      progressMessage = nil
    }

    do {
      let createdAt = Date.now
      let snapshot = try makeLibrarySnapshot()
      let safetyArchiveURL = try StructuredLibraryCutover.writeSafetyArchive(
        snapshot: snapshot,
        createdAt: createdAt,
        libraryLocation: libraryLocation,
        fileManager: fileManager
      )

      let sourceDailyDocuments = try structuredNoteRepository.prepareLegacyDocuments()
      let sourceListDocuments = try structuredListNoteRepository.prepareLegacyDocuments()
      let existingStructuredListIDs = Set(snapshot.structuredListNotes.map(\.id))
      _ = try structuredNoteRepository.importPreparedDocuments(sourceDailyDocuments)
      _ = try structuredListNoteRepository.importPreparedDocuments(sourceListDocuments)

      let importedListIDs = Set(sourceListDocuments.map(\.id)).subtracting(
        existingStructuredListIDs
      )
      var targetManifest = snapshot.structuredListManifest
      targetManifest.appendImportedNotes(
        from: snapshot.legacyListManifest,
        importedIDs: importedListIDs
      )
      try libraryRepository.saveStructuredListNotesManifest(targetManifest)

      hasLoadedStructuredNotes = false
      hasLoadedStructuredListNotes = false
      try loadStructuredDailyNotesIfNeeded()
      try loadStructuredListNotesIfNeeded()

      let sourceAfterUpgrade = try libraryRepository.loadArchiveSourceSnapshot()
      let legacyLibraryPreserved =
        sourceAfterUpgrade
        == LibraryArchiveSourceSnapshot(
          dailyNotes: snapshot.legacyDailyNotes,
          listNotes: snapshot.legacyListNotes,
          listManifest: snapshot.legacyListManifest
        )
      let report = try StructuredLibraryMigrationReporter.makeReport(
        createdAt: createdAt,
        safetyArchiveURL: safetyArchiveURL,
        sourceDailyDocuments: sourceDailyDocuments,
        sourceListDocuments: sourceListDocuments,
        sourceListManifest: snapshot.legacyListManifest,
        structuredDailyDocuments: structuredNotes,
        structuredListDocuments: structuredListNotes,
        structuredListManifest: structuredListNoteManifest,
        attachmentsRootURL: libraryRepository.attachmentsRootURL,
        templates: snapshot.templates,
        settings: snapshot.settings,
        legacyLibraryPreserved: legacyLibraryPreserved,
        fileManager: fileManager
      )
      let reportURL = try StructuredLibraryMigrationReporter.writeReport(
        report,
        to: libraryLocation.migrationReportsDirectoryURL(fileManager: fileManager),
        fileManager: fileManager
      )

      if report.passedContentValidation, report.legacyLibraryPreserved {
        userMessage = (
          text:
            "Structured upgrade passed for \(report.matchingDailyNoteCount) daily and \(report.matchingListNoteCount) list notes. Legacy Markdown remains available for rollback. Report: \(reportURL.lastPathComponent).",
          kind: .info
        )
      } else {
        userMessage = (
          text:
            "Structured upgrade finished with validation differences. Legacy Markdown was kept; review \(reportURL.lastPathComponent) before switching modes.",
          kind: .error
        )
      }
    } catch {
      report(error, context: "Upgrading full library to Structured Notes V2 failed")
    }
  }

}
