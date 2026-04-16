import Foundation
import XCTest

@testable import Sceal

@MainActor
final class ScealBackupArchiveExporterTests: NotesStoreTestCase {
  func testBackupArchiveContainsDailyNotesListNotesManifestAndMetadata() throws {
    let dailyNote = makeDailyNote(year: 2026, month: 4, day: 16, title: "Daily", body: "Daily body")
    let listNote = makeListNote(
      id: "2026-04-16-abcdef",
      year: 2026,
      month: 4,
      day: 16,
      title: "List",
      body: "List body"
    )
    let manifest = ListNotesManifest(
      ungroupedNoteIDs: [listNote.id],
      groups: [NoteGroup(name: "Pinned", noteIDs: [listNote.id])]
    )

    let archiveURL = try ScealBackupArchiveExporter.exportBackup(
      dailyNotes: [dailyNote],
      listNotes: [listNote],
      manifest: manifest,
      kind: .manual,
      createdAt: makeDate(year: 2026, month: 4, day: 16)
    )
    defer {
      ZipArchiveWriter.cleanUp(zipURL: archiveURL)
    }

    let unzipDirectoryURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: unzipDirectoryURL, withIntermediateDirectories: true)
    defer {
      try? FileManager.default.removeItem(at: unzipDirectoryURL)
    }

    try unzipArchive(at: archiveURL, to: unzipDirectoryURL)

    let rootURL = try XCTUnwrap(extractedBackupRootURL(in: unzipDirectoryURL))
    let dailyNoteURL = rootURL.appendingPathComponent("Notes/\(dailyNote.fileName)")
    let listNoteURL = rootURL.appendingPathComponent("ListNotes/\(listNote.fileName)")
    let manifestURL = rootURL.appendingPathComponent("ListNotes/groups.json")
    let metadataURL = rootURL.appendingPathComponent("backup-metadata.json")

    XCTAssertTrue(FileManager.default.fileExists(atPath: dailyNoteURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: listNoteURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: manifestURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: metadataURL.path))

    let metadata = try JSONDecoder().decode(
      BackupArchiveMetadata.self,
      from: Data(contentsOf: metadataURL)
    )
    XCTAssertEqual(metadata.backupKind, .manual)
    XCTAssertEqual(metadata.dailyNoteCount, 1)
    XCTAssertEqual(metadata.listNoteCount, 1)
    XCTAssertTrue(metadata.includesManifest)
  }

  private func unzipArchive(at archiveURL: URL, to destinationURL: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    process.arguments = ["-x", "-k", archiveURL.path, destinationURL.path]

    try process.run()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
  }

  private func extractedBackupRootURL(in unzipDirectoryURL: URL) -> URL? {
    let directRootURL = unzipDirectoryURL
    if FileManager.default.fileExists(
      atPath: directRootURL.appendingPathComponent("backup-metadata.json").path
    ) {
      return directRootURL
    }

    let nestedRootURL = unzipDirectoryURL.appendingPathComponent(
      ScealBackupArchiveExporter.managedFolderName,
      isDirectory: true
    )
    if FileManager.default.fileExists(
      atPath: nestedRootURL.appendingPathComponent("backup-metadata.json").path
    ) {
      return nestedRootURL
    }

    return nil
  }
}
