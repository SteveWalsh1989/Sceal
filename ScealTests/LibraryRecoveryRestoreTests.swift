import Foundation
import XCTest

@testable import Sceal

@MainActor
final class LibraryRecoveryRestoreTests: NotesStoreTestCase {
  // Recovery accepts both historical backups and current structured backups without parsing damaged live notes.
  func testRecoveryPreservesDamagedLibraryAndRestoresBothArchiveGenerations() throws {
    for structured in [false, true] {
      let location = makeLibraryLocation()
      let original = LibraryArchiveFiles(files: [
        "Notes/2026-09-01.md": Data("unparseable original daily source".utf8),
        "ListNotes/project.md": Data("unparseable original list source".utf8),
        "StructuredNotes/damaged.scealnote": Data("broken document".utf8),
        ".sceal-install.json": Data("broken journal".utf8),
        "structured-library.json": Data("broken completion".utf8),
        "Attachments/shared.txt": Data("old image".utf8),
        "Attachments/orphan.txt": Data("keep orphan".utf8),
      ])
      try original.write(to: location.rootURL)
      let source = makeLibraryLocation()
      try LibraryArchiveFiles(files: ["shared.txt": Data("archived image".utf8)])
        .write(to: source.rootURL.appendingPathComponent("Attachments"))
      let note = makeDailyNote(
        year: 2026, month: 9, day: 2, title: "Recovered", body: "# Heading\n\n- [ ] Keep")
      let document = try LegacyMarkdownStructuredNoteAdapter.importDocument(note)
      let store = makeStore(libraryLocation: location, enforcesStructuredCutover: true)
      let settings = try store.makeArchiveSettings().normalizedForStructuredRuntime()
      let archive = try ScealBackupArchiveExporter.exportBackup(
        dailyNotes: structured ? [] : [note], listNotes: [], manifest: .empty,
        templates: [NoteTemplate.starterMeeting],
        structuredDailyNotes: structured ? [document] : [],
        structuredListManifest: structured ? .empty : nil, settings: structured ? settings : nil,
        authority: structured ? .structured : .legacy, kind: .manual,
        attachmentsRootURL: source.rootURL.appendingPathComponent("Attachments"))
      defer { ZipArchiveWriter.cleanUp(zipURL: archive) }
      store.loadIfNeeded()
      XCTAssertFalse(store.isLibraryReadyForEditing)
      let preserved = try LibraryRecoveryRestore.perform(
        from: archive, at: location, settings: settings, templates: [])
      addTeardownBlock { try? FileManager.default.removeItem(at: preserved) }
      let preservedFiles = try LibraryArchiveFiles.read(from: preserved).files
      for (path, bytes) in original.files { XCTAssertEqual(preservedFiles[path], bytes, path) }
      XCTAssertTrue(preservedFiles.keys.contains { $0.hasPrefix("Selected Archive ") })
      XCTAssertTrue(preservedFiles.keys.contains { $0.hasPrefix("Recovery Settings ") })
      XCTAssertTrue(preservedFiles.keys.contains { $0.hasPrefix("Recovery Templates ") })
      store.loadIfNeeded()
      XCTAssertTrue(store.isLibraryReadyForEditing)
      XCTAssertEqual(store.structuredNotes.map(\.title), ["Recovered"])
      if structured { XCTAssertEqual(store.structuredNotes, [document]) }
      XCTAssertEqual(store.noteTemplates.map(\.id), [NoteTemplate.starterMeeting.id])
      for path in ["Notes/2026-09-01.md", "ListNotes/project.md"] {
        XCTAssertEqual(
          try Data(contentsOf: location.rootURL.appendingPathComponent(path)), original.files[path])
      }
      XCTAssertEqual(
        try LibraryArchiveFiles.read(from: location.rootURL.appendingPathComponent("Attachments"))
          .files,
        ["shared.txt": Data("archived image".utf8), "orphan.txt": Data("keep orphan".utf8)])
      XCTAssertNil(try LibraryInstallTransaction.read(at: location.rootURL))
      XCTAssertFalse(
        FileManager.default.fileExists(
          atPath: LibraryInstallTransaction.recoveryHoldURL(in: location.rootURL).path))
      let reopened = makeStore(
        userDefaults: store.settingsRepository.userDefaults, libraryLocation: location,
        enforcesStructuredCutover: true)
      reopened.loadIfNeeded()
      XCTAssertTrue(reopened.isLibraryReadyForEditing)
      XCTAssertEqual(reopened.structuredNotes, store.structuredNotes)
      XCTAssertNoThrow(try reopened.makeLibrarySnapshot())
    }
  }

