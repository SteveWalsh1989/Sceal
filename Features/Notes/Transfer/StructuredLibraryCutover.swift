//
//  StructuredLibraryCutover.swift
//

// Stages, validates, and transactionally installs a structured copy of the legacy library.

import Foundation

nonisolated struct StructuredLibraryCutoverResult: Sendable {
  let dailyDocuments: [StructuredNoteDocument]
  let listDocuments: [StructuredNoteDocument]
  let listManifest: ListNotesManifest
  let safetyArchiveURL: URL
  let reportURL: URL
}

nonisolated enum StructuredLibraryCutover {
  private static let stagingPrefix = ".sceal-structured-cutover-"
  private static let rollbackPrefix = ".sceal-structured-rollback-"

  // Creates a restorable archive before installing an exact, staged legacy conversion.
  static func perform(
    snapshot: ScealLibrarySnapshot,
    sourceDailyDocuments: [StructuredNoteDocument],
    sourceListDocuments: [StructuredNoteDocument],
    libraryLocation: ScealLibraryLocation,
    fileManager: FileManager = .default,
    createdAt: Date = .now
  ) throws -> StructuredLibraryCutoverResult {
    guard try !StructuredLibraryState.isCompleted(at: libraryLocation) else {
      throw StructuredLibraryStateError.alreadyCompleted
    }
    guard snapshot.structuredDailyNotes.isEmpty, snapshot.structuredListNotes.isEmpty else {
      throw StructuredLibraryStateError.ambiguousLibraries
    }
    let safetyArchiveURL = try writeSafetyArchive(
      snapshot: snapshot,
      createdAt: createdAt,
      libraryLocation: libraryLocation,
      fileManager: fileManager
    )
    let stagingRootURL = libraryLocation.rootURL.appendingPathComponent(
      "\(stagingPrefix)\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? fileManager.removeItem(at: stagingRootURL) }

    let stagingLocation = ScealLibraryLocation.test(rootURL: stagingRootURL)
    let stagedDailyRepository = StructuredNoteRepository(
      libraryLocation: stagingLocation,
      fileManager: fileManager
    )
    let stagedListRepository = StructuredNoteRepository.listNotes(
      libraryLocation: stagingLocation,
      fileManager: fileManager
    )
    let stagedLibraryRepository = LibraryRepository(
      libraryLocation: stagingLocation,
      fileManager: fileManager
    )

    try fileManager.createDirectory(
      at: stagingLocation.structuredNotesDirectoryURL,
      withIntermediateDirectories: true
    )
    for document in sourceDailyDocuments {
      try stagedDailyRepository.save(document)
    }
    for document in sourceListDocuments {
      try stagedListRepository.save(document)
    }
    try stagedLibraryRepository.saveStructuredListNotesManifest(snapshot.legacyListManifest)

    let stagedDailyDocuments = try stagedDailyRepository.loadDocuments()
    let stagedListDocuments = try stagedListRepository.loadDocuments()
    let stagedListManifest =
      try stagedLibraryRepository
      .loadStructuredListNotesManifestForArchive(
        noteIDs: Set(stagedListDocuments.map(\.id))
      )
    let legacyLibraryPreserved = try legacyLibraryMatchesSnapshot(
      snapshot,
      libraryLocation: libraryLocation,
      fileManager: fileManager
    )
    let stagedReport = try StructuredLibraryMigrationReporter.makeReport(
      createdAt: createdAt,
      safetyArchiveURL: safetyArchiveURL,
      sourceDailyDocuments: sourceDailyDocuments,
      sourceListDocuments: sourceListDocuments,
      sourceListManifest: snapshot.legacyListManifest,
      structuredDailyDocuments: stagedDailyDocuments,
      structuredListDocuments: stagedListDocuments,
      structuredListManifest: stagedListManifest,
      attachmentsRootURL: libraryLocation.rootURL.appendingPathComponent(
        NoteImageAttachmentStore.attachmentsFolderName,
        isDirectory: true
      ),
      templates: snapshot.templates,
      settings: snapshot.settings,
      legacyLibraryPreserved: legacyLibraryPreserved,
      fileManager: fileManager
    )
    guard stagedReport.passedContentValidation, stagedReport.legacyLibraryPreserved else {
      throw StructuredLibraryCutoverError.stagedValidationFailed
    }

    let installed = try installStagedStorage(
      from: stagingLocation,
      into: libraryLocation,
      snapshot: snapshot,
      sourceDailyDocuments: sourceDailyDocuments,
      sourceListDocuments: sourceListDocuments,
      safetyArchiveURL: safetyArchiveURL,
      createdAt: createdAt,
      fileManager: fileManager
    )

    return StructuredLibraryCutoverResult(
      dailyDocuments: installed.dailyDocuments,
      listDocuments: installed.listDocuments,
      listManifest: installed.listManifest,
      safetyArchiveURL: safetyArchiveURL,
      reportURL: installed.reportURL
    )
  }

  // Reuses the version 2 archive contract for both manual upgrades and startup cutover.
  static func writeSafetyArchive(
    snapshot: ScealLibrarySnapshot,
    createdAt: Date,
    libraryLocation: ScealLibraryLocation,
    fileManager: FileManager = .default
  ) throws -> URL {
    let temporaryArchiveURL = try ScealBackupArchiveExporter.exportBackup(
      dailyNotes: snapshot.legacyDailyNotes,
      listNotes: snapshot.legacyListNotes,
      manifest: snapshot.legacyListManifest,
      templates: snapshot.templates,
      structuredDailyNotes: snapshot.structuredDailyNotes,
      structuredListNotes: snapshot.structuredListNotes,
      structuredListManifest: snapshot.structuredListManifest,
      settings: snapshot.settings,
      authority: snapshot.authority,
      legacySourceFiles: snapshot.legacySourceFiles,
      kind: .manual,
      createdAt: createdAt,
      attachmentsRootURL: libraryLocation.rootURL.appendingPathComponent(
        NoteImageAttachmentStore.attachmentsFolderName,
        isDirectory: true
      )
    )
    defer { ZipArchiveWriter.cleanUp(zipURL: temporaryArchiveURL) }

    let safetyDirectoryURL = try libraryLocation.restoreSafetyArchiveDirectoryURL(
      fileManager: fileManager
    )
    var destinationURL = safetyDirectoryURL.appendingPathComponent(
      temporaryArchiveURL.lastPathComponent
    )
    if fileManager.fileExists(atPath: destinationURL.path) {
      destinationURL = safetyDirectoryURL.appendingPathComponent(
        "\(temporaryArchiveURL.deletingPathExtension().lastPathComponent)-\(UUID().uuidString).zip"
      )
    }
    try fileManager.moveItem(at: temporaryArchiveURL, to: destinationURL)
    return destinationURL
  }

  private static func legacyLibraryMatchesSnapshot(
    _ snapshot: ScealLibrarySnapshot,
    libraryLocation: ScealLibraryLocation,
    fileManager: FileManager
  ) throws -> Bool {
    let current = try LibraryRepository(
      libraryLocation: libraryLocation,
      fileManager: fileManager
    ).loadArchiveSourceSnapshot()
    return current
      == LibraryArchiveSourceSnapshot(
        dailyNotes: snapshot.legacyDailyNotes,
        listNotes: snapshot.legacyListNotes,
        listManifest: snapshot.legacyListManifest
      )
  }

  // Rolls both structured folders back if either installation or reload validation fails.
  private static func installStagedStorage(
    from stagingLocation: ScealLibraryLocation,
    into libraryLocation: ScealLibraryLocation,
    snapshot: ScealLibrarySnapshot,
    sourceDailyDocuments: [StructuredNoteDocument],
    sourceListDocuments: [StructuredNoteDocument],
    safetyArchiveURL: URL,
    createdAt: Date,
    fileManager: FileManager
  ) throws -> (
    dailyDocuments: [StructuredNoteDocument],
    listDocuments: [StructuredNoteDocument],
    listManifest: ListNotesManifest,
    reportURL: URL
  ) {
    let rollbackRootURL = libraryLocation.rootURL.appendingPathComponent(
      "\(rollbackPrefix)\(UUID().uuidString)",
      isDirectory: true
    )
    try fileManager.createDirectory(at: rollbackRootURL, withIntermediateDirectories: true)
    let items = [
      (
        name: ScealLibraryLocation.structuredNotesFolderName,
        stagedURL: stagingLocation.structuredNotesDirectoryURL,
        destinationURL: libraryLocation.structuredNotesDirectoryURL
      ),
      (
        name: ScealLibraryLocation.structuredListNotesFolderName,
        stagedURL: stagingLocation.structuredListNotesDirectoryURL,
        destinationURL: libraryLocation.structuredListNotesDirectoryURL
      ),
    ]
    var movedOriginals: [(destinationURL: URL, rollbackURL: URL)] = []

    do {
      for item in items where fileManager.fileExists(atPath: item.destinationURL.path) {
        let rollbackURL = rollbackRootURL.appendingPathComponent(item.name, isDirectory: true)
        try fileManager.moveItem(at: item.destinationURL, to: rollbackURL)
        movedOriginals.append((item.destinationURL, rollbackURL))
      }
      for item in items {
        try fileManager.moveItem(at: item.stagedURL, to: item.destinationURL)
      }

      let dailyRepository = StructuredNoteRepository(
        libraryLocation: libraryLocation,
        fileManager: fileManager
      )
      let listRepository = StructuredNoteRepository.listNotes(
        libraryLocation: libraryLocation,
        fileManager: fileManager
      )
      let libraryRepository = LibraryRepository(
        libraryLocation: libraryLocation,
        fileManager: fileManager
      )
      let dailyDocuments = try dailyRepository.loadDocuments()
      let listDocuments = try listRepository.loadDocuments()
      let listManifest = try libraryRepository.loadStructuredListNotesManifestForArchive(
        noteIDs: Set(listDocuments.map(\.id))
      )
      let installedReport = try StructuredLibraryMigrationReporter.makeReport(
        createdAt: createdAt,
        safetyArchiveURL: safetyArchiveURL,
        sourceDailyDocuments: sourceDailyDocuments,
        sourceListDocuments: sourceListDocuments,
        sourceListManifest: snapshot.legacyListManifest,
        structuredDailyDocuments: dailyDocuments,
        structuredListDocuments: listDocuments,
        structuredListManifest: listManifest,
        attachmentsRootURL: libraryLocation.rootURL.appendingPathComponent(
          NoteImageAttachmentStore.attachmentsFolderName,
          isDirectory: true
        ),
        templates: snapshot.templates,
        settings: snapshot.settings,
        legacyLibraryPreserved: try legacyLibraryMatchesSnapshot(
          snapshot,
          libraryLocation: libraryLocation,
          fileManager: fileManager
        ),
        fileManager: fileManager
      )
      guard installedReport.passedContentValidation, installedReport.legacyLibraryPreserved else {
        throw StructuredLibraryCutoverError.installedValidationFailed
      }
      let reportURL = try StructuredLibraryMigrationReporter.writeReport(
        installedReport,
        to: libraryLocation.migrationReportsDirectoryURL(fileManager: fileManager),
        fileManager: fileManager
      )
      try StructuredLibraryState.markCompleted(at: libraryLocation)
      // Cleanup failure must not roll back an installation already committed on disk.
      try? fileManager.removeItem(at: rollbackRootURL)
      return (dailyDocuments, listDocuments, listManifest, reportURL)
    } catch {
      let installationError = error
      do {
        for item in items where fileManager.fileExists(atPath: item.destinationURL.path) {
          try fileManager.removeItem(at: item.destinationURL)
        }
        for original in movedOriginals.reversed() {
          try fileManager.moveItem(at: original.rollbackURL, to: original.destinationURL)
        }
        try fileManager.removeItem(at: rollbackRootURL)
      } catch {
        throw StructuredLibraryCutoverError.rollbackFailed(error.localizedDescription)
      }
      throw installationError
    }
  }
}

nonisolated enum StructuredLibraryCutoverError: LocalizedError, Equatable, Sendable {
  case stagedValidationFailed
  case installedValidationFailed
  case rollbackFailed(String)

  var errorDescription: String? {
    switch self {
    case .stagedValidationFailed:
      return "The staged structured library did not exactly match every legacy note."
    case .installedValidationFailed:
      return "The installed structured library did not pass its final reload validation."
    case .rollbackFailed(let reason):
      return
        "Structured conversion rollback failed. The safety archive and original Markdown remain available. \(reason)"
    }
  }
}
