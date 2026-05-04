import AppKit
import XCTest

@testable import Sceal

@MainActor
final class NoteImageAttachmentStoreTests: XCTestCase {
  func testCopyingImageFileStoresUnderNoteAttachmentFolder() throws {
    let temporaryDirectoryURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let sourceDirectoryURL = temporaryDirectoryURL.appendingPathComponent(
      "Source", isDirectory: true)
    let attachmentsRootURL = temporaryDirectoryURL.appendingPathComponent(
      "Attachments",
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: sourceDirectoryURL,
      withIntermediateDirectories: true
    )
    addTeardownBlock {
      try? FileManager.default.removeItem(at: temporaryDirectoryURL)
    }

    let sourceURL = sourceDirectoryURL.appendingPathComponent("Desk Photo.png")
    try Data("image".utf8).write(to: sourceURL)

    let stored = try NoteImageAttachmentStore.storeImageFile(
      from: sourceURL,
      for: "2026-05-04",
      rootURL: attachmentsRootURL
    )

    XCTAssertEqual(
      stored.relativePath,
      "../Attachments/2026-05-04/Desk-Photo.png"
    )
    XCTAssertEqual(stored.title, "Desk Photo")
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath:
          attachmentsRootURL
          .appendingPathComponent("2026-05-04/Desk-Photo.png")
          .path
      )
    )
  }

  func testRewritingAttachmentReferencesMovesPathsToNewNoteID() {
    let markdown = "![Desk](../Attachments/2026-05-04/desk.png)"

    XCTAssertEqual(
      NoteImageAttachmentStore.rewritingAttachmentReferences(
        in: markdown,
        from: "2026-05-04",
        to: "2026-05-05"
      ),
      "![Desk](../Attachments/2026-05-05/desk.png)"
    )
  }
}
