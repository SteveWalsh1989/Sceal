import Foundation
import XCTest

@testable import Sceal

@MainActor
final class MigrationArchiveFixtureTests: NotesStoreTestCase {
  func testBackupArchiveFromMigrationFixturesContainsExpectedLayoutAndDecodes() throws {
    let fixture = try makeFixtureLibrary()
    let archiveURL = try ScealBackupArchiveExporter.exportBackup(
      dailyNotes: fixture.dailyNotes,
      listNotes: fixture.listNotes,
      manifest: fixture.manifest,
      templates: fixture.templates,
      kind: .manual,
      createdAt: makeDate(year: 2026, month: 5, day: 10),
      attachmentsRootURL: fixture.attachmentsRootURL
    )
    defer {
      ZipArchiveWriter.cleanUp(zipURL: archiveURL)
    }

    let extractionURL = try makeTemporaryDirectory()
    try ZipArchiveWriter.extractZip(from: archiveURL, to: extractionURL)

    let rootURL = try XCTUnwrap(extractedBackupRootURL(in: extractionURL))
    let compositeURL = rootURL.appendingPathComponent("Notes/2026-05-10.md")
    let blankURL = rootURL.appendingPathComponent("Notes/2026-05-11.md")
    let listNoteURL = rootURL.appendingPathComponent("ListNotes/project-alpha.md")
    let manifestURL = rootURL.appendingPathComponent("ListNotes/groups.json")
    let metadataURL = rootURL.appendingPathComponent("backup-metadata.json")
    let templatesURL = rootURL.appendingPathComponent("Templates/templates.json")
    let dailyAttachmentURL = rootURL.appendingPathComponent(
      "Attachments/2026-05-10/desk-photo.png"
    )
    let listAttachmentURL = rootURL.appendingPathComponent(
      "Attachments/project-alpha/alpha-plan.txt"
    )

    assertFileExists(compositeURL)
    assertFileExists(blankURL)
    assertFileExists(listNoteURL)
    assertFileExists(manifestURL)
    assertFileExists(metadataURL)
    assertFileExists(templatesURL)
    assertFileExists(dailyAttachmentURL)
    assertFileExists(listAttachmentURL)

    let exportedComposite = try decodeDailyNote(at: compositeURL)
    let exportedBlank = try decodeDailyNote(at: blankURL)
    let exportedListNote = try decodeListNote(at: listNoteURL, idOverride: "project-alpha")
    XCTAssertEqual(exportedComposite.body, fixture.dailyNotes[0].body)
    XCTAssertEqual(exportedBlank.body, fixture.dailyNotes[1].body)
    XCTAssertEqual(exportedListNote.body, fixture.listNotes[0].body)
    XCTAssertEqual(
      try JSONDecoder().decode(ListNotesManifest.self, from: Data(contentsOf: manifestURL)),
      fixture.manifest
    )
    XCTAssertEqual(
      try JSONDecoder().decode([NoteTemplate].self, from: Data(contentsOf: templatesURL)),
      fixture.templates
    )

    let metadata = try JSONDecoder().decode(
      BackupArchiveMetadata.self,
      from: Data(contentsOf: metadataURL)
    )
    XCTAssertEqual(metadata.backupKind, .manual)
    XCTAssertEqual(metadata.dailyNoteCount, 2)
    XCTAssertEqual(metadata.listNoteCount, 1)
    XCTAssertEqual(metadata.templateCount, fixture.templates.count)
    XCTAssertTrue(metadata.includesManifest)
  }

