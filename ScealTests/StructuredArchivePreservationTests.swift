import Foundation
import XCTest

@testable import Sceal

@MainActor
final class StructuredArchivePreservationTests: NotesStoreTestCase {
  // Recovery bytes are archival evidence, not a prerequisite for protecting current documents.
  func testStructuredSnapshotBacksUpMalformedRecoveryFilesAndRestoresExactActiveDocuments() throws {
    let location = makeLibraryLocation()
    let repository = LibraryRepository(libraryLocation: location)
    let sourceFiles = LegacyArchiveSourceFiles(
      daily: LibraryArchiveFiles(files: ["2026-09-01.md": Data([0xFF, 0xFE, 0xFF])]),
      list: LibraryArchiveFiles(files: [
        "old-list.md": Data([0xFF]), "groups.json": Data("broken manifest".utf8),
        "Recovery/readme.txt": Data("Keep this too".utf8),
      ])
    )
    let storage = try repository.storageURLs()
    try sourceFiles.daily.write(to: storage.notesDirectoryURL)
    try sourceFiles.list.write(to: storage.listNotesDirectoryURL)
    let document = StructuredNoteDocument(
      id: "2026-09-01", date: makeDate(year: 2026, month: 9, day: 1), title: "Current", tags: [],
      nodes: [.section(StructuredNoteSection(markdown: "Current content"))]
    )
    try StructuredNoteRepository(libraryLocation: location).save(document)
    let store = makeStore(libraryLocation: location)
    let snapshot = try store.makeLibrarySnapshot()
    XCTAssertEqual(snapshot.authority, .structured)
    XCTAssertEqual(snapshot.legacySourceFiles, sourceFiles)
    XCTAssertTrue(snapshot.legacyDailyNotes.isEmpty)
    let archiveURL = try export(snapshot)
    let rootURL = try extract(archiveURL)
    XCTAssertEqual(
      try LegacyArchiveSourceFiles.read(
        dailyURL: rootURL.appendingPathComponent("Notes"),
        listURL: rootURL.appendingPathComponent("ListNotes")
      ), sourceFiles)

    let destination = makeLibraryLocation()
    let result = try restore(archiveURL, at: destination)
    XCTAssertEqual(result.structuredDailyNotes, [document])
    XCTAssertEqual(
      try StructuredNoteRepository(libraryLocation: destination).loadDocuments(), [document])
    XCTAssertEqual(
      try Data(contentsOf: result.retainedArchiveURL), try Data(contentsOf: archiveURL))
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: destination.legacyNotesDirectoryURL.appendingPathComponent("2026-09-01.md").path))
    XCTAssertEqual(
      try LegacyArchiveSourceFiles.read(
        dailyURL: storage.notesDirectoryURL, listURL: storage.listNotesDirectoryURL
      ), sourceFiles)

    let restoredStore = makeStore(libraryLocation: destination)
    try restoredStore.completeStructuredCutoverAfterValidatedRestore()
    let nextArchiveURL = try export(restoredStore.makeLibrarySnapshot())
    let secondRestore = try restore(nextArchiveURL, at: makeLibraryLocation())
    XCTAssertEqual(secondRestore.structuredDailyNotes, [document])
  }

  // Explicit archive authority determines whether old notes are imported into structured storage.
  func testArchiveAuthorityControlsLegacyImportIncludingEmptyStructuredLibrary() throws {
    let legacy = makeDailyNote(year: 2026, month: 9, day: 1, body: "Legacy only")
    let store = makeStore()
    for authority in [ScealArchiveAuthority.legacy, .structured] {
      let settings = try store.makeArchiveSettings()
      let archiveURL = try ScealBackupArchiveExporter.exportBackup(
        dailyNotes: [legacy], listNotes: [], manifest: .empty,
        structuredListManifest: .empty, settings: settings, authority: authority, kind: .manual
      )
      defer { ZipArchiveWriter.cleanUp(zipURL: archiveURL) }
      let result = try restore(archiveURL, at: makeLibraryLocation())
      XCTAssertEqual(result.metadata.structuredStorageIsAuthoritative, authority == .structured)
      XCTAssertEqual(result.structuredDailyNotes.map(\.id), authority == .legacy ? [legacy.id] : [])
    }
  }

  // A malformed active legacy note must still fail rather than silently disappearing.
  func testLegacyAuthoritativeArchiveStillRejectsMalformedMarkdown() throws {
    let archiveURL = try ScealBackupArchiveExporter.exportBackup(
      dailyNotes: [], listNotes: [], manifest: .empty,
      settings: makeStore().makeArchiveSettings(), authority: .legacy,
      legacySourceFiles: LegacyArchiveSourceFiles(
        daily: LibraryArchiveFiles(files: ["2026-09-01.md": Data([0xFF])]),
        list: LibraryArchiveFiles()
      ), kind: .manual
    )
    defer { ZipArchiveWriter.cleanUp(zipURL: archiveURL) }
    let destination = makeLibraryLocation()
    XCTAssertThrowsError(try restore(archiveURL, at: destination))
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: destination.structuredNotesDirectoryURL.path))
  }

  // Same-path images must match the restored note; old and unreferenced images remain recoverable.
  func testAttachmentConflictsUseArchiveBytesAndPreservePreviousBytesInSafetyBackup() throws {
    let destination = makeLibraryLocation()
    let repository = LibraryRepository(libraryLocation: destination)
    let oldFiles = LibraryArchiveFiles(files: [
      "2026-09-01/image.png": Data("old image".utf8), "recovery-only/old.png": Data("orphan".utf8),
    ])
    try oldFiles.write(to: repository.attachmentsRootURL)
    let incoming = makeLibraryLocation()
    let incomingRepository = LibraryRepository(libraryLocation: incoming)
    let incomingFiles = LibraryArchiveFiles(files: [
      "2026-09-01/image.png": Data("incoming image".utf8),
      "unreferenced/new.png": Data("new orphan".utf8),
    ])
    try incomingFiles.write(to: incomingRepository.attachmentsRootURL)
    let note = makeDailyNote(
      year: 2026, month: 9, day: 1, body: "![Image](../Attachments/2026-09-01/image.png)")
    let archiveURL = try ScealBackupArchiveExporter.exportBackup(
      dailyNotes: [note], listNotes: [], manifest: .empty, kind: .manual,
      attachmentsRootURL: incomingRepository.attachmentsRootURL
    )
    defer { ZipArchiveWriter.cleanUp(zipURL: archiveURL) }
    let result = try restore(archiveURL, at: destination)
    var expectedFiles = oldFiles
    expectedFiles.files.merge(incomingFiles.files) { _, incoming in incoming }
    XCTAssertEqual(try LibraryArchiveFiles.read(from: repository.attachmentsRootURL), expectedFiles)
    let safetyRoot = try extract(result.safetyArchiveURL)
    XCTAssertEqual(
      try LibraryArchiveFiles.read(from: safetyRoot.appendingPathComponent("Attachments")), oldFiles
    )
    let restoredStore = makeStore(libraryLocation: destination)
    try restoredStore.completeStructuredCutoverAfterValidatedRestore()
    let nextArchive = try export(
      restoredStore.makeLibrarySnapshot(), attachmentsRootURL: repository.attachmentsRootURL)
    let nextRoot = try extract(nextArchive)
    XCTAssertEqual(
      try LibraryArchiveFiles.read(from: nextRoot.appendingPathComponent("Attachments")),
      expectedFiles)
  }

  // A failed second folder move must not delete an original that was never moved.
  func testCaughtRestoreMoveFailureRollsBackMovedFoldersWithoutDeletingUntouchedStorage() throws {
    let location = makeLibraryLocation()
    let repository = LibraryRepository(libraryLocation: location)
    let storage = try repository.storageURLs()
    let lockedParent = location.rootURL.appendingPathComponent("Locked", isDirectory: true)
    let lockedStructuredURL = lockedParent.appendingPathComponent(
      "StructuredNotes", isDirectory: true)
    let protectedFiles = LibraryArchiveFiles(files: ["keep.txt": Data("untouched".utf8)])
    try protectedFiles.write(to: lockedStructuredURL)
    let oldAttachments = LibraryArchiveFiles(files: [
      "orphan/image.png": Data("before restore".utf8)
    ])
    try oldAttachments.write(to: storage.attachmentsRootURL)
    try protectedFiles.write(to: storage.notesDirectoryURL)
    try protectedFiles.write(to: storage.listNotesDirectoryURL)
    let originalSources = try LegacyArchiveSourceFiles.read(
      dailyURL: storage.notesDirectoryURL, listURL: storage.listNotesDirectoryURL
    )
    let archiveURL = try ScealBackupArchiveExporter.exportBackup(
      dailyNotes: [], listNotes: [], manifest: .empty, kind: .manual
    )
    defer { ZipArchiveWriter.cleanUp(zipURL: archiveURL) }
    let permissions = try XCTUnwrap(
      FileManager.default.attributesOfItem(atPath: lockedParent.path)[.posixPermissions])
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: permissions], ofItemAtPath: lockedParent.path)
    }
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o500], ofItemAtPath: lockedParent.path)
    XCTAssertThrowsError(
      try ScealBackupArchiveImporter.restoreLibrary(
        from: archiveURL, currentDailyNotes: [], currentListNotes: [], currentManifest: .empty,
        destinationURLs: ScealLibraryStorageURLs(
          notesDirectoryURL: storage.notesDirectoryURL,
          listNotesDirectoryURL: storage.listNotesDirectoryURL,
          structuredNotesDirectoryURL: lockedStructuredURL,
          structuredListNotesDirectoryURL: storage.structuredListNotesDirectoryURL,
          attachmentsRootURL: storage.attachmentsRootURL
        ), safetyArchiveDirectoryURL: makeLibraryLocation().rootURL
      ))
    XCTAssertEqual(try LibraryArchiveFiles.read(from: lockedStructuredURL), protectedFiles)
    XCTAssertEqual(try LibraryArchiveFiles.read(from: storage.attachmentsRootURL), oldAttachments)
    XCTAssertEqual(
      try LegacyArchiveSourceFiles.read(
        dailyURL: storage.notesDirectoryURL, listURL: storage.listNotesDirectoryURL
      ), originalSources)
  }

  // Unreadable files and links must surface an error, never produce a partial success-shaped backup.
  func testRawRecoverySnapshotRejectsUnreadableFilesAndSymlinks() throws {
    let location = makeLibraryLocation()
    let fileURL = location.rootURL.appendingPathComponent("2026-09-01.md")
    try LibraryArchiveFiles(files: [fileURL.lastPathComponent: Data("recovery".utf8)]).write(
      to: location.rootURL)
    let permissions = try XCTUnwrap(
      FileManager.default.attributesOfItem(atPath: fileURL.path)[.posixPermissions])
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: permissions], ofItemAtPath: fileURL.path)
    }
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: fileURL.path)
    XCTAssertThrowsError(try LibraryArchiveFiles.read(from: location.rootURL))
    try FileManager.default.setAttributes(
      [.posixPermissions: permissions], ofItemAtPath: fileURL.path)
    let linkURL = location.rootURL.appendingPathComponent("link.md")
    try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: fileURL)
    XCTAssertThrowsError(try LibraryArchiveFiles.read(from: location.rootURL))
  }

  // Source changes after snapshot preparation must stop restore before replacement starts.
  func testChangedOriginalSourcesRejectRestoreBeforeWritingSafetyOrReplacingStorage() throws {
    let location = makeLibraryLocation()
    let storage = try LibraryRepository(libraryLocation: location).storageURLs()
    let archiveURL = try ScealBackupArchiveExporter.exportBackup(
      dailyNotes: [], listNotes: [], manifest: .empty, kind: .manual
    )
    defer { ZipArchiveWriter.cleanUp(zipURL: archiveURL) }
    let safetyURL = makeLibraryLocation().rootURL
    XCTAssertThrowsError(
      try ScealBackupArchiveImporter.restoreLibrary(
        from: archiveURL, currentDailyNotes: [], currentListNotes: [], currentManifest: .empty,
        currentLegacySourceFiles: LegacyArchiveSourceFiles(
          daily: LibraryArchiveFiles(files: ["missing.md": Data("changed".utf8)]),
          list: LibraryArchiveFiles()
        ), destinationURLs: storage, safetyArchiveDirectoryURL: safetyURL
      ))
    XCTAssertFalse(FileManager.default.fileExists(atPath: safetyURL.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: storage.structuredNotesDirectoryURL.path))
  }

  // Keep archive integration tests on disposable, real ZIPs and filesystem roots.
  private func export(_ snapshot: ScealLibrarySnapshot, attachmentsRootURL: URL? = nil) throws
    -> URL
  {
    let archiveURL = try ScealBackupArchiveExporter.exportBackup(
      dailyNotes: snapshot.legacyDailyNotes, listNotes: snapshot.legacyListNotes,
      manifest: snapshot.legacyListManifest,
      templates: snapshot.templates, structuredDailyNotes: snapshot.structuredDailyNotes,
      structuredListNotes: snapshot.structuredListNotes,
      structuredListManifest: snapshot.structuredListManifest,
      settings: snapshot.settings, authority: snapshot.authority,
      legacySourceFiles: snapshot.legacySourceFiles,
      kind: .manual, attachmentsRootURL: attachmentsRootURL
    )
    addTeardownBlock { ZipArchiveWriter.cleanUp(zipURL: archiveURL) }
    return archiveURL
  }

  // Extract inside a separately cleaned test root so retained archive contents can be compared.
  private func extract(_ archiveURL: URL) throws -> URL {
    let rootURL = makeLibraryLocation().rootURL
    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    try ZipArchiveWriter.extractZip(from: archiveURL, to: rootURL)
    let nestedURL = rootURL.appendingPathComponent(ScealBackupArchiveExporter.managedFolderName)
    return FileManager.default.fileExists(atPath: nestedURL.path) ? nestedURL : rootURL
  }

  // Empty-target restores exercise conversion and retention without modifying a real library.
  private func restore(_ archiveURL: URL, at location: ScealLibraryLocation) throws
    -> ScealBackupArchiveImporter.RestoreResult
  {
    try ScealBackupArchiveImporter.restoreLibrary(
      from: archiveURL, currentDailyNotes: [], currentListNotes: [], currentManifest: .empty,
      destinationURLs: LibraryRepository(libraryLocation: location).storageURLs(),
      safetyArchiveDirectoryURL: location.restoreSafetyArchiveDirectoryURL()
    )
  }
}
