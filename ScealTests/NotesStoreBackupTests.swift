import Foundation
import XCTest

@testable import Sceal

@MainActor
final class NotesStoreBackupTests: NotesStoreTestCase {
  // A failed disk write must not let a snapshot silently use the previous saved document.
  func testSnapshotRejectsFailedStructuredSaveAndRetriesLatestEdits() throws {
    for isListNote in [false, true] {
      let location = makeLibraryLocation()
      let repository =
        isListNote
        ? StructuredNoteRepository.listNotes(libraryLocation: location)
        : StructuredNoteRepository(libraryLocation: location)
      let document = StructuredNoteDocument.empty(
        id: "2026-09-05", date: makeDate(year: 2026, month: 9, day: 5)
      )
      try repository.save(document)
      let store = makeStore(libraryLocation: location)
      store.sidebarMode = isListNote ? .list : .daily
      if isListNote {
        try store.loadStructuredListNotesIfNeeded()
      } else {
        try store.loadStructuredDailyNotesIfNeeded()
      }
      store.structuredTitleBinding(for: document.id).wrappedValue = "Latest edit"

      try withReadOnlyDirectory(repository.storageDirectoryURL) {
        XCTAssertThrowsError(try store.makeLibrarySnapshot())
        XCTAssertThrowsError(try store.makeLibrarySnapshot())
        XCTAssertEqual(try repository.loadDocuments().first?.title, document.title)
        store.structuredTitleBinding(for: document.id).wrappedValue = "Latest edit after failure"
        XCTAssertThrowsError(try store.makeLibrarySnapshot())
        let cutoverStatus = store.structuredNotesCutoverStatus
        store.backUpAndConvertLegacyLibrary()
        XCTAssertEqual(store.structuredNotesCutoverStatus, cutoverStatus)
        XCTAssertFalse(store.isPerformingFileOperation)
      }

      let snapshot = try store.makeLibrarySnapshot()
      let documents = isListNote ? snapshot.structuredListNotes : snapshot.structuredDailyNotes
      XCTAssertEqual(documents.first?.title, "Latest edit after failure")
      XCTAssertTrue(store.pendingStructuredNoteSaveTasks.isEmpty)
    }
  }

