import Foundation
import XCTest

@testable import Sceal

@MainActor
final class NotesStoreBackupTests: NotesStoreTestCase {
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
}