  func testStandardExportFromMigrationFixturesPreservesDailyNotesAndCopiesOnlyDailyAttachments()
    throws
  {
    let fixture = try makeFixtureLibrary()
    let archiveURL = try ScealArchiveExporter.exportNotes(
      fixture.dailyNotes,
      templates: fixture.templates,
      attachmentsRootURL: fixture.attachmentsRootURL
    )
    defer {
      ZipArchiveWriter.cleanUp(zipURL: archiveURL)
    }

    let extractionURL = try makeTemporaryDirectory()
    try ZipArchiveWriter.extractZip(from: archiveURL, to: extractionURL)

    let rootURL = exportedRootURL(in: extractionURL)
    let compositeURL = rootURL.appendingPathComponent("2026/2026-05-10.md")
    let blankURL = rootURL.appendingPathComponent("2026/2026-05-11.md")
    let dailyAttachmentURL = rootURL.appendingPathComponent(
      "Attachments/2026-05-10/desk-photo.png"
    )
    let listAttachmentURL = rootURL.appendingPathComponent(
      "Attachments/project-alpha/alpha-plan.txt"
    )

    assertFileExists(compositeURL)
    assertFileExists(blankURL)
    assertFileExists(dailyAttachmentURL)
    XCTAssertFalse(FileManager.default.fileExists(atPath: listAttachmentURL.path))

    XCTAssertEqual(try decodeDailyNote(at: compositeURL).body, fixture.dailyNotes[0].body)
    XCTAssertEqual(try decodeDailyNote(at: blankURL).body, fixture.dailyNotes[1].body)
  }

  func testRestoreFromMigrationFixtureArchiveWritesSafetyBackupBeforeReplacingTempStorage()
    throws
  {
    let fixture = try makeFixtureLibrary()
    let archiveURL = try makeFixtureBackupArchive(from: fixture)
    let storageRootURL = try makeTemporaryDirectory()
    let storageURLs = makeStorageURLs(in: storageRootURL)
    let safetyDirectoryURL = try makeTemporaryDirectory()
    let oldDailyNote = makeDailyNote(
      year: 2026,
      month: 4,
      day: 9,
      title: "Old daily",
      body: "Old body"
    )
    let oldListNote = makeListNote(
      id: "old-list-note",
      year: 2026,
      month: 4,
      day: 9,
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
        AttachmentSeed(noteID: oldDailyNote.id, fileName: "old.txt", contents: "old attachment")
      ]
    )

    let result = try ScealBackupArchiveImporter.restoreLibrary(
      from: archiveURL,
      currentDailyNotes: [oldDailyNote],
      currentListNotes: [oldListNote],
      currentManifest: oldManifest,
      destinationURLs: storageURLs,
      safetyArchiveDirectoryURL: safetyDirectoryURL,
      createdAt: makeDate(year: 2026, month: 5, day: 10)
    )

