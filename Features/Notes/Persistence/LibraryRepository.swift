//
//  LibraryRepository.swift
//

// File-backed repository for daily notes, list notes, and list-note manifest storage.

import Foundation
import OSLog

struct LibraryListNotesSnapshot: Equatable, Sendable {
  let notes: [DayNote]
  let manifest: ListNotesManifest
  let warnings: [LibraryLoadWarning]
}

struct LibraryDailyNotesSnapshot: Equatable, Sendable {
  let notes: [DayNote]
  let warnings: [LibraryLoadWarning]
}

struct LibraryLoadWarning: Equatable, Sendable {
  enum Kind: Equatable, Sendable {
    case dailyNote
    case listNote
    case listNotesManifest
  }

  let kind: Kind
  let fileName: String
  let detail: String
  let recoveryFileName: String?
}

struct LibraryRepository {
  private static let logger = Logger(subsystem: "com.sceal.app", category: "libraryRepository")
  private static let manifestFileName = "groups.json"

  let libraryLocation: ScealLibraryLocation
  let fileManager: FileManager

  init(libraryLocation: ScealLibraryLocation, fileManager: FileManager = .default) {
    self.libraryLocation = libraryLocation
    self.fileManager = fileManager
  }

  // Loads all valid daily markdown notes, preserving the current skip-corrupt behavior.
  func loadDailyNotes() throws -> [DayNote] {
    try loadDailyNotesSnapshot().notes
  }

  // Loads valid daily notes while returning warnings for skipped files.
  func loadDailyNotesSnapshot() throws -> LibraryDailyNotesSnapshot {
    let fileURLs = try markdownFileURLs(in: dailyNotesDirectoryURL())
    var warnings: [LibraryLoadWarning] = []
    let notes =
      fileURLs.compactMap { url -> DayNote? in
        do {
          return try loadDailyNote(from: url)
        } catch {
          Self.logger.error(
            "Skipping corrupt note \(url.lastPathComponent): \(error.localizedDescription)")
          warnings.append(
            LibraryLoadWarning(
              kind: .dailyNote,
              fileName: url.lastPathComponent,
              detail: error.localizedDescription,
              recoveryFileName: nil
            )
          )
          return nil
        }
      }
      .sorted(by: { $0.date > $1.date })

    return LibraryDailyNotesSnapshot(notes: notes, warnings: warnings)
  }

  // Writes one daily note using the supported markdown codec.
  func saveDailyNote(_ note: DayNote) throws {
    try write(note, to: dailyNotesDirectoryURL().appendingPathComponent(note.fileName))
  }

  // Removes a daily note file when it exists.
  func deleteDailyNoteFile(for note: DayNote) throws {
    try deleteFileIfPresent(at: dailyNotesDirectoryURL().appendingPathComponent(note.fileName))
  }

  // Loads list notes and a reconciled manifest, then persists the reconciliation.
  func loadListNotes() throws -> LibraryListNotesSnapshot {
    let fileURLs = try markdownFileURLs(in: listNotesDirectoryURL())
    var warnings: [LibraryLoadWarning] = []
    let notes =
      fileURLs
      .compactMap { url -> DayNote? in
        do {
          return try loadListNote(from: url)
        } catch {
          Self.logger.error(
            "Skipping corrupt list note \(url.lastPathComponent): \(error.localizedDescription)"
          )
          warnings.append(
            LibraryLoadWarning(
              kind: .listNote,
              fileName: url.lastPathComponent,
              detail: error.localizedDescription,
              recoveryFileName: nil
            )
          )
          return nil
        }
      }
      .sorted(by: { $0.date > $1.date })

    let manifestResult = loadListNotesManifestResult(backsUpInvalidManifest: true)
    var manifest = manifestResult.manifest
    if let warning = manifestResult.warning {
      warnings.append(warning)
    }
    reconcileManifest(&manifest, with: Set(notes.map(\.id)))
    try saveListNotesManifest(manifest)
    return LibraryListNotesSnapshot(notes: notes, manifest: manifest, warnings: warnings)
  }

  // Writes one list note using the supported markdown codec.
  func saveListNote(_ note: DayNote) throws {
    try write(note, to: listNotesDirectoryURL().appendingPathComponent(note.fileName))
  }

  // Removes a list note file when it exists.
  func deleteListNoteFile(for note: DayNote) throws {
    try deleteFileIfPresent(at: listNotesDirectoryURL().appendingPathComponent(note.fileName))
  }

  var attachmentsRootURL: URL {
    libraryLocation.rootURL.appendingPathComponent(
      NoteImageAttachmentStore.attachmentsFolderName,
      isDirectory: true
    )
  }

  // Returns the attachment root, creating it when the caller intends to write attachments.
  func attachmentsRootDirectoryURL(createIfNeeded: Bool = true) throws -> URL {
    try NoteImageAttachmentStore.attachmentRootDirectoryURL(
      fileManager: fileManager,
      rootURL: attachmentsRootURL,
      createIfNeeded: createIfNeeded
    )
  }

  // Moves all attachment files when a daily note changes its storage ID.
  func moveAttachments(from oldNoteID: DayNote.ID, to newNoteID: DayNote.ID) throws {
    try NoteImageAttachmentStore.moveAttachments(
      from: oldNoteID,
      to: newNoteID,
      fileManager: fileManager,
      rootURL: attachmentsRootURL
    )
  }

  // Deletes all attachment files for the requested note ID.
  func deleteAttachments(for noteID: DayNote.ID) throws {
    try NoteImageAttachmentStore.deleteAttachments(
      for: noteID,
      fileManager: fileManager,
      rootURL: attachmentsRootURL
    )
  }

