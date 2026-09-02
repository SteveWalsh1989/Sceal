//
//  ArchiveService.swift
//

// Boundary around archive export, backup, restore, and backup-folder access.

import Foundation

nonisolated struct ArchiveService {
  let fileManager: FileManager

  // Exports selected daily notes using the existing year-organized archive format.
  func exportNotes(
    _ notes: [DayNote],
    templates: [NoteTemplate] = [],
    attachmentsRootURL: URL? = nil
  ) throws -> URL {
    try ScealArchiveExporter.exportNotes(
      notes,
      templates: templates,
      attachmentsRootURL: attachmentsRootURL
    )
  }

  // Exports a full-library backup archive using the existing backup archive layout.
  func exportBackup(
    dailyNotes: [DayNote],
    listNotes: [DayNote],
    manifest: ListNotesManifest,
    templates: [NoteTemplate] = [],
    structuredDailyNotes: [StructuredNoteDocument] = [],
    structuredListNotes: [StructuredNoteDocument] = [],
    structuredListManifest: ListNotesManifest? = nil,
    settings: ScealArchiveSettings? = nil,
    kind: BackupArchiveKind,
    createdAt: Date = .now,
    attachmentsRootURL: URL? = nil
  ) throws -> URL {
    try ScealBackupArchiveExporter.exportBackup(
      dailyNotes: dailyNotes,
      listNotes: listNotes,
      manifest: manifest,
      templates: templates,
      structuredDailyNotes: structuredDailyNotes,
      structuredListNotes: structuredListNotes,
      structuredListManifest: structuredListManifest,
      settings: settings,
      kind: kind,
      createdAt: createdAt,
      attachmentsRootURL: attachmentsRootURL
    )
  }

  // Restores a validated archive using the current safety-backup-first behavior.
  func restoreLibrary(
    from archiveURL: URL,
    currentDailyNotes: [DayNote],
    currentListNotes: [DayNote],
    currentManifest: ListNotesManifest,
    currentTemplates: [NoteTemplate] = [],
    currentStructuredDailyNotes: [StructuredNoteDocument] = [],
    currentStructuredListNotes: [StructuredNoteDocument] = [],
    currentStructuredListManifest: ListNotesManifest = .empty,
    currentSettings: ScealArchiveSettings? = nil,
    destinationURLs: ScealLibraryStorageURLs,
    safetyArchiveDirectoryURL: URL
  ) throws -> ScealBackupArchiveImporter.RestoreResult {
    try ScealBackupArchiveImporter.restoreLibrary(
      from: archiveURL,
      currentDailyNotes: currentDailyNotes,
      currentListNotes: currentListNotes,
      currentManifest: currentManifest,
      currentTemplates: currentTemplates,
      currentStructuredDailyNotes: currentStructuredDailyNotes,
      currentStructuredListNotes: currentStructuredListNotes,
      currentStructuredListManifest: currentStructuredListManifest,
      currentSettings: currentSettings,
      destinationURLs: destinationURLs,
      safetyArchiveDirectoryURL: safetyArchiveDirectoryURL,
      fileManager: fileManager
    )
  }

  // Moves a backup archive into the managed folder and prunes automatic backups when needed.
  func writeManagedBackupArchive(
    dailyNotes: [DayNote],
    listNotes: [DayNote],
    manifest: ListNotesManifest,
    templates: [NoteTemplate] = [],
    structuredDailyNotes: [StructuredNoteDocument] = [],
    structuredListNotes: [StructuredNoteDocument] = [],
    structuredListManifest: ListNotesManifest? = nil,
    settings: ScealArchiveSettings? = nil,
    bookmarkData: Data,
    kind: BackupArchiveKind,
    schedule: BackupSchedule,
    createdAt: Date,
    attachmentsRootURL: URL? = nil
  ) throws -> URL {
    try accessBookmark(bookmarkData) { selectedFolderURL in
      let managedFolderURL = managedBackupDirectoryURL(in: selectedFolderURL)
      try fileManager.createDirectory(at: managedFolderURL, withIntermediateDirectories: true)

      let temporaryArchiveURL = try exportBackup(
        dailyNotes: dailyNotes,
        listNotes: listNotes,
        manifest: manifest,
        templates: templates,
        structuredDailyNotes: structuredDailyNotes,
        structuredListNotes: structuredListNotes,
        structuredListManifest: structuredListManifest,
        settings: settings,
        kind: kind,
        createdAt: createdAt,
        attachmentsRootURL: attachmentsRootURL
      )
      let destinationArchiveURL = managedFolderURL.appendingPathComponent(
        temporaryArchiveURL.lastPathComponent
      )

      if fileManager.fileExists(atPath: destinationArchiveURL.path) {
        try fileManager.removeItem(at: destinationArchiveURL)
      }

      try fileManager.moveItem(at: temporaryArchiveURL, to: destinationArchiveURL)
      ZipArchiveWriter.cleanUp(zipURL: temporaryArchiveURL)

      if kind == .automatic {
        try pruneAutomaticBackups(in: managedFolderURL, schedule: schedule)
      }

      return destinationArchiveURL
    }
  }

  // Returns the managed backup directory inside the user-selected parent folder.
  func managedBackupDirectoryURL(in selectedFolderURL: URL) -> URL {
    ScealBackupArchiveExporter.managedBackupDirectoryURL(in: selectedFolderURL)
  }

  // Removes old automatic backup archives according to the selected schedule.
  func pruneAutomaticBackups(
    in managedFolderURL: URL,
    schedule: BackupSchedule
  ) throws {
    guard let retainedAutomaticBackupCount = schedule.retainedAutomaticBackupCount else {
      return
    }

    let automaticArchiveURLs = try fileManager.contentsOfDirectory(
      at: managedFolderURL,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )
    .filter { $0.lastPathComponent.hasPrefix("sceal-backup-auto-") && $0.pathExtension == "zip" }
    .sorted(by: { $0.lastPathComponent > $1.lastPathComponent })

    guard automaticArchiveURLs.count > retainedAutomaticBackupCount else {
      return
    }

    for archiveURL in automaticArchiveURLs.dropFirst(retainedAutomaticBackupCount) {
      try fileManager.removeItem(at: archiveURL)
    }
  }

  // Resolves a security-scoped bookmark and runs the provided filesystem operation.
  func accessBookmark<T>(
    _ bookmarkData: Data,
    accessBlock: (URL) throws -> T
  ) throws -> T {
    var isStale = false
    let selectedFolderURL = try URL(
      resolvingBookmarkData: bookmarkData,
      options: [.withSecurityScope, .withoutUI],
      relativeTo: nil,
      bookmarkDataIsStale: &isStale
    )

    if isStale {
      throw BackupFolderError.permissionRequired
    }

    let didStartAccessing = selectedFolderURL.startAccessingSecurityScopedResource()
    guard didStartAccessing else {
      throw BackupFolderError.permissionRequired
    }

    defer {
      selectedFolderURL.stopAccessingSecurityScopedResource()
    }

    return try accessBlock(selectedFolderURL)
  }

  // Requires a configured backup-folder bookmark before archive writes.
  func requireBookmarkData(from settings: BackupSettings) throws -> Data {
    guard let bookmarkData = settings.folderBookmarkData else {
      throw BackupFolderError.folderNotConfigured
    }

    return bookmarkData
  }

  // Cleans up a temporary archive's parent staging folder after the archive is moved.
  func cleanUp(zipURL: URL) {
    ZipArchiveWriter.cleanUp(zipURL: zipURL)
  }
}
