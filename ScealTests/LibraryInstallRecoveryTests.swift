import Foundation
import XCTest

@testable import Sceal

@MainActor
final class LibraryInstallRecoveryTests: NotesStoreTestCase {
  private let folderNames = ["StructuredNotes", "StructuredListNotes", "Attachments"]

  // Reopening the journal models process loss before/after each real directory replacement.
  func testRestartRollsBackEveryInstallationBoundaryIncludingMissingDestination() throws {
    for installedCount in 0...folderNames.count {
      for removeNextDestination in [false, true] {
        let location = makeLibraryLocation()
        try seedLibrary(at: location, title: "Before")
        let before = try snapshot(location)
        let transaction = try prepare(at: location)
        for name in folderNames.prefix(installedCount) {
          try transaction.installFolder(named: name)
        }
        if removeNextDestination, installedCount < folderNames.count {
          try FileManager.default.removeItem(
            at: location.rootURL.appendingPathComponent(folderNames[installedCount]))
        }
        let restarted = try XCTUnwrap(LibraryInstallTransaction.read(at: location.rootURL))
        try restarted.rollback()
        XCTAssertEqual(try snapshot(location), before)
        XCTAssertNil(try LibraryInstallTransaction.read(at: location.rootURL))
      }
    }
  }

  // Recovery copies remain immutable even if recovery itself loses a live folder mid-rollback.
  func testRestartCanRepeatInterruptedRollbackWithoutLosingOriginals() throws {
    let location = makeLibraryLocation()
    try seedLibrary(at: location, title: "Before")
    let before = try snapshot(location)
    let transaction = try prepare(at: location)
    for name in folderNames { try transaction.installFolder(named: name) }
    let dailyURL = location.structuredNotesDirectoryURL
    try FileManager.default.removeItem(at: dailyURL)
    try FileManager.default.copyItem(
      at: transaction.workspaceURL.appendingPathComponent("Original/StructuredNotes"), to: dailyURL)
    try FileManager.default.removeItem(at: location.structuredListNotesDirectoryURL)
    try XCTUnwrap(LibraryInstallTransaction.read(at: location.rootURL)).rollback()
    XCTAssertEqual(try snapshot(location), before)
  }

  // A partial first conversion returns to conversion-required, never a completed empty library.
  func testFirstConversionInterruptionPreservesMarkdownAndDoesNotSeedStructuredNotes() throws {
    let location = makeLibraryLocation()
    let note = makeDailyNote(year: 2026, month: 9, day: 1, body: "Original Markdown")
    try LibraryRepository(libraryLocation: location).saveDailyNote(note)
    let markdownURL = location.legacyNotesDirectoryURL.appendingPathComponent(note.fileName)
    let originalData = try Data(contentsOf: markdownURL)
    let transaction = try prepare(at: location)
    try transaction.installFolder(named: "StructuredNotes")
    let defaults = makeUserDefaults()
    SettingsRepository(userDefaults: defaults).saveStructuredNotesCutoverStatus(.recoveryRequired)
    let store = makeStore(
      userDefaults: defaults, libraryLocation: location, enforcesStructuredCutover: true)
    store.prepareStructuredCutoverForProductionLaunch()
    XCTAssertFalse(store.hasLoaded)
    XCTAssertFalse(store.isLibraryRecoveryBlocked)
    XCTAssertEqual(store.structuredNotesCutoverStatus, .conversionRequired)
    XCTAssertTrue(try StructuredNoteRepository(libraryLocation: location).loadDocuments().isEmpty)
    XCTAssertEqual(try Data(contentsOf: markdownURL), originalData)
    XCTAssertFalse(try StructuredLibraryState.isCompleted(at: location))
  }

