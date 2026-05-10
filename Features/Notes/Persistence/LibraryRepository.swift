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
