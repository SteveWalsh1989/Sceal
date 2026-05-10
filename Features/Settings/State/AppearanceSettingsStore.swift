//
//  AppearanceSettingsStore.swift
//

// Feature store for persisted note appearance settings.

import Combine
import Foundation

@MainActor
final class AppearanceSettingsStore: ObservableObject {
  @Published private(set) var settings: NoteAppearanceSettings

  private let settingsRepository: SettingsRepository

  init(settingsRepository: SettingsRepository) {
    self.settingsRepository = settingsRepository
    self.settings = settingsRepository.loadAppearanceSettings()
  }

  // Applies, clamps, and persists one appearance settings mutation.
  func updateSettings(_ mutate: (inout NoteAppearanceSettings) -> Void) throws {
    var updatedSettings = settings
    mutate(&updatedSettings)
    settings = updatedSettings.clamped
    try persistSettings()
  }

  // Persists the current appearance settings using the existing defaults key.
  func persistSettings() throws {
    try settingsRepository.saveAppearanceSettings(settings)
  }
}