  // Validated file installs replay all portable configuration before exposing the new library.
  func testRestartFinishesSettingsTemplatesAndCompletionThenDoesNotReplayOnLaterLaunch() throws {
    let location = makeLibraryLocation()
    try seedLibrary(at: location, title: "Before")
    let defaults = makeUserDefaults()
    let store = makeStore(
      userDefaults: defaults, libraryLocation: location, enforcesStructuredCutover: true)
    let bookmark = Data("existing local permission".utf8)
    store.backupSettingsStore.configureFolder(
      bookmarkData: bookmark, displayPath: "/Volumes/Existing")
    try store.backupSettingsStore.persistSettings()
    var transaction = try prepare(at: location)
    for name in folderNames { try transaction.installFolder(named: name) }
    try transaction.markAwaitingConfiguration()
    let expectedSettings = try XCTUnwrap(transaction.record.configuration.settings)
    store.prepareStructuredCutoverForProductionLaunch()
    XCTAssertTrue(store.hasLoaded)
    XCTAssertFalse(store.isLibraryRecoveryBlocked)
    XCTAssertEqual(store.structuredNotes.first?.title, "After")
    XCTAssertEqual(
      store.noteTemplates.map(\.id), transaction.record.configuration.templates.map(\.id))
    XCTAssertEqual(
      store.continuousSpellCheckingEnabled, expectedSettings.continuousSpellCheckingEnabled)
    XCTAssertFalse(store.continuousSpellCheckingEnabled)
    XCTAssertEqual(store.newNoteDefault, .blank)
    XCTAssertEqual(store.backupSettings.folderBookmarkData, bookmark)
    XCTAssertTrue(try StructuredLibraryState.isCompleted(at: location))
    XCTAssertNil(try LibraryInstallTransaction.read(at: location.rootURL))

    var edited = try XCTUnwrap(store.structuredNotes.first)
    edited.title = "Later edit"
    try StructuredNoteRepository(libraryLocation: location).save(edited)
    let relaunched = makeStore(
      userDefaults: defaults, libraryLocation: location, enforcesStructuredCutover: true)
    relaunched.prepareStructuredCutoverForProductionLaunch()
    XCTAssertEqual(relaunched.structuredNotes.first?.title, "Later edit")
  }

  // Configuration failure must retain the journal and installed data for a retry, not enable stale editors.
  func testCompletionWriteFailureBlocksEditingAndBackupUntilRetrySucceeds() throws {
    let location = makeLibraryLocation()
    try seedLibrary(at: location, title: "Before")
    var transaction = try prepare(at: location)
    for name in folderNames { try transaction.installFolder(named: name) }
    try transaction.markAwaitingConfiguration()
    let installed = try snapshot(location)
    try FileManager.default.createDirectory(
      at: location.structuredLibraryStateURL, withIntermediateDirectories: true)
    let store = makeStore(libraryLocation: location, enforcesStructuredCutover: true)
    store.prepareStructuredCutoverForProductionLaunch()
    XCTAssertTrue(store.isLibraryRecoveryBlocked)
    XCTAssertFalse(store.hasLoaded)
    XCTAssertFalse(store.canBeginLibraryFileOperation())
    XCTAssertThrowsError(try store.makeLibrarySnapshot())
    store.continueUsingLegacyForNow()
    XCTAssertTrue(store.isLibraryRecoveryBlocked)
    XCTAssertFalse(store.hasLoaded)
    XCTAssertEqual(try snapshot(location), installed)
    XCTAssertEqual(
      try LibraryInstallTransaction.read(at: location.rootURL)?.record.phase, .configuration)
    try FileManager.default.removeItem(at: location.structuredLibraryStateURL)
    store.prepareStructuredCutoverForProductionLaunch()
    XCTAssertTrue(store.hasLoaded)
    XCTAssertFalse(store.isLibraryRecoveryBlocked)
    XCTAssertNil(try LibraryInstallTransaction.read(at: location.rootURL))
  }