  // A rejected selection cannot retire recovery records or modify any current source bytes.
  func testInvalidArchiveLeavesCurrentLibraryUntouched() throws {
    let location = makeLibraryLocation()
    let original = LibraryArchiveFiles(files: [
      "Notes/source.md": Data("keep".utf8), ".sceal-install.json": Data("keep journal".utf8),
    ])
    try original.write(to: location.rootURL)
    let archive = location.rootURL.appendingPathComponent("invalid.zip")
    try Data("not a zip".utf8).write(to: archive)
    let before = try LibraryArchiveFiles.read(from: location.rootURL)
    XCTAssertThrowsError(
      try LibraryRecoveryRestore.perform(
        from: archive, at: location, settings: makeStore().makeArchiveSettings(), templates: []))
    XCTAssertEqual(try LibraryArchiveFiles.read(from: location.rootURL), before)
  }

  // A crash after the hold but before quarantine cannot commit an older pending installation.
  func testNewRecoveryHoldBlocksEveryPhaseOfAnOlderJournal() throws {
    for phase in [LibraryInstallTransaction.Phase.installing, .configuration, .committed] {
      let location = makeLibraryLocation()
      let staged = try emptyStructuredLibrary()
      var transaction = try LibraryInstallTransaction.prepare(
        at: location.rootURL, replacements: replacements(staged),
        configuration: .init(settings: nil, templates: []))
      for folder in transaction.record.folders { try transaction.installFolder(named: folder.name) }
      if phase != .installing { try transaction.markAwaitingConfiguration() }
      var record = transaction.record
      record.phase = phase
      try JSONEncoder().encode(record).write(
        to: LibraryInstallTransaction.journalURL(in: location.rootURL), options: .atomic)
      let preserved = try emptyStructuredLibrary()
      _ = try LibraryInstallTransaction.holdForRecovery(
        at: location.rootURL, preservedCopyURL: preserved.rootURL)
      let before = try LibraryArchiveFiles.read(from: location.rootURL)
      let store = makeStore(libraryLocation: location, enforcesStructuredCutover: true)
      store.loadIfNeeded()
      XCTAssertTrue(store.isLibraryRecoveryBlocked)
      XCTAssertFalse(store.isLibraryReadyForEditing)
      XCTAssertEqual(try LibraryArchiveFiles.read(from: location.rootURL), before)
    }
  }

  // Rolling back an interrupted recovery restore returns damaged originals, never an editable empty library.
  func testRecoveryRollbackRetainsHoldUntilAnotherExplicitRestore() throws {
    let location = makeLibraryLocation()
    let original = LibraryArchiveFiles(files: ["bad.scealnote": Data("damaged".utf8)])
    try original.write(to: location.structuredNotesDirectoryURL)
    let preserved = try emptyStructuredLibrary()
    let recoveryID = try LibraryInstallTransaction.holdForRecovery(
      at: location.rootURL, preservedCopyURL: preserved.rootURL)
    let transaction = try LibraryInstallTransaction.prepare(
      at: location.rootURL, replacements: replacements(preserved),
      configuration: .init(settings: nil, templates: []), recoveryID: recoveryID)
    try transaction.installFolder(named: "StructuredNotes")
    let store = makeStore(libraryLocation: location, enforcesStructuredCutover: true)
    store.loadIfNeeded()
    XCTAssertTrue(store.isLibraryRecoveryBlocked)
    XCTAssertFalse(store.hasLoaded)
    XCTAssertEqual(
      try LibraryArchiveFiles.read(from: location.structuredNotesDirectoryURL), original)
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: LibraryInstallTransaction.recoveryHoldURL(in: location.rootURL).path))
    XCTAssertThrowsError(try store.makeLibrarySnapshot())
  }

  // Journals published before recovery UI existed have no recovery ID and remain readable.
  func testHistoricalJournalWithoutRecoveryIDStillLoads() throws {
    let location = makeLibraryLocation()
    let staged = try emptyStructuredLibrary()
    let transaction = try LibraryInstallTransaction.prepare(
      at: location.rootURL, replacements: replacements(staged),
      configuration: .init(settings: nil, templates: []))
    let data = try Data(contentsOf: LibraryInstallTransaction.journalURL(in: location.rootURL))
    let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertNil(fields["recoveryID"])
    XCTAssertEqual(
      try LibraryInstallTransaction.read(at: location.rootURL)?.record.id, transaction.record.id)
  }

  private func emptyStructuredLibrary() throws -> ScealLibraryLocation {
    let location = makeLibraryLocation()
    _ = try StructuredNoteRepository(libraryLocation: location).loadDocuments()
    try LibraryRepository(libraryLocation: location).saveStructuredListNotesManifest(.empty)
    return location
  }

  private func replacements(_ location: ScealLibraryLocation) -> [String: URL] {
    [
      "StructuredNotes": location.structuredNotesDirectoryURL,
      "StructuredListNotes": location.structuredListNotesDirectoryURL,
    ]
  }
}
