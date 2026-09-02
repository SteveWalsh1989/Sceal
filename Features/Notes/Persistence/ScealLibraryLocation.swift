//
//  ScealLibraryLocation.swift
//

// Resolves the active on-disk note library root for production, developer, and test runs.

import Foundation

struct ScealLibraryLocation: Equatable, Sendable {
  nonisolated static let productionFolderName = "Sceal"
  nonisolated static let developerFolderName = "Sceal Developer"
  nonisolated static let notesFolderName = "Notes"
  nonisolated static let structuredNotesFolderName = "StructuredNotes"
  nonisolated static let listNotesFolderName = "ListNotes"
  nonisolated static let structuredListNotesFolderName = "StructuredListNotes"
  nonisolated static let restoreSafetyBackupsFolderName = "Restore Safety Backups"
  nonisolated static let migrationReportsFolderName = "Migration Reports"

  let rootURL: URL

  nonisolated static func defaultForCurrentBuild(
    fileManager: FileManager = .default
  ) -> ScealLibraryLocation {
    #if DEBUG
      return developer(fileManager: fileManager)
    #else
      return production(fileManager: fileManager)
    #endif
  }

  nonisolated static func production(fileManager: FileManager = .default) -> ScealLibraryLocation {
    applicationSupportLocation(named: productionFolderName, fileManager: fileManager)
  }

  nonisolated static func developer(fileManager: FileManager = .default) -> ScealLibraryLocation {
    applicationSupportLocation(named: developerFolderName, fileManager: fileManager)
  }

  nonisolated static func test(rootURL: URL) -> ScealLibraryLocation {
    ScealLibraryLocation(rootURL: rootURL)
  }

  nonisolated func notesDirectoryURL(fileManager: FileManager = .default) throws -> URL {
    try createdDirectory(named: Self.notesFolderName, fileManager: fileManager)
  }

  // Resolves the legacy daily-note folder without creating or changing it.
  nonisolated var legacyNotesDirectoryURL: URL {
    rootURL.appendingPathComponent(Self.notesFolderName, isDirectory: true)
  }

  // Resolves the isolated structured daily-note folder without creating or changing it.
  nonisolated var structuredNotesDirectoryURL: URL {
    rootURL.appendingPathComponent(Self.structuredNotesFolderName, isDirectory: true)
  }

  nonisolated func listNotesDirectoryURL(fileManager: FileManager = .default) throws -> URL {
    try createdDirectory(named: Self.listNotesFolderName, fileManager: fileManager)
  }

  // Resolves the isolated structured list-note folder without creating or changing it.
  nonisolated var structuredListNotesDirectoryURL: URL {
    rootURL.appendingPathComponent(Self.structuredListNotesFolderName, isDirectory: true)
  }

  nonisolated func attachmentsRootURL(fileManager: FileManager = .default) throws -> URL {
    try createdDirectory(
      named: NoteImageAttachmentStore.attachmentsFolderName, fileManager: fileManager)
  }

  nonisolated func restoreSafetyArchiveDirectoryURL(fileManager: FileManager = .default) throws
    -> URL
  {
    try createdDirectory(named: Self.restoreSafetyBackupsFolderName, fileManager: fileManager)
  }

  nonisolated func migrationReportsDirectoryURL(fileManager: FileManager = .default) throws -> URL {
    try createdDirectory(named: Self.migrationReportsFolderName, fileManager: fileManager)
  }

  private nonisolated static func applicationSupportLocation(
    named folderName: String,
    fileManager: FileManager
  ) -> ScealLibraryLocation {
    let applicationSupportURL =
      (try? fileManager.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      ))
      ?? fileManager.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support", isDirectory: true)

    return ScealLibraryLocation(
      rootURL: applicationSupportURL.appendingPathComponent(folderName, isDirectory: true)
    )
  }

  private nonisolated func createdDirectory(
    named folderName: String,
    fileManager: FileManager
  ) throws -> URL {
    let directoryURL = rootURL.appendingPathComponent(folderName, isDirectory: true)
    try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    return directoryURL
  }
}
