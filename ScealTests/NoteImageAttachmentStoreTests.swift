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

  func testCopyingAttachmentsMergesWithoutReplacingExistingDestinationFiles() throws {
    let rootURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let sourceURL = rootURL.appendingPathComponent("source", isDirectory: true)
    let destinationURL = rootURL.appendingPathComponent("destination", isDirectory: true)
    try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: rootURL) }
    try Data("shared".utf8).write(to: sourceURL.appendingPathComponent("shared.png"))
    try Data("shared".utf8).write(to: destinationURL.appendingPathComponent("shared.png"))
    try Data("new".utf8).write(to: sourceURL.appendingPathComponent("new.png"))
    try Data("keep".utf8).write(to: destinationURL.appendingPathComponent("keep.png"))

    try NoteImageAttachmentStore.copyAttachments(
      from: "source",
      to: "destination",
      rootURL: rootURL
    )

    XCTAssertEqual(
      try Data(contentsOf: destinationURL.appendingPathComponent("keep.png")),
      Data("keep".utf8)
    )
    XCTAssertEqual(
      try Data(contentsOf: destinationURL.appendingPathComponent("new.png")),
      Data("new".utf8)
    )
  }

  func testCopyingAttachmentsRejectsConflictingDestinationBeforeWriting() throws {
    let rootURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let sourceURL = rootURL.appendingPathComponent("source", isDirectory: true)
    let destinationURL = rootURL.appendingPathComponent("destination", isDirectory: true)
    try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: rootURL) }
    try Data("source".utf8).write(to: sourceURL.appendingPathComponent("conflict.png"))
    try Data("destination".utf8).write(
      to: destinationURL.appendingPathComponent("conflict.png")
    )
    try Data("new".utf8).write(to: sourceURL.appendingPathComponent("new.png"))

    XCTAssertThrowsError(
      try NoteImageAttachmentStore.copyAttachments(
        from: "source",
        to: "destination",
        rootURL: rootURL
      )
    )
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: destinationURL.appendingPathComponent("new.png").path)
    )
  }

  func testCopyingAttachmentFoldersRejectsConflictWithoutReplacingExistingFolder() throws {
    let rootURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let sourceRootURL = rootURL.appendingPathComponent("source", isDirectory: true)
    let destinationRootURL = rootURL.appendingPathComponent("destination", isDirectory: true)
    let noteID = "2026-09-04"
    let sourceURL = sourceRootURL.appendingPathComponent(noteID, isDirectory: true)
    let destinationURL = destinationRootURL.appendingPathComponent(noteID, isDirectory: true)
    try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: rootURL) }
    try Data("source".utf8).write(to: sourceURL.appendingPathComponent("conflict.png"))
    try Data("destination".utf8).write(
      to: destinationURL.appendingPathComponent("conflict.png")
    )
    try Data("keep".utf8).write(to: destinationURL.appendingPathComponent("keep.png"))

    XCTAssertThrowsError(
      try NoteImageAttachmentStore.copyAttachmentFolders(
        for: [noteID],
        from: sourceRootURL,
        to: destinationRootURL
      )
    )
    XCTAssertEqual(
      try Data(contentsOf: destinationURL.appendingPathComponent("conflict.png")),
      Data("destination".utf8)
    )
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: destinationURL.appendingPathComponent("keep.png").path)
    )
  }
}