  // Both launch routes must reject damaged metadata without rewriting it or loading an editable library.
  func testMalformedJournalBlocksDebugAndProductionLoadingWithoutChangingFiles() throws {
    for production in [false, true] {
      let location = makeLibraryLocation()
      try seedLibrary(at: location, title: "Before")
      let before = try snapshot(location)
      let damaged = Data("not a recovery record".utf8)
      let journalURL = LibraryInstallTransaction.journalURL(in: location.rootURL)
      try damaged.write(to: journalURL)
      let store = makeStore(libraryLocation: location, enforcesStructuredCutover: production)
      if production {
        store.prepareStructuredCutoverForProductionLaunch()
      } else {
        store.loadIfNeeded()
      }
      XCTAssertTrue(store.isLibraryRecoveryBlocked)
      XCTAssertFalse(store.hasLoaded)
      XCTAssertEqual(try snapshot(location), before)
      XCTAssertEqual(try Data(contentsOf: journalURL), damaged)
      XCTAssertThrowsError(try store.makeLibrarySnapshot())
    }
  }

  // Corrupt recovery copies or changed installed bytes are retained for manual recovery, not guessed away.
  func testDamagedCopiesAndInstalledFilesBlockRecoveryWithoutDiscardingJournal() throws {
    for installed in [false, true] {
      let location = makeLibraryLocation()
      try seedLibrary(at: location, title: "Before")
      var transaction = try prepare(at: location)
      if installed {
        for name in folderNames { try transaction.installFolder(named: name) }
        try transaction.markAwaitingConfiguration()
      }
      let damagedRoot =
        installed
        ? location.structuredNotesDirectoryURL
        : transaction.workspaceURL.appendingPathComponent("Original/StructuredNotes")
      try Data("unexpected file".utf8).write(to: damagedRoot.appendingPathComponent("damage.txt"))
      let store = makeStore(libraryLocation: location, enforcesStructuredCutover: true)
      store.prepareStructuredCutoverForProductionLaunch()
      XCTAssertTrue(store.isLibraryRecoveryBlocked)
      XCTAssertFalse(store.hasLoaded)
      XCTAssertNotNil(try LibraryInstallTransaction.read(at: location.rootURL))
      XCTAssertTrue(
        FileManager.default.fileExists(
          atPath: damagedRoot.appendingPathComponent("damage.txt").path))
    }
  }

  // An existing journal cannot be superseded by a second install, conversion, or restore request.
  func testPendingTransactionRejectsNewLibraryOperations() throws {
    let location = makeLibraryLocation()
    try seedLibrary(at: location, title: "Before")
    let store = makeStore(libraryLocation: location)
    let beforeSnapshot = try store.makeLibrarySnapshot()
    _ = try prepare(at: location)
    XCTAssertThrowsError(try prepare(at: location))
    XCTAssertThrowsError(try store.makeLibrarySnapshot())
    XCTAssertThrowsError(
      try StructuredLibraryCutover.perform(
        snapshot: beforeSnapshot, sourceDailyDocuments: [], sourceListDocuments: [],
        libraryLocation: location
      ))
    let archive = try ScealBackupArchiveExporter.exportBackup(
      dailyNotes: [], listNotes: [], manifest: .empty, kind: .manual)
    defer { ZipArchiveWriter.cleanUp(zipURL: archive) }
    XCTAssertThrowsError(
      try ScealBackupArchiveImporter.restoreLibrary(
        from: archive, currentDailyNotes: [], currentListNotes: [], currentManifest: .empty,
        destinationURLs: LibraryRepository(libraryLocation: location).storageURLs(),
        safetyArchiveDirectoryURL: location.restoreSafetyArchiveDirectoryURL()
      ))
  }

