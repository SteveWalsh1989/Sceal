import Foundation
import XCTest

@testable import Sceal

@MainActor
final class ScealArchiveExporterTests: NotesStoreTestCase {
  func testExportArchiveIncludesNoteAttachments() throws {
    let note = makeDailyNote(
      year: 2026,
      month: 5,
      day: 4,
      body: "![Desk](../Attachments/2026-05-04/desk.png)"
    )
    let attachmentsRootURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let noteAttachmentDirectoryURL = attachmentsRootURL.appendingPathComponent(
      note.id,
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: noteAttachmentDirectoryURL,
      withIntermediateDirectories: true
    )
    try Data("image".utf8).write(to: noteAttachmentDirectoryURL.appendingPathComponent("desk.png"))
    addTeardownBlock {
      try? FileManager.default.removeItem(at: attachmentsRootURL)
    }

    let archiveURL = try ScealArchiveExporter.exportNotes(
      [note],
      attachmentsRootURL: attachmentsRootURL
    )
    defer {
      ZipArchiveWriter.cleanUp(zipURL: archiveURL)
    }

    let unzipDirectoryURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: unzipDirectoryURL,
      withIntermediateDirectories: true
    )
    defer {
      try? FileManager.default.removeItem(at: unzipDirectoryURL)
    }

    try unzipArchive(at: archiveURL, to: unzipDirectoryURL)

    let rootURL = exportedRootURL(in: unzipDirectoryURL)
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath:
          rootURL
          .appendingPathComponent("Attachments/2026-05-04/desk.png")
          .path
      )
    )
  }

  private func unzipArchive(at archiveURL: URL, to destinationURL: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    process.arguments = ["-x", "-k", archiveURL.path, destinationURL.path]

    try process.run()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
  }

  private func exportedRootURL(in unzipDirectoryURL: URL) -> URL {
    let nestedRootURL = unzipDirectoryURL.appendingPathComponent("sceal-export", isDirectory: true)
    if FileManager.default.fileExists(
      atPath: nestedRootURL.appendingPathComponent("Attachments").path
    ) {
      return nestedRootURL
    }

    return unzipDirectoryURL
  }
}
