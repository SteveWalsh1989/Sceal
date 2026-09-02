//
//  LibraryRepository.swift
//

// File-backed repository for daily notes, list notes, and list-note manifest storage.

import Foundation
import OSLog

struct LibraryListNotesSnapshot: Equatable, Sendable {
  let notes: [DayNote]
  let manifest: ListNotesManifest
}

struct LibraryArchiveSourceSnapshot: Equatable, Sendable {
  let dailyNotes: [DayNote]
  let listNotes: [DayNote]
  let listManifest: ListNotesManifest
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
    let fileURLs = try markdownFileURLs(in: dailyNotesDirectoryURL())
    return
      fileURLs
      .compactMap { url -> DayNote? in
        do {
          return try loadDailyNote(from: url)
        } catch {
          Self.logger.error(
            "Skipping corrupt note \(url.lastPathComponent): \(error.localizedDescription)")
          return nil
        }
      }
      .sorted(by: { $0.date > $1.date })
  }

  // Strictly reads the complete legacy library without reconciling or changing source files.
  func loadArchiveSourceSnapshot() throws -> LibraryArchiveSourceSnapshot {
    let dailyNotes = try markdownFileURLs(in: dailyNotesDirectoryURL())
      .map(loadDailyNote(from:))
      .sorted(by: { $0.date > $1.date })
    let listNotes = try markdownFileURLs(in: listNotesDirectoryURL())
      .map(loadListNote(from:))
      .sorted(by: { $0.date > $1.date })
    let manifest = try decodeManifestForArchive(
      at: manifestFileURL(),
      invalidError: LibraryRepositoryError.invalidLegacyManifest
    )
    guard manifest.allNoteIDs == Set(listNotes.map(\.id)) else {
      throw LibraryRepositoryError.manifestMismatch
    }
    return LibraryArchiveSourceSnapshot(
      dailyNotes: dailyNotes,
      listNotes: listNotes,
      listManifest: manifest
    )
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
    let notes =
      fileURLs
      .compactMap { url -> DayNote? in
        do {
          return try loadListNote(from: url)
        } catch {
          Self.logger.error(
            "Skipping corrupt list note \(url.lastPathComponent): \(error.localizedDescription)"
          )
          return nil
        }
      }
      .sorted(by: { $0.date > $1.date })

    var manifest = loadListNotesManifest()
    reconcileManifest(&manifest, with: Set(notes.map(\.id)))
    try saveListNotesManifest(manifest)
    return LibraryListNotesSnapshot(notes: notes, manifest: manifest)
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

  // Copies a note's attachment folder for structured duplication without changing its source.
  func copyAttachments(from oldNoteID: DayNote.ID, to newNoteID: DayNote.ID) throws {
    try NoteImageAttachmentStore.copyAttachments(
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
      structuredNotesDirectoryURL: libraryLocation.structuredNotesDirectoryURL,
      structuredListNotesDirectoryURL: libraryLocation.structuredListNotesDirectoryURL,
      attachmentsRootURL: attachmentsRootDirectoryURL()
    )
  }

  // Returns the restore safety archive directory, creating it if needed.
  func restoreSafetyArchiveDirectoryURL() throws -> URL {
    try libraryLocation.restoreSafetyArchiveDirectoryURL(fileManager: fileManager)
  }

  // Reads the list-note manifest, returning empty when the file is missing or invalid.
  func loadListNotesManifest() -> ListNotesManifest {
    guard
      let data = try? Data(contentsOf: manifestFileURL()),
      let manifest = try? JSONDecoder().decode(ListNotesManifest.self, from: data)
    else {
      return .empty
    }

    return manifest
  }

  // Writes the list-note manifest using the current pretty-printed JSON format.
  func saveListNotesManifest(_ manifest: ListNotesManifest) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(manifest)
    try data.write(to: manifestFileURL(), options: .atomic)
  }

  // Loads and reconciles the isolated structured list-note ordering manifest.
  func loadStructuredListNotesManifest(noteIDs: Set<String>) throws -> ListNotesManifest {
    var manifest = decodedManifest(at: structuredManifestFileURL())
    reconcileManifest(&manifest, with: noteIDs)
    try saveStructuredListNotesManifest(manifest)
    return manifest
  }

  // Strictly reads the structured list manifest without reconciling archive source data.
  func loadStructuredListNotesManifestForArchive(
    noteIDs: Set<String>
  ) throws -> ListNotesManifest {
    let manifest = try decodeManifestForArchive(
      at: structuredManifestFileURL(),
      invalidError: LibraryRepositoryError.invalidStructuredManifest
    )
    guard manifest.allNoteIDs == noteIDs else {
      throw LibraryRepositoryError.structuredManifestMismatch
    }
    return manifest
  }

  // Writes list-library grouping separately from within-note structured groups.
  func saveStructuredListNotesManifest(_ manifest: ListNotesManifest) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(manifest)
    try fileManager.createDirectory(
      at: libraryLocation.structuredListNotesDirectoryURL,
      withIntermediateDirectories: true
    )
    try data.write(to: structuredManifestFileURL(), options: .atomic)
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

  private func structuredManifestFileURL() -> URL {
    libraryLocation.structuredListNotesDirectoryURL.appendingPathComponent(Self.manifestFileName)
  }

  private func decodedManifest(at fileURL: URL) -> ListNotesManifest {
    guard let data = try? Data(contentsOf: fileURL),
      let manifest = try? JSONDecoder().decode(ListNotesManifest.self, from: data)
    else { return .empty }
    return manifest
  }

  // Treats a missing manifest as an empty library but never hides malformed archive source data.
  private func decodeManifestForArchive(
    at fileURL: URL,
    invalidError: (Error) -> LibraryRepositoryError
  ) throws -> ListNotesManifest {
    guard fileManager.fileExists(atPath: fileURL.path) else { return .empty }
    do {
      return try JSONDecoder().decode(
        ListNotesManifest.self,
        from: Data(contentsOf: fileURL)
      )
    } catch {
      throw invalidError(error)
    }
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

enum LibraryRepositoryError: LocalizedError {
  case manifestMismatch
  case structuredManifestMismatch
  case invalidLegacyManifest(Error)
  case invalidStructuredManifest(Error)

  var errorDescription: String? {
    switch self {
    case .manifestMismatch:
      return "The legacy list-note manifest does not match the list notes on disk."
    case .structuredManifestMismatch:
      return "The structured list-note manifest does not match the list notes on disk."
    case .invalidLegacyManifest(let error):
      return "The legacy list-note manifest is invalid. \(error.localizedDescription)"
    case .invalidStructuredManifest(let error):
      return "The structured list-note manifest is invalid. \(error.localizedDescription)"
    }
  }
}
