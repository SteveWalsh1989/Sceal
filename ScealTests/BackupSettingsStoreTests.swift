import Foundation
import XCTest

@testable import Sceal

@MainActor
final class BackupSettingsStoreTests: NotesStoreTestCase {
  // Preserves the existing backup settings payload while moving ownership out of NotesStore.
  func testLoadingAndPersistingBackupSettingsUsesExistingDefaultsKey() throws {
    let userDefaults = makeUserDefaults()
    let savedSettings = BackupSettings(
      folderBookmarkData: Data("bookmark".utf8),
      folderDisplayPath: "/tmp/backups",
      schedule: .weekly,
      backupOnInactive: false,
      lastSuccessfulBackupAt: makeDate(year: 2026, month: 5, day: 1),
      lastAttemptedBackupAt: makeDate(year: 2026, month: 5, day: 2),
      lastBackupErrorDescription: nil,
      lastBackupArchiveName: "sceal-backup-auto-2026-05-01-12-00-00.zip",
      lastBackupBytes: 4096
    )
    userDefaults.set(try JSONEncoder().encode(savedSettings), forKey: "sceal.backupSettings")
    let store = BackupSettingsStore(
      settingsRepository: SettingsRepository(userDefaults: userDefaults)
    )

    XCTAssertEqual(store.settings, savedSettings)

    store.updateSchedule(.hourly)
    try store.persistSettings()

    let data = try XCTUnwrap(userDefaults.data(forKey: "sceal.backupSettings"))
    let persistedSettings = try JSONDecoder().decode(BackupSettings.self, from: data)
    XCTAssertEqual(persistedSettings.schedule, .hourly)
    XCTAssertEqual(persistedSettings.folderDisplayPath, "/tmp/backups")
  }

  // Reconfiguring a backup folder must not carry stale run metadata to the new destination.
  func testConfigureFolderResetsRunMetadata() {
    let store = BackupSettingsStore(
      settingsRepository: SettingsRepository(userDefaults: makeUserDefaults())
    )
    store.markBackupSucceeded(
      at: makeDate(year: 2026, month: 5, day: 3),
      archiveName: "old.zip",
      bytes: 1024
    )

    store.configureFolder(bookmarkData: Data("new-bookmark".utf8), displayPath: "/tmp/new")

    XCTAssertEqual(store.settings.folderBookmarkData, Data("new-bookmark".utf8))
    XCTAssertEqual(store.settings.folderDisplayPath, "/tmp/new")
    XCTAssertNil(store.settings.lastSuccessfulBackupAt)
    XCTAssertNil(store.settings.lastAttemptedBackupAt)
    XCTAssertNil(store.settings.lastBackupErrorDescription)
    XCTAssertNil(store.settings.lastBackupArchiveName)
    XCTAssertNil(store.settings.lastBackupBytes)
  }

  // Tracks attempted, successful, and failed backup metadata without changing destination data.
  func testBackupRunMetadataUpdatesPreserveDestination() {
    let store = BackupSettingsStore(
      settingsRepository: SettingsRepository(userDefaults: makeUserDefaults())
    )
    store.configureFolder(bookmarkData: Data("bookmark".utf8), displayPath: "/tmp/backups")
    let attemptDate = makeDate(year: 2026, month: 5, day: 4)
    let successDate = makeDate(year: 2026, month: 5, day: 5)

    store.markBackupAttempted(at: attemptDate)
    XCTAssertEqual(store.settings.lastAttemptedBackupAt, attemptDate)
    XCTAssertNil(store.settings.lastBackupErrorDescription)

    store.markBackupSucceeded(at: successDate, archiveName: "backup.zip", bytes: 2048)
    XCTAssertEqual(store.settings.lastSuccessfulBackupAt, successDate)
    XCTAssertEqual(store.settings.lastBackupArchiveName, "backup.zip")
    XCTAssertEqual(store.settings.lastBackupBytes, 2048)
    XCTAssertEqual(store.settings.folderDisplayPath, "/tmp/backups")

    store.markBackupFailed("Disk full")
    XCTAssertEqual(store.settings.lastBackupErrorDescription, "Disk full")
    XCTAssertEqual(store.settings.folderDisplayPath, "/tmp/backups")
  }
}
