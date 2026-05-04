import Foundation
import XCTest

@testable import Sceal

@MainActor
final class ScealBackupArchiveExporterTests: NotesStoreTestCase {
  func testBackupArchiveContainsDailyNotesListNotesManifestAndMetadata() throws {
    let dailyNote = makeDailyNote(
      year: 2026,
      month: 4,
      day: 16,
      title: "Daily",
      body: "![Desk](../Attachments/2026-04-16/desk.png)"
    )
    let listNote = makeListNote(
      id: "2026-04-16-abcdef",
      year: 2026,
      month: 4,
      day: 16,
      title: "List",
      body: "![Plan](../Attachments/2026-04-16-abcdef/plan.png)"
    )
    let manifest = ListNotesManifest(
      ungroupedNoteIDs: [],
      groups: [NoteGroup(name: "Pinned", noteIDs: [listNote.id])]
    )
    let attachmentsRootURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let dailyAttachmentDirectoryURL = attachmentsRootURL.appendingPathComponent(
      dailyNote.id,
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: dailyAttachmentDirectoryURL,
      withIntermediateDirectories: true
    )
    try Data("image".utf8).write(
      to: dailyAttachmentDirectoryURL.appendingPathComponent("desk.png")
    )
    let listAttachmentDirectoryURL = attachmentsRootURL.appendingPathComponent(
      listNote.id,
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: listAttachmentDirectoryURL,
      withIntermediateDirectories: true
    )
    try Data("plan".utf8).write(
      to: listAttachmentDirectoryURL.appendingPathComponent("plan.png")
    )
    addTeardownBlock {
      try? FileManager.default.removeItem(at: attachmentsRootURL)
    }

    let archiveURL = try ScealBackupArchiveExporter.exportBackup(
      dailyNotes: [dailyNote],
      listNotes: [listNote],
      manifest: manifest,
      kind: .manual,
      createdAt: makeDate(year: 2026, month: 4, day: 16),
      attachmentsRootURL: attachmentsRootURL
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
    let attachmentURL = rootURL.appendingPathComponent("Attachments/\(dailyNote.id)/desk.png")
    let listAttachmentURL = rootURL.appendingPathComponent(
      "Attachments/\(listNote.id)/plan.png"
    )

    XCTAssertTrue(FileManager.default.fileExists(atPath: dailyNoteURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: listNoteURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: manifestURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: metadataURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: attachmentURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: listAttachmentURL.path))

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