  // The debounce path must retain failed edits too, not only an explicit flush attempt.
  func testFailedDebouncedSaveRemainsRetryable() async throws {
    let location = makeLibraryLocation()
    let repository = StructuredNoteRepository(libraryLocation: location)
    let document = StructuredNoteDocument.empty(
      id: "2026-09-05", date: makeDate(year: 2026, month: 9, day: 5)
    )
    try repository.save(document)
    let store = makeStore(libraryLocation: location)
    try store.loadStructuredDailyNotesIfNeeded()
    let directoryURL = repository.storageDirectoryURL
    let attributes = try FileManager.default.attributesOfItem(atPath: directoryURL.path)
    let permissions = try XCTUnwrap(attributes[.posixPermissions])
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: permissions], ofItemAtPath: directoryURL.path
      )
    }
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o500], ofItemAtPath: directoryURL.path)
    store.structuredTitleBinding(for: document.id).wrappedValue = "Debounced edit"
    for _ in 0..<100 where store.userMessage?.kind != .error {
      try await Task.sleep(nanoseconds: 20_000_000)
    }
    XCTAssertEqual(store.userMessage?.kind, .error)
    XCTAssertThrowsError(try store.makeLibrarySnapshot())
    try FileManager.default.setAttributes(
      [.posixPermissions: permissions], ofItemAtPath: directoryURL.path
    )
    store.flushPendingSaves()
    XCTAssertEqual(try repository.loadDocuments().first?.title, "Debounced edit")
    XCTAssertTrue(store.pendingStructuredNoteSaveTasks.isEmpty)
  }

  // No backup may report success or write an archive after its save barrier fails.
  func testManualAndAutomaticBackupsReportSnapshotSaveFailure() throws {
    for trigger in [BackupTrigger.manual, .periodicTimer] {
      let location = makeLibraryLocation()
      let repository = StructuredNoteRepository(libraryLocation: location)
      let document = StructuredNoteDocument.empty(
        id: "2026-09-05", date: makeDate(year: 2026, month: 9, day: 5)
      )
      try repository.save(document)
      let store = makeStore(libraryLocation: location)
      try store.loadStructuredDailyNotesIfNeeded()
      let backupFolder = try configureBackup(for: store)
      store.structuredTitleBinding(for: document.id).wrappedValue = "Unsaved edit"

      try withReadOnlyDirectory(repository.storageDirectoryURL) {
        startBackup(store, trigger: trigger)
        XCTAssertFalse(store.isBackupRunning)
        XCTAssertFalse(store.isPerformingFileOperation)
        XCTAssertNil(store.backupSettings.lastSuccessfulBackupAt)
        XCTAssertNotNil(store.backupSettings.lastAttemptedBackupAt)
        XCTAssertNotNil(store.backupSettings.lastBackupErrorDescription)
        XCTAssertEqual(store.userMessage?.kind, .error)
        XCTAssertTrue(
          try FileManager.default.contentsOfDirectory(atPath: backupFolder.path).isEmpty
        )
      }
      XCTAssertEqual(
        try store.makeLibrarySnapshot().structuredDailyNotes.first?.title, "Unsaved edit")
    }
  }

  // Restoring real generated ZIPs proves both triggers use the latest daily/list snapshots.
  func testManualScheduledAndPostImportBackupsRestoreLatestMatchingIDs() async throws {
    for trigger in [BackupTrigger.manual, .periodicTimer, .postImport] {
      let location = makeLibraryLocation()
      let document = StructuredNoteDocument.empty(
        id: "2026-09-05", date: makeDate(year: 2026, month: 9, day: 5)
      )
      try StructuredNoteRepository(libraryLocation: location).save(document)
      try StructuredNoteRepository.listNotes(libraryLocation: location).save(document)
      let store = makeStore(libraryLocation: location)
      try store.loadStructuredDailyNotesIfNeeded()
      try store.loadStructuredListNotesIfNeeded()
      let backupFolder = try configureBackup(for: store)
      store.sidebarMode = .daily
      store.structuredTitleBinding(for: document.id).wrappedValue = "Newest daily title"
      store.sidebarMode = .list
      store.structuredTitleBinding(for: document.id).wrappedValue = "Newest list title"

      startBackup(store, trigger: trigger)
      XCTAssertTrue(store.isBackupRunning)
      for _ in 0..<250 where store.isBackupRunning {
        try await Task.sleep(nanoseconds: 20_000_000)
      }
      XCTAssertFalse(store.isBackupRunning)
      XCTAssertNil(store.backupSettings.lastBackupErrorDescription)
      let archiveName = try XCTUnwrap(store.backupSettings.lastBackupArchiveName)
      let target = makeLibraryLocation()
      let result = try ScealBackupArchiveImporter.restoreLibrary(
        from: backupFolder.appendingPathComponent(archiveName),
        currentDailyNotes: [], currentListNotes: [], currentManifest: .empty,
        destinationURLs: LibraryRepository(libraryLocation: target).storageURLs(),
        safetyArchiveDirectoryURL: target.restoreSafetyArchiveDirectoryURL()
      )
      XCTAssertEqual(result.structuredDailyNotes, store.structuredNotes)
      XCTAssertEqual(result.structuredListNotes, store.structuredListNotes)
      XCTAssertEqual(result.structuredListManifest, store.structuredListNoteManifest)
      XCTAssertEqual(result.metadata.structuredStorageIsAuthoritative, true)
    }
  }

  // Busy operations retain their progress state and defer backups without marking an attempt.
  func testBackupsDoNotOverlapLibraryFileOperations() throws {
    let store = makeStore()
    _ = try configureBackup(for: store)
    store.isPerformingFileOperation = true
    store.progressMessage = "Restoring library..."
    for trigger in [BackupTrigger.manual, .periodicTimer, .postImport] {
      startBackup(store, trigger: trigger)
      XCTAssertFalse(store.isBackupRunning)
      XCTAssertTrue(store.isPerformingFileOperation)
      XCTAssertEqual(store.progressMessage, "Restoring library...")
      XCTAssertNil(store.backupSettings.lastAttemptedBackupAt)
    }
  }

  // These public entry points must reject an active automatic backup before opening a panel.
  func testImportExportAndRestoreDoNotStartDuringAutomaticBackup() {
    let store = makeStore()
    store.isBackupRunning = true
    store.importFromSceal()
    store.exportFullLibrary()
    store.exportNotes(startDate: .now, endDate: .now)
    store.restoreFullLibraryFromArchive()
    XCTAssertTrue(store.isBackupRunning)
    XCTAssertFalse(store.isPerformingFileOperation)
    XCTAssertNotNil(store.userMessage)
  }

  // Uses an isolated security-scoped folder just like the real backup destination.
  private func configureBackup(for store: NotesStore) throws -> URL {
    let folder = makeLibraryLocation().rootURL
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let bookmark = try folder.bookmarkData(
      options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil
    )
    store.backupSettingsStore.configureFolder(bookmarkData: bookmark, displayPath: folder.path)
    store.updateBackupSchedule(.hourly)
    let managedFolder = ScealBackupArchiveExporter.managedBackupDirectoryURL(in: folder)
    try FileManager.default.createDirectory(at: managedFolder, withIntermediateDirectories: true)
    return managedFolder
  }

  // Exercises the same public trigger entry points as the app and periodic scheduler.
  private func startBackup(_ store: NotesStore, trigger: BackupTrigger) {
    if trigger == .manual {
      store.runBackupNow()
    } else {
      store.checkAndRunBackupIfDue(trigger: trigger)
    }
  }

  // Uses real filesystem permissions to fail writes without mocking persistence behavior.
  private func withReadOnlyDirectory(_ directoryURL: URL, perform: () throws -> Void) throws {
    let attributes = try FileManager.default.attributesOfItem(atPath: directoryURL.path)
    let permissions = try XCTUnwrap(attributes[.posixPermissions])
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o500], ofItemAtPath: directoryURL.path)
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: permissions], ofItemAtPath: directoryURL.path
      )
    }
    try perform()
  }

  // Confirms successful backup feedback clears itself after its display interval.
  func testTransientBackupMessageDismissesItself() async {
    let store = makeStore()

    store.showTransientMessage(
      "Automatic backup complete.",
      kind: .info,
      dismissAfterNanoseconds: 1_000_000
    )
    XCTAssertEqual(store.userMessage?.text, "Automatic backup complete.")

    try? await Task.sleep(nanoseconds: 20_000_000)

    XCTAssertNil(store.userMessage)
  }

  func testUpdatingBackupSchedulePersistsChoice() throws {
    let userDefaults = makeUserDefaults()
    let store = makeStore(userDefaults: userDefaults)

    store.updateBackupSchedule(.hourly)

    XCTAssertEqual(store.backupSettings.schedule, .hourly)
    let data = try XCTUnwrap(userDefaults.data(forKey: "sceal.backupSettings"))
    let persisted = try JSONDecoder().decode(BackupSettings.self, from: data)
    XCTAssertEqual(persisted.schedule, .hourly)
  }

  func testLoadingBackupSettingsFromDefaults() throws {
    let userDefaults = makeUserDefaults()
    let savedSettings = BackupSettings(
      folderBookmarkData: Data("bookmark".utf8),
      folderDisplayPath: "/tmp/backups",
      schedule: .weekly,
      backupOnInactive: false,
      lastSuccessfulBackupAt: makeDate(year: 2026, month: 4, day: 12),
      lastAttemptedBackupAt: makeDate(year: 2026, month: 4, day: 13),
      lastBackupErrorDescription: nil,
      lastBackupArchiveName: "sceal-backup-auto-2026-04-12-12-00-00.zip",
      lastBackupBytes: 2048
    )
    userDefaults.set(try JSONEncoder().encode(savedSettings), forKey: "sceal.backupSettings")

    let store = makeStore(userDefaults: userDefaults)

    XCTAssertEqual(store.backupSettings, savedSettings)
  }

  func testBackupDueWithoutSuccessfulBackupWhenAutomaticScheduleConfigured() {
    let userDefaults = makeUserDefaults()
    userDefaults.set(
      try? JSONEncoder().encode(
        BackupSettings(
          folderBookmarkData: Data("bookmark".utf8),
          folderDisplayPath: "/tmp/backups",
          schedule: .daily,
          backupOnInactive: true,
          lastSuccessfulBackupAt: nil,
          lastAttemptedBackupAt: nil,
          lastBackupErrorDescription: nil,
          lastBackupArchiveName: nil,
          lastBackupBytes: nil
        )
      ),
      forKey: "sceal.backupSettings"
    )
    let store = makeStore(userDefaults: userDefaults)

    XCTAssertTrue(store.isBackupDue(at: makeDate(year: 2026, month: 4, day: 16)))
  }

  func testBackupNotDueBeforeIntervalElapses() {
    let userDefaults = makeUserDefaults()
    userDefaults.set(
      try? JSONEncoder().encode(
        BackupSettings(
          folderBookmarkData: Data("bookmark".utf8),
          folderDisplayPath: "/tmp/backups",
          schedule: .weekly,
          backupOnInactive: true,
          lastSuccessfulBackupAt: makeDate(year: 2026, month: 4, day: 16),
          lastAttemptedBackupAt: nil,
          lastBackupErrorDescription: nil,
          lastBackupArchiveName: nil,
          lastBackupBytes: nil
        )
      ),
      forKey: "sceal.backupSettings"
    )
    let store = makeStore(userDefaults: userDefaults)

    XCTAssertFalse(store.isBackupDue(at: makeDate(year: 2026, month: 4, day: 18)))
  }

  func testPruneAutomaticBackupsKeepsNewestArchives() throws {
    let temporaryDirectoryURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: temporaryDirectoryURL, withIntermediateDirectories: true)
    addTeardownBlock {
      try? FileManager.default.removeItem(at: temporaryDirectoryURL)
    }

    let archiveNames =
      (0..<26).map { index in
        String(format: "sceal-backup-auto-2026-04-16-%02d-00-00.zip", index)
      } + ["sceal-backup-manual-2026-04-16-00-30-00.zip"]

    for archiveName in archiveNames.sorted() {
      let archiveURL = temporaryDirectoryURL.appendingPathComponent(archiveName)
      try Data().write(to: archiveURL)
    }

    try NotesStore.pruneAutomaticBackups(
      in: temporaryDirectoryURL, schedule: .hourly, fileManager: .default)
    let remainingNames = try FileManager.default.contentsOfDirectory(
      at: temporaryDirectoryURL,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )
    .map(\.lastPathComponent)
    .sorted()

    XCTAssertEqual(remainingNames.count, 25)
    XCTAssertFalse(remainingNames.contains("sceal-backup-auto-2026-04-16-00-00-00.zip"))
    XCTAssertFalse(remainingNames.contains("sceal-backup-auto-2026-04-16-01-00-00.zip"))
    XCTAssertTrue(remainingNames.contains("sceal-backup-manual-2026-04-16-00-30-00.zip"))
  }

  func testWritingAutomaticBackupPrunesWhileFolderAccessIsActive() throws {
    let temporaryDirectoryURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: temporaryDirectoryURL, withIntermediateDirectories: true)
    addTeardownBlock {
      try? FileManager.default.removeItem(at: temporaryDirectoryURL)
    }

    let managedFolderURL = ScealBackupArchiveExporter.managedBackupDirectoryURL(
      in: temporaryDirectoryURL)
    try FileManager.default.createDirectory(at: managedFolderURL, withIntermediateDirectories: true)

    for hour in 0..<24 {
      let archiveName = String(format: "sceal-backup-auto-2026-04-16-%02d-00-00.zip", hour)
      try Data().write(to: managedFolderURL.appendingPathComponent(archiveName))
    }

    let bookmarkData = try temporaryDirectoryURL.bookmarkData(
      options: [.withSecurityScope],
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )

    let archiveURL = try NotesStore.writeBackupArchive(
      dailyNotes: [makeDailyNote(year: 2026, month: 4, day: 17, body: "Backup body")],
      listNotes: [],
      manifest: .empty,
      bookmarkData: bookmarkData,
      kind: .automatic,
      schedule: .hourly,
      createdAt: makeDate(year: 2026, month: 4, day: 17),
      fileManager: .default
    )
    addTeardownBlock {
      ZipArchiveWriter.cleanUp(zipURL: archiveURL)
    }

    let remainingNames = try FileManager.default.contentsOfDirectory(
      at: managedFolderURL,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )
    .map(\.lastPathComponent)
    .sorted()

    XCTAssertEqual(remainingNames.filter { $0.hasPrefix("sceal-backup-auto-") }.count, 24)
    XCTAssertFalse(remainingNames.contains("sceal-backup-auto-2026-04-16-00-00-00.zip"))
    XCTAssertTrue(remainingNames.contains(archiveURL.lastPathComponent))
  }
}