  func testFailedFolderReplacementKeepsJournalForSuccessfulRollbackRetry() throws {
    let location = makeLibraryLocation()
    try seedLibrary(at: location, title: "Before")
    let before = try snapshot(location)
    let transaction = try prepare(at: location)
    try transaction.installFolder(named: "StructuredNotes")
    let protected = location.structuredListNotesDirectoryURL
    let permissions = try XCTUnwrap(
      FileManager.default.attributesOfItem(atPath: protected.path)[.posixPermissions])
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: permissions], ofItemAtPath: protected.path)
    }
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: protected.path)
    XCTAssertThrowsError(try transaction.installFolder(named: "StructuredListNotes"))
    XCTAssertNotNil(try LibraryInstallTransaction.read(at: location.rootURL))
    try FileManager.default.setAttributes(
      [.posixPermissions: permissions], ofItemAtPath: protected.path)
    try XCTUnwrap(LibraryInstallTransaction.read(at: location.rootURL)).rollback()
    XCTAssertEqual(try snapshot(location), before)
  }

  // Old pre-journal rollback folders cannot safely establish which files were installed.
  func testUntrackedOlderRollbackRequiresRecoveryAndRemainsUntouched() throws {
    let location = makeLibraryLocation()
    let recoveryURL = location.rootURL.appendingPathComponent(".sceal-structured-rollback-old")
    try LibraryArchiveFiles(files: ["keep.txt": Data("original".utf8)]).write(to: recoveryURL)
    let store = makeStore(libraryLocation: location, enforcesStructuredCutover: true)
    store.prepareStructuredCutoverForProductionLaunch()
    XCTAssertTrue(store.isLibraryRecoveryBlocked)
    XCTAssertFalse(store.hasLoaded)
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: recoveryURL.appendingPathComponent("keep.txt").path))
  }

  // Persisted committed state only needs cleanup and must never restore older snapshots over later edits.
  func testCommittedJournalCleanupDoesNotReplayConfigurationOrRollback() throws {
    let location = makeLibraryLocation()
    try seedLibrary(at: location, title: "Before")
    let transaction = try prepare(at: location)
    var record = transaction.record
    record.phase = .committed
    try JSONEncoder().encode(record).write(
      to: LibraryInstallTransaction.journalURL(in: location.rootURL), options: .atomic)
    let before = try snapshot(location)
    let store = makeStore(libraryLocation: location)
    try store.recoverPendingLibraryInstallation()
    XCTAssertEqual(try snapshot(location), before)
    XCTAssertNil(try LibraryInstallTransaction.read(at: location.rootURL))
  }

  // Real repositories produce valid fixtures so recovery also exercises normal launch validation.
  private func seedLibrary(at location: ScealLibraryLocation, title: String) throws {
    var document = StructuredNoteDocument.empty(
      id: "2026-09-01", date: makeDate(year: 2026, month: 9, day: 1))
    document.title = title
    try StructuredNoteRepository(libraryLocation: location).save(document)
    try LibraryRepository(libraryLocation: location).saveStructuredListNotesManifest(.empty)
    try LibraryArchiveFiles(files: ["orphan/image.png": Data(title.utf8)]).write(
      to: location.rootURL.appendingPathComponent("Attachments"))
  }

  // The same durable preparation used by conversion/restore can be paused between actual filesystem steps.
  private func prepare(at location: ScealLibraryLocation) throws -> LibraryInstallTransaction {
    let staged = makeLibraryLocation()
    try seedLibrary(at: staged, title: "After")
    let settingsStore = makeStore()
    settingsStore.updateContinuousSpellCheckingEnabled(false)
    settingsStore.updateNewNoteDefault(.template("missing-from-restored-templates"))
    let settings = try settingsStore.makeArchiveSettings().normalizedForStructuredRuntime()
    return try LibraryInstallTransaction.prepare(
      at: location.rootURL,
      replacements: Dictionary(
        uniqueKeysWithValues: folderNames.map { ($0, staged.rootURL.appendingPathComponent($0)) }),
      configuration: LibraryInstallTransaction.Configuration(
        settings: settings, templates: [NoteTemplate.starterMeeting])
    )
  }

  private func snapshot(_ location: ScealLibraryLocation) throws -> [String: LibraryArchiveFiles] {
    try Dictionary(
      uniqueKeysWithValues: folderNames.map { name in
        (name, try LibraryArchiveFiles.read(from: location.rootURL.appendingPathComponent(name)))
      })
  }
}
