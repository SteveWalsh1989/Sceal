import Foundation
import XCTest

@testable import Sceal

@MainActor
final class ScealBackupArchiveImporterTests: NotesStoreTestCase {
  func testRestoreLibraryPreservesOriginalSourcesAndInstallsStructuredContentWithSafetyArchive()
    throws
  {
    let storageRootURL = try makeTemporaryDirectory()
    let storageURLs = makeStorageURLs(in: storageRootURL)
    let safetyDirectoryURL = try makeTemporaryDirectory()
    let oldDailyNote = makeDailyNote(
      year: 2026,
      month: 4,
      day: 10,
      title: "Old daily",
      body: "Old body"
    )
    let oldListNote = makeListNote(
      id: "2026-04-10-oldold",
      year: 2026,
      month: 4,
      day: 10,
      title: "Old list",
      body: "Old list body"
    )
    let oldManifest = ListNotesManifest(
      ungroupedNoteIDs: [oldListNote.id],
      groups: []
    )
    try writeLibrary(
      storageURLs: storageURLs,
      dailyNotes: [oldDailyNote],
      listNotes: [oldListNote],
      manifest: oldManifest,
      attachments: [
        AttachmentSeed(noteID: oldDailyNote.id, fileName: "old.png", contents: "old image")
      ]
    )

    let restoredDailyNote = makeDailyNote(
      year: 2026,
      month: 5,
      day: 4,
      title: "Restored daily",
      body: "![Desk](../Attachments/2026-05-04/desk.png)"
    )
    let restoredListNote = makeListNote(
      id: "2026-05-04-abcdef",
      year: 2026,
      month: 5,
      day: 4,
      title: "Restored list",
      body: "![Plan](../Attachments/2026-05-04-abcdef/plan.png)"
    )
    let restoredManifest = ListNotesManifest(
      ungroupedNoteIDs: [],
      groups: [NoteGroup(name: "Pinned", noteIDs: [restoredListNote.id], isCollapsed: true)]
    )
    let archiveURL = try makeArchive(
      dailyNotes: [restoredDailyNote],
      listNotes: [restoredListNote],
      manifest: restoredManifest,
      attachments: [
        AttachmentSeed(noteID: restoredDailyNote.id, fileName: "desk.png", contents: "image"),
        AttachmentSeed(noteID: restoredListNote.id, fileName: "plan.png", contents: "plan"),
      ]
    )

    let originalSources = try LegacyArchiveSourceFiles.read(
      dailyURL: storageURLs.notesDirectoryURL, listURL: storageURLs.listNotesDirectoryURL
    )
    let result = try ScealBackupArchiveImporter.restoreLibrary(
      from: archiveURL,
      currentDailyNotes: [oldDailyNote],
      currentListNotes: [oldListNote],
      currentManifest: oldManifest,
      destinationURLs: storageURLs,
      safetyArchiveDirectoryURL: safetyDirectoryURL,
      createdAt: makeDate(year: 2026, month: 5, day: 5)
    )

    XCTAssertEqual(result.dailyNotes, [oldDailyNote])
    XCTAssertEqual(result.listNotes, [oldListNote])
    XCTAssertEqual(result.manifest, oldManifest)
    XCTAssertEqual(
      try LegacyArchiveSourceFiles.read(
        dailyURL: storageURLs.notesDirectoryURL, listURL: storageURLs.listNotesDirectoryURL
      ), originalSources)
    XCTAssertEqual(
      try Data(contentsOf: result.retainedArchiveURL), try Data(contentsOf: archiveURL))
    XCTAssertEqual(result.structuredDailyNotes.map(\.id), [restoredDailyNote.id])
    XCTAssertEqual(result.structuredListNotes.map(\.id), [restoredListNote.id])
    XCTAssertEqual(result.structuredListManifest, restoredManifest)
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: storageURLs.notesDirectoryURL.appendingPathComponent(
          restoredDailyNote.fileName
        ).path
      )
    )
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: storageURLs.notesDirectoryURL.appendingPathComponent(oldDailyNote.fileName).path
      )
    )
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: storageURLs.attachmentsRootURL.appendingPathComponent(
          "\(restoredDailyNote.id)/desk.png"
        ).path
      )
    )
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: storageURLs.attachmentsRootURL.appendingPathComponent(
          "\(restoredListNote.id)/plan.png"
        ).path
      )
    )

    let restoredManifestData = try Data(
      contentsOf: storageURLs.listNotesDirectoryURL.appendingPathComponent("groups.json")
    )
    XCTAssertEqual(
      try JSONDecoder().decode(ListNotesManifest.self, from: restoredManifestData), oldManifest
    )
    XCTAssertTrue(FileManager.default.fileExists(atPath: result.safetyArchiveURL.path))
    XCTAssertEqual(
      try StructuredNoteDocumentCodec.read(
        from: storageURLs.structuredNotesDirectoryURL
          .appendingPathComponent(restoredDailyNote.id)
          .appendingPathExtension(StructuredNoteRepository.fileExtension)
      ).title,
      restoredDailyNote.title
    )

    let safetyExtractURL = try makeTemporaryDirectory()
    try ZipArchiveWriter.extractZip(from: result.safetyArchiveURL, to: safetyExtractURL)
    let safetyRootURL = try XCTUnwrap(extractedBackupRootURL(in: safetyExtractURL))
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: safetyRootURL.appendingPathComponent("Notes/\(oldDailyNote.fileName)").path
      )
    )
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: safetyRootURL.appendingPathComponent("Attachments/\(oldDailyNote.id)/old.png").path
      )
    )
  }

  func testRestoreRejectsArchiveMissingMetadataBeforeReplacingStorage() throws {
    let storageRootURL = try makeTemporaryDirectory()
    let storageURLs = makeStorageURLs(in: storageRootURL)
    let safetyDirectoryURL = try makeTemporaryDirectory()
    let existingNote = makeDailyNote(year: 2026, month: 4, day: 10, title: "Existing")
    let replacementNote = makeDailyNote(year: 2026, month: 5, day: 4, title: "Replacement")
    try writeLibrary(
      storageURLs: storageURLs,
      dailyNotes: [existingNote],
      listNotes: [],
      manifest: .empty
    )
    let archiveURL = try makeArchive(
      dailyNotes: [replacementNote],
      listNotes: [],
      manifest: .empty
    )
    let invalidArchiveURL = try makeMutatedArchive(from: archiveURL) { rootURL in
      try FileManager.default.removeItem(
        at: rootURL.appendingPathComponent("backup-metadata.json")
      )
    }

    XCTAssertThrowsError(
      try ScealBackupArchiveImporter.restoreLibrary(
        from: invalidArchiveURL,
        currentDailyNotes: [existingNote],
        currentListNotes: [],
        currentManifest: .empty,
        destinationURLs: storageURLs,
        safetyArchiveDirectoryURL: safetyDirectoryURL
      )
    )
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: storageURLs.notesDirectoryURL.appendingPathComponent(existingNote.fileName).path
      )
    )
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: storageURLs.notesDirectoryURL.appendingPathComponent(replacementNote.fileName).path
      )
    )
  }

  func testRestoreRejectsCorruptNoteBeforeReplacingStorage() throws {
    let storageRootURL = try makeTemporaryDirectory()
    let storageURLs = makeStorageURLs(in: storageRootURL)
    let safetyDirectoryURL = try makeTemporaryDirectory()
    let existingNote = makeDailyNote(year: 2026, month: 4, day: 10, title: "Existing")
    let corruptNote = makeDailyNote(year: 2026, month: 5, day: 4, title: "Corrupt")
    try writeLibrary(
      storageURLs: storageURLs,
      dailyNotes: [existingNote],
      listNotes: [],
      manifest: .empty
    )
    let archiveURL = try makeArchive(
      dailyNotes: [corruptNote],
      listNotes: [],
      manifest: .empty
    )
    let invalidArchiveURL = try makeMutatedArchive(from: archiveURL) { rootURL in
      try "not markdown".write(
        to: rootURL.appendingPathComponent("Notes/\(corruptNote.fileName)"),
        atomically: true,
        encoding: .utf8
      )
    }

    XCTAssertThrowsError(
      try ScealBackupArchiveImporter.restoreLibrary(
        from: invalidArchiveURL,
        currentDailyNotes: [existingNote],
        currentListNotes: [],
        currentManifest: .empty,
        destinationURLs: storageURLs,
        safetyArchiveDirectoryURL: safetyDirectoryURL
      )
    )
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: storageURLs.notesDirectoryURL.appendingPathComponent(existingNote.fileName).path
      )
    )
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: storageURLs.notesDirectoryURL.appendingPathComponent(corruptNote.fileName).path
      )
    )
  }

  private struct AttachmentSeed {
    let noteID: DayNote.ID
    let fileName: String
    let contents: String
  }

  private func makeTemporaryDirectory() throws -> URL {
    let directoryURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    addTeardownBlock {
      try? FileManager.default.removeItem(at: directoryURL)
    }
    return directoryURL
  }

  private func makeStorageURLs(in rootURL: URL) -> ScealLibraryStorageURLs {
    ScealLibraryStorageURLs(
      notesDirectoryURL: rootURL.appendingPathComponent("Notes", isDirectory: true),
      listNotesDirectoryURL: rootURL.appendingPathComponent("ListNotes", isDirectory: true),
      attachmentsRootURL: rootURL.appendingPathComponent("Attachments", isDirectory: true)
    )
  }

  private func writeLibrary(
    storageURLs: ScealLibraryStorageURLs,
    dailyNotes: [DayNote],
    listNotes: [DayNote],
    manifest: ListNotesManifest,
    attachments: [AttachmentSeed] = []
  ) throws {
    try FileManager.default.createDirectory(
      at: storageURLs.notesDirectoryURL,
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: storageURLs.listNotesDirectoryURL,
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: storageURLs.attachmentsRootURL,
      withIntermediateDirectories: true
    )

    for note in dailyNotes {
      try MarkdownNoteCodec.encode(note).write(
        to: storageURLs.notesDirectoryURL.appendingPathComponent(note.fileName),
        atomically: true,
        encoding: .utf8
      )
    }

    for note in listNotes {
      try MarkdownNoteCodec.encode(note).write(
        to: storageURLs.listNotesDirectoryURL.appendingPathComponent(note.fileName),
        atomically: true,
        encoding: .utf8
      )
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(manifest).write(
      to: storageURLs.listNotesDirectoryURL.appendingPathComponent("groups.json"),
      options: .atomic
    )

    for attachment in attachments {
      let attachmentDirectoryURL = storageURLs.attachmentsRootURL.appendingPathComponent(
        attachment.noteID,
        isDirectory: true
      )
      try FileManager.default.createDirectory(
        at: attachmentDirectoryURL,
        withIntermediateDirectories: true
      )
      try Data(attachment.contents.utf8).write(
        to: attachmentDirectoryURL.appendingPathComponent(attachment.fileName)
      )
    }
  }

  private func makeArchive(
    dailyNotes: [DayNote],
    listNotes: [DayNote],
    manifest: ListNotesManifest,
    attachments: [AttachmentSeed] = []
  ) throws -> URL {
    let attachmentRootURL = try makeTemporaryDirectory()

    for attachment in attachments {
      let attachmentDirectoryURL = attachmentRootURL.appendingPathComponent(
        attachment.noteID,
        isDirectory: true
      )
      try FileManager.default.createDirectory(
        at: attachmentDirectoryURL,
        withIntermediateDirectories: true
      )
      try Data(attachment.contents.utf8).write(
        to: attachmentDirectoryURL.appendingPathComponent(attachment.fileName)
      )
    }

    let archiveURL = try ScealBackupArchiveExporter.exportBackup(
      dailyNotes: dailyNotes,
      listNotes: listNotes,
      manifest: manifest,
      kind: .manual,
      createdAt: makeDate(year: 2026, month: 5, day: 4),
      attachmentsRootURL: attachmentRootURL
    )
    addTeardownBlock {
      ZipArchiveWriter.cleanUp(zipURL: archiveURL)
    }
    return archiveURL
  }

  private func makeMutatedArchive(
    from archiveURL: URL,
    mutate: (URL) throws -> Void
  ) throws -> URL {
    let extractURL = try makeTemporaryDirectory()
    try ZipArchiveWriter.extractZip(from: archiveURL, to: extractURL)
    let rootURL = try XCTUnwrap(extractedBackupRootURL(in: extractURL))
    try mutate(rootURL)

    let outputDirectoryURL = try makeTemporaryDirectory()
    let mutatedArchiveURL = outputDirectoryURL.appendingPathComponent("mutated.zip")
    try ZipArchiveWriter.createZip(from: rootURL, to: mutatedArchiveURL)
    return mutatedArchiveURL
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

    let contents =
      (try? FileManager.default.contentsOfDirectory(
        at: unzipDirectoryURL,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      )) ?? []
    return contents.first {
      FileManager.default.fileExists(
        atPath: $0.appendingPathComponent("backup-metadata.json").path
      )
    }
  }
}
