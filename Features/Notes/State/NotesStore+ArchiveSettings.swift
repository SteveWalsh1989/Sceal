//
//  NotesStore+ArchiveSettings.swift
//

// Creates and applies portable full-library settings snapshots on the main actor.

import Combine
import Foundation

extension NotesStore {
  // Strictly captures both rollback libraries and all portable configuration from disk.
  func makeLibrarySnapshot() throws -> ScealLibrarySnapshot {
    flushPendingSaves()
    let legacy = try libraryRepository.loadArchiveSourceSnapshot()
    let structuredDaily = try structuredNoteRepository.loadDocuments()
    let structuredList = try structuredListNoteRepository.loadDocuments()
    let structuredManifest = try libraryRepository.loadStructuredListNotesManifestForArchive(
      noteIDs: Set(structuredList.map(\.id))
    )
    return ScealLibrarySnapshot(
      legacyDailyNotes: legacy.dailyNotes,
      legacyListNotes: legacy.listNotes,
      legacyListManifest: legacy.listManifest,
      structuredDailyNotes: structuredDaily,
      structuredListNotes: structuredList,
      structuredListManifest: structuredManifest,
      templates: noteTemplates,
      settings: try makeArchiveSettings()
    )
  }

  // Encodes appearance, theme, editor, mode, and safe backup behavior for a v2 archive.
  func makeArchiveSettings() throws -> ScealArchiveSettings {
    ScealArchiveSettings(
      appearanceSettingsData: try JSONEncoder().encode(appearanceSettings),
      continuousSpellCheckingEnabled: continuousSpellCheckingEnabled,
      newNoteDefaultRawValue: newNoteDefault.rawValue,
      dailyNoteStorageModeRawValue: dailyNoteStorageMode.rawValue,
      backupScheduleRawValue: backupSettings.schedule.rawValue,
      backupOnInactive: backupSettings.backupOnInactive,
      themeID: appearanceSettings.themeID,
      includesCustomThemeColors: appearanceSettings.colorOverrides != nil,
      layoutSettings: settingsRepository.loadArchiveLayoutSettings()
    )
  }

  // Applies already validated portable settings while retaining OS-bound backup permissions.
  func applyArchiveSettings(_ settings: ScealArchiveSettings) throws {
    try settings.validate()
    let appearance = try JSONDecoder().decode(
      NoteAppearanceSettings.self,
      from: settings.appearanceSettingsData
    )
    guard let newNoteDefault = NewNoteDefault(rawValue: settings.newNoteDefaultRawValue),
      let storageMode = DailyNoteStorageMode(rawValue: settings.dailyNoteStorageModeRawValue),
      let backupSchedule = BackupSchedule(rawValue: settings.backupScheduleRawValue)
    else {
      throw ScealArchiveSettingsError.invalidAppearanceSettings
    }

    objectWillChange.send()
    try appearanceSettingsStore.restoreSettings(appearance)
    editorPreferencesStore.restoreSettings(
      continuousSpellCheckingEnabled: settings.continuousSpellCheckingEnabled,
      newNoteDefault: newNoteDefault
    )
    try backupSettingsStore.restorePortableSettings(
      schedule: backupSchedule,
      backupOnInactive: settings.backupOnInactive
    )
    dailyNoteStorageMode = storageMode
    settingsRepository.saveDailyNoteStorageMode(storageMode)
    settingsRepository.saveArchiveLayoutSettings(settings.layoutSettings)
    refreshBackupHealth()
  }
}
