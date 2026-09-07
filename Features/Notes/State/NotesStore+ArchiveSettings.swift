//
//  NotesStore+ArchiveSettings.swift
//

// Creates and applies portable full-library settings snapshots on the main actor.

import Combine
import Foundation

extension NotesStore {
  // Validate active documents while preserving retained Markdown as uninterpreted recovery bytes.
  func makeLibrarySnapshot() throws -> ScealLibrarySnapshot {
    try flushPendingSavesForLibraryOperation()
    let sourceFiles = try LegacyArchiveSourceFiles.read(
      dailyURL: libraryLocation.legacyNotesDirectoryURL,
      listURL: libraryLocation.rootURL.appendingPathComponent(
        ScealLibraryLocation.listNotesFolderName),
      fileManager: fileManager
    )
    let structuredDaily = try structuredNoteRepository.loadDocuments()
    let structuredList = try structuredListNoteRepository.loadDocuments()
    let structuredManifest = try libraryRepository.loadStructuredListNotesManifestForArchive(
      noteIDs: Set(structuredList.map(\.id))
    )
    return ScealLibrarySnapshot(
      legacyDailyNotes: [],
      legacyListNotes: [],
      legacyListManifest: .empty,
      structuredDailyNotes: structuredDaily,
      structuredListNotes: structuredList,
      structuredListManifest: structuredManifest,
      templates: noteTemplates,
      settings: try makeArchiveSettings(),
      authority: .structured,
      legacySourceFiles: sourceFiles
    )
  }

  // Encodes appearance, theme, editor, and safe backup behavior for a v2 archive.
  func makeArchiveSettings() throws -> ScealArchiveSettings {
    ScealArchiveSettings(
      appearanceSettingsData: try JSONEncoder().encode(appearanceSettings),
      continuousSpellCheckingEnabled: continuousSpellCheckingEnabled,
      newNoteDefaultRawValue: newNoteDefault.rawValue,
      dailyNoteStorageModeRawValue: ScealArchiveAuthority.structured.rawValue,
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
    settingsRepository.saveArchiveLayoutSettings(settings.layoutSettings)
    refreshBackupHealth()
  }
}