    XCTAssertEqual(Set(result.dailyNotes.map(\.id)), ["2026-05-10", "2026-05-11"])
    XCTAssertEqual(result.listNotes.map(\.id), ["project-alpha"])
    XCTAssertEqual(result.manifest, fixture.manifest)
    assertFileExists(storageURLs.notesDirectoryURL.appendingPathComponent("2026-05-10.md"))
    assertFileExists(storageURLs.notesDirectoryURL.appendingPathComponent("2026-05-11.md"))
    assertFileExists(storageURLs.listNotesDirectoryURL.appendingPathComponent("project-alpha.md"))
    assertFileExists(
      storageURLs.attachmentsRootURL.appendingPathComponent("2026-05-10/desk-photo.png")
    )
    assertFileExists(
      storageURLs.attachmentsRootURL.appendingPathComponent("project-alpha/alpha-plan.txt")
    )
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: storageURLs.notesDirectoryURL.appendingPathComponent(oldDailyNote.fileName).path
      )
    )
    assertFileExists(result.safetyArchiveURL)

    let safetyExtractionURL = try makeTemporaryDirectory()
    try ZipArchiveWriter.extractZip(from: result.safetyArchiveURL, to: safetyExtractionURL)
    let safetyRootURL = try XCTUnwrap(extractedBackupRootURL(in: safetyExtractionURL))
    assertFileExists(safetyRootURL.appendingPathComponent("Notes/\(oldDailyNote.fileName)"))
    assertFileExists(
      safetyRootURL.appendingPathComponent("Attachments/\(oldDailyNote.id)/old.txt")
    )
  }

  func testRestoreRejectsFixtureArchiveWithManifestMismatchBeforeReplacingTempStorage() throws {
    let fixture = try makeFixtureLibrary()
    let archiveURL = try makeFixtureBackupArchive(from: fixture)
    let invalidArchiveURL = try makeMutatedArchive(from: archiveURL) { rootURL in
      let mismatchedManifest = ListNotesManifest(
        ungroupedNoteIDs: [],
        groups: []
      )
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      try encoder.encode(mismatchedManifest).write(
        to: rootURL.appendingPathComponent("ListNotes/groups.json"),
        options: .atomic
      )
    }
    let storageRootURL = try makeTemporaryDirectory()
    let storageURLs = makeStorageURLs(in: storageRootURL)
    let safetyDirectoryURL = try makeTemporaryDirectory()
    let existingNote = makeDailyNote(year: 2026, month: 4, day: 9, title: "Existing")
    try writeLibrary(
      storageURLs: storageURLs,
      dailyNotes: [existingNote],
      listNotes: [],
      manifest: .empty
    )

    XCTAssertThrowsError(
      try ScealBackupArchiveImporter.restoreLibrary(
        from: invalidArchiveURL,
        currentDailyNotes: [existingNote],
        currentListNotes: [],
        currentManifest: .empty,
        destinationURLs: storageURLs,
        safetyArchiveDirectoryURL: safetyDirectoryURL
      )
    ) { error in
      guard case ScealBackupArchiveImporterError.manifestMismatch = error else {
        return XCTFail("Expected manifest mismatch, got \(error).")
      }
    }
    assertFileExists(storageURLs.notesDirectoryURL.appendingPathComponent(existingNote.fileName))
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: storageURLs.notesDirectoryURL.appendingPathComponent("2026-05-10.md").path
      )
    )
    XCTAssertEqual(
      try FileManager.default.contentsOfDirectory(
        at: safetyDirectoryURL,
        includingPropertiesForKeys: nil
      ),
      []
    )
  }

  private struct FixtureLibrary {
    let dailyNotes: [DayNote]
    let listNotes: [DayNote]
    let manifest: ListNotesManifest
    let templates: [NoteTemplate]
    let attachmentsRootURL: URL
  }

  private struct AttachmentSeed {
    let noteID: DayNote.ID
    let fileName: String
    let contents: String
  }

  private func makeFixtureLibrary() throws -> FixtureLibrary {
    let compositeNote = try decodeDailyFixture(named: "2026-05-10-composite")
    let blankNote = try decodeDailyFixture(named: "2026-05-11-blank")
    let listNote = try decodeListFixture(named: "project-alpha", idOverride: "project-alpha")
    let manifest = try JSONDecoder().decode(
      ListNotesManifest.self,
      from: Data(contentsOf: try fixtureURL(named: "groups", fileExtension: "json"))
    )
    let attachmentsRootURL = try makeTemporaryDirectory()
    try copyFixtureAttachment(
      named: "desk-photo",
      fileExtension: "png",
      noteID: compositeNote.id,
      fileName: "desk-photo.png",
      to: attachmentsRootURL
    )
    try copyFixtureAttachment(
      named: "alpha-plan",
      fileExtension: "txt",
      noteID: listNote.id,
      fileName: "alpha-plan.txt",
      to: attachmentsRootURL
    )

    return FixtureLibrary(
      dailyNotes: [compositeNote, blankNote],
      listNotes: [listNote],
      manifest: manifest,
      templates: [.starterMeeting],
      attachmentsRootURL: attachmentsRootURL
    )
  }

  private func makeFixtureBackupArchive(from fixture: FixtureLibrary) throws -> URL {
    let archiveURL = try ScealBackupArchiveExporter.exportBackup(
      dailyNotes: fixture.dailyNotes,
      listNotes: fixture.listNotes,
      manifest: fixture.manifest,
      templates: fixture.templates,
      kind: .manual,
      createdAt: makeDate(year: 2026, month: 5, day: 10),
      attachmentsRootURL: fixture.attachmentsRootURL
    )
    addTeardownBlock {
      ZipArchiveWriter.cleanUp(zipURL: archiveURL)
    }
    return archiveURL
  }

  private func decodeDailyFixture(named resourceName: String) throws -> DayNote {
    let fileURL = try fixtureURL(named: resourceName, fileExtension: "md")
    return try MarkdownNoteCodec.decode(
      contents: String(contentsOf: fileURL, encoding: .utf8),
      sourceURL: fileURL
    )
  }

  private func decodeListFixture(named resourceName: String, idOverride: String) throws -> DayNote {
    let fileURL = try fixtureURL(named: resourceName, fileExtension: "md")
    return try MarkdownNoteCodec.decode(
      contents: String(contentsOf: fileURL, encoding: .utf8),
      sourceURL: fileURL,
      idOverride: idOverride
    )
  }

  private func decodeDailyNote(at fileURL: URL) throws -> DayNote {
    try MarkdownNoteCodec.decode(
      contents: String(contentsOf: fileURL, encoding: .utf8),
      sourceURL: fileURL
    )
  }

  private func decodeListNote(at fileURL: URL, idOverride: String) throws -> DayNote {
    try MarkdownNoteCodec.decode(
      contents: String(contentsOf: fileURL, encoding: .utf8),
      sourceURL: fileURL,
      idOverride: idOverride
    )
  }

  private func copyFixtureAttachment(
    named resourceName: String,
    fileExtension: String,
    noteID: DayNote.ID,
    fileName: String,
    to attachmentsRootURL: URL
  ) throws {
    let noteAttachmentDirectoryURL = attachmentsRootURL.appendingPathComponent(
      noteID,
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: noteAttachmentDirectoryURL,
      withIntermediateDirectories: true
    )
    try FileManager.default.copyItem(
      at: fixtureURL(named: resourceName, fileExtension: fileExtension),
      to: noteAttachmentDirectoryURL.appendingPathComponent(fileName)
    )
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

  private func makeMutatedArchive(
    from archiveURL: URL,
    mutate: (URL) throws -> Void
  ) throws -> URL {
    let extractionURL = try makeTemporaryDirectory()
    try ZipArchiveWriter.extractZip(from: archiveURL, to: extractionURL)
    let rootURL = try XCTUnwrap(extractedBackupRootURL(in: extractionURL))
    try mutate(rootURL)

    let outputDirectoryURL = try makeTemporaryDirectory()
    let mutatedArchiveURL = outputDirectoryURL.appendingPathComponent("mutated.zip")
    try ZipArchiveWriter.createZip(from: rootURL, to: mutatedArchiveURL)
    return mutatedArchiveURL
  }

  private func exportedRootURL(in extractionURL: URL) -> URL {
    let nestedRootURL = extractionURL.appendingPathComponent("sceal-export", isDirectory: true)
    if FileManager.default.fileExists(atPath: nestedRootURL.path) {
      return nestedRootURL
    }
    return extractionURL
  }

  private func extractedBackupRootURL(in extractionURL: URL) -> URL? {
    let directRootURL = extractionURL
    if FileManager.default.fileExists(
      atPath: directRootURL.appendingPathComponent("backup-metadata.json").path
    ) {
      return directRootURL
    }

    let nestedRootURL = extractionURL.appendingPathComponent(
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
        at: extractionURL,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      )) ?? []
    return contents.first {
      FileManager.default.fileExists(
        atPath: $0.appendingPathComponent("backup-metadata.json").path
      )
    }
  }

  private func fixtureURL(named resourceName: String, fileExtension: String) throws
    -> URL
  {
    guard
      let resourceURL = Bundle(for: Self.self).url(
        forResource: resourceName,
        withExtension: fileExtension
      )
    else {
      throw MigrationArchiveFixtureError.missingResource("\(resourceName).\(fileExtension)")
    }

    return resourceURL
  }

  private func assertFileExists(
    _ fileURL: URL,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), file: file, line: line)
  }
}

enum MigrationArchiveFixtureError: LocalizedError {
  case missingResource(String)

  var errorDescription: String? {
    switch self {
    case .missingResource(let name):
      return "Missing migration archive fixture resource: \(name)"
    }
  }
}
