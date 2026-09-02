//
//  BackupSettingsStore.swift
//

// Feature store for persisted backup configuration and last-run metadata.

import Combine
import Foundation

@MainActor
final class BackupSettingsStore: ObservableObject {
  @Published private(set) var settings: BackupSettings

  private let settingsRepository: SettingsRepository

  init(settingsRepository: SettingsRepository) {
    self.settingsRepository = settingsRepository
    self.settings = settingsRepository.loadBackupSettings()
  }

  // Updates the automatic backup schedule and clears the last run error.
  func updateSchedule(_ schedule: BackupSchedule) {
    settings.schedule = schedule
    settings.lastBackupErrorDescription = nil
  }

  // Updates whether backup should run when the app becomes inactive.
  func updateBackupOnInactive(_ value: Bool) {
    settings.backupOnInactive = value
  }

  // Stores the selected folder bookmark and resets run metadata for the new destination.
  func configureFolder(bookmarkData: Data, displayPath: String) {
    settings.folderBookmarkData = bookmarkData
    settings.folderDisplayPath = displayPath
    settings.lastSuccessfulBackupAt = nil
    settings.lastAttemptedBackupAt = nil
    settings.lastBackupErrorDescription = nil
    settings.lastBackupArchiveName = nil
    settings.lastBackupBytes = nil
  }

  // Clears the folder bookmark without touching existing backup archives.
  func removeFolder() {
    settings.folderBookmarkData = nil
    settings.folderDisplayPath = nil
    settings.lastSuccessfulBackupAt = nil
    settings.lastAttemptedBackupAt = nil
    settings.lastBackupErrorDescription = nil
    settings.lastBackupArchiveName = nil
    settings.lastBackupBytes = nil
  }

  // Marks a backup run as started and clears stale error state.
  func markBackupAttempted(at backupDate: Date) {
    settings.lastAttemptedBackupAt = backupDate
    settings.lastBackupErrorDescription = nil
  }

  // Stores successful backup metadata without changing the configured destination.
  func markBackupSucceeded(at backupDate: Date, archiveName: String, bytes: Int64?) {
    settings.lastSuccessfulBackupAt = backupDate
    settings.lastBackupErrorDescription = nil
    settings.lastBackupArchiveName = archiveName
    settings.lastBackupBytes = bytes
  }

  // Stores the most recent backup failure message for settings UI and health checks.
  func markBackupFailed(_ errorDescription: String) {
    settings.lastBackupErrorDescription = errorDescription
  }

  // Persists settings using the existing UserDefaults key and payload shape.
  func persistSettings() throws {
    try settingsRepository.saveBackupSettings(settings)
  }

  // Restores portable backup behavior while preserving this Mac's security-scoped folder access.
  func restorePortableSettings(schedule: BackupSchedule, backupOnInactive: Bool) throws {
    settings.schedule = schedule
    settings.backupOnInactive = backupOnInactive
    settings.lastBackupErrorDescription = nil
    try persistSettings()
  }
}