  // Returns the directories used by full-library restore.
  func storageURLs() throws -> ScealLibraryStorageURLs {
    try ScealLibraryStorageURLs(
      notesDirectoryURL: dailyNotesDirectoryURL(),
      listNotesDirectoryURL: listNotesDirectoryURL(),
      attachmentsRootURL: attachmentsRootDirectoryURL()
    )
  }

  // Returns the restore safety archive directory, creating it if needed.
  func restoreSafetyArchiveDirectoryURL() throws -> URL {
    try libraryLocation.restoreSafetyArchiveDirectoryURL(fileManager: fileManager)
  }

  // Reads the list-note manifest, returning empty when the file is missing or invalid.
  func loadListNotesManifest() -> ListNotesManifest {
    loadListNotesManifestResult(backsUpInvalidManifest: false).manifest
  }

  private struct ManifestLoadResult {
    let manifest: ListNotesManifest
    let warning: LibraryLoadWarning?
  }

  private func loadListNotesManifestResult(backsUpInvalidManifest: Bool) -> ManifestLoadResult {
    let manifestURL: URL
    do {
      manifestURL = try manifestFileURL()
    } catch {
      Self.logger.error("Resolving list-note manifest failed: \(error.localizedDescription)")
      return ManifestLoadResult(manifest: .empty, warning: nil)
    }

    guard fileManager.fileExists(atPath: manifestURL.path) else {
      return ManifestLoadResult(manifest: .empty, warning: nil)
    }

    do {
      let data = try Data(contentsOf: manifestURL)
      let manifest = try JSONDecoder().decode(ListNotesManifest.self, from: data)
      return ManifestLoadResult(manifest: manifest, warning: nil)
    } catch {
      Self.logger.error(
        "Invalid list-note manifest \(manifestURL.lastPathComponent): \(error.localizedDescription)"
      )
      let recoveryFileName =
        backsUpInvalidManifest ? backupInvalidManifest(at: manifestURL) : nil
      let warning = LibraryLoadWarning(
        kind: .listNotesManifest,
        fileName: manifestURL.lastPathComponent,
        detail: error.localizedDescription,
        recoveryFileName: recoveryFileName
      )
      return ManifestLoadResult(manifest: .empty, warning: warning)
    }
  }

  private func backupInvalidManifest(at manifestURL: URL) -> String? {
    let backupURL = invalidManifestBackupURL(for: manifestURL)

    do {
      try fileManager.copyItem(at: manifestURL, to: backupURL)
      Self.logger.warning(
        "Backed up invalid list-note manifest to \(backupURL.lastPathComponent)"
      )
      return backupURL.lastPathComponent
    } catch {
      Self.logger.error(
        "Backing up invalid list-note manifest failed: \(error.localizedDescription)"
      )
      return nil
    }
  }

  private func invalidManifestBackupURL(for manifestURL: URL) -> URL {
    let directoryURL = manifestURL.deletingLastPathComponent()
    let timestamp = Self.backupTimestamp()
    var backupURL = directoryURL.appendingPathComponent("groups.invalid-\(timestamp).json")
    var suffix = 2

    while fileManager.fileExists(atPath: backupURL.path) {
      backupURL = directoryURL.appendingPathComponent(
        "groups.invalid-\(timestamp)-\(suffix).json"
      )
      suffix += 1
    }

    return backupURL
  }

  private static func backupTimestamp() -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter.string(from: .now)
  }

  // Writes the list-note manifest using the current pretty-printed JSON format.
  func saveListNotesManifest(_ manifest: ListNotesManifest) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(manifest)
    try data.write(to: manifestFileURL(), options: .atomic)
  }

  // Returns the daily notes directory, creating it if needed.
  func dailyNotesDirectoryURL() throws -> URL {
    try libraryLocation.notesDirectoryURL(fileManager: fileManager)
  }

  // Returns the list notes directory, creating it if needed.
  func listNotesDirectoryURL() throws -> URL {
    try libraryLocation.listNotesDirectoryURL(fileManager: fileManager)
  }

  private func manifestFileURL() throws -> URL {
    try listNotesDirectoryURL().appendingPathComponent(Self.manifestFileName)
  }

  private func markdownFileURLs(in directoryURL: URL) throws -> [URL] {
    try fileManager.contentsOfDirectory(
      at: directoryURL,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )
    .filter { $0.pathExtension == "md" }
  }

  private func loadDailyNote(from url: URL) throws -> DayNote {
    let contents = try String(contentsOf: url, encoding: .utf8)
    return try MarkdownNoteCodec.decode(contents: contents, sourceURL: url)
  }

  private func loadListNote(from url: URL) throws -> DayNote {
    let contents = try String(contentsOf: url, encoding: .utf8)
    let noteID = url.deletingPathExtension().lastPathComponent
    return try MarkdownNoteCodec.decode(contents: contents, sourceURL: url, idOverride: noteID)
  }

  private func write(_ note: DayNote, to fileURL: URL) throws {
    let contents = try MarkdownNoteCodec.encode(note)
    try contents.write(to: fileURL, atomically: true, encoding: .utf8)
  }

  private func deleteFileIfPresent(at fileURL: URL) throws {
    guard fileManager.fileExists(atPath: fileURL.path) else {
      return
    }

    try fileManager.removeItem(at: fileURL)
  }

  private func reconcileManifest(
    _ manifest: inout ListNotesManifest,
    with noteIDsOnDisk: Set<String>
  ) {
    let trackedIDs = manifest.allNoteIDs

    for orphanID in trackedIDs.subtracting(noteIDsOnDisk) {
      manifest.removeNoteID(orphanID)
    }

    for untrackedID in noteIDsOnDisk.subtracting(trackedIDs) {
      manifest.ungroupedNoteIDs.insert(untrackedID, at: 0)
    }
  }
}
