//
//  EditorPreferencesStore.swift
//

// Feature store for editor behavior preferences persisted in UserDefaults.

import Combine
import Foundation

@MainActor
final class EditorPreferencesStore: ObservableObject {
  @Published private(set) var continuousSpellCheckingEnabled: Bool
  @Published private(set) var newNoteDefault: NewNoteDefault

  private let settingsRepository: SettingsRepository

  init(settingsRepository: SettingsRepository) {
    self.settingsRepository = settingsRepository
    self.continuousSpellCheckingEnabled =
      settingsRepository.loadContinuousSpellCheckingEnabled()
    self.newNoteDefault = settingsRepository.loadNewNoteDefault()
  }

  // Persists the default content strategy for newly created daily notes.
  func updateNewNoteDefault(_ value: NewNoteDefault) {
    newNoteDefault = value
    settingsRepository.saveNewNoteDefault(value)
  }

  // Persists the body editor spell-check preference.
  func updateContinuousSpellCheckingEnabled(_ value: Bool) {
    continuousSpellCheckingEnabled = value
    settingsRepository.saveContinuousSpellCheckingEnabled(value)
  }

  // Restores portable editor behavior without introducing a second persistence path.
  func restoreSettings(
    continuousSpellCheckingEnabled: Bool,
    newNoteDefault: NewNoteDefault
  ) {
    self.continuousSpellCheckingEnabled = continuousSpellCheckingEnabled
    self.newNoteDefault = newNoteDefault
    settingsRepository.saveContinuousSpellCheckingEnabled(continuousSpellCheckingEnabled)
    settingsRepository.saveNewNoteDefault(newNoteDefault)
  }
}
