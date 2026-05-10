//
//  SettingsRepository.swift
//

// UserDefaults-backed persistence boundary for app settings and templates.

import Foundation

struct SettingsRepository {
  private enum Keys {
    static let appearanceSettings = "sceal.noteAppearanceSettings"
    static let continuousSpellCheckingEnabled = "sceal.continuousSpellCheckingEnabled"
    static let newNoteDefault = "sceal.newNoteDefault"
    static let developerPlan = "sceal.developer.plan"
    static let backupSettings = "sceal.backupSettings"
    static let noteTemplates = "sceal.noteTemplates"
    static let noteTemplatesSeeded = "sceal.noteTemplatesSeeded"
  }

  let userDefaults: UserDefaults

  // Decodes appearance settings from the existing defaults payload.
  func loadAppearanceSettings() -> NoteAppearanceSettings {
    guard
      let data = userDefaults.data(forKey: Keys.appearanceSettings),
      let settings = try? JSONDecoder().decode(NoteAppearanceSettings.self, from: data)
    else {
      return .default
    }

    return settings.clamped
  }

  // Persists clamped appearance settings using the existing defaults key.
  func saveAppearanceSettings(_ settings: NoteAppearanceSettings) throws {
    let data = try JSONEncoder().encode(settings.clamped)
    userDefaults.set(data, forKey: Keys.appearanceSettings)
  }

  // Reads the body editor spell-check preference, defaulting to enabled for new installs.
  func loadContinuousSpellCheckingEnabled() -> Bool {
    guard userDefaults.object(forKey: Keys.continuousSpellCheckingEnabled) != nil else {
      return true
    }

    return userDefaults.bool(forKey: Keys.continuousSpellCheckingEnabled)
  }

  // Persists the body editor spell-check preference.
  func saveContinuousSpellCheckingEnabled(_ value: Bool) {
    userDefaults.set(value, forKey: Keys.continuousSpellCheckingEnabled)
  }

  // Reads the new-note default preference from its existing raw-value key.
  func loadNewNoteDefault() -> NewNoteDefault {
    guard
      let rawValue = userDefaults.string(forKey: Keys.newNoteDefault),
      let value = NewNoteDefault(rawValue: rawValue)
    else {
      return .blank
    }

    return value
  }

  // Persists the new-note default preference.
  func saveNewNoteDefault(_ value: NewNoteDefault) {
    userDefaults.set(value.rawValue, forKey: Keys.newNoteDefault)
  }

  // Loads the active plan, defaulting to paid so existing builds keep full feature parity.
  func loadInitialPlan() -> AppPlan {
    #if DEBUG
      return loadDeveloperPlanOverride() ?? .paid
    #else
      return .paid
    #endif
  }

  #if DEBUG
    // Reads the developer-only plan override without treating absence as Free.
    func loadDeveloperPlanOverride() -> AppPlan? {
      guard
        let rawValue = userDefaults.string(forKey: Keys.developerPlan),
        let plan = AppPlan(rawValue: rawValue)
      else {
        return nil
      }

      return plan
    }

    // Persists the developer-only plan override.
    func saveDeveloperPlan(_ plan: AppPlan) {
      userDefaults.set(plan.rawValue, forKey: Keys.developerPlan)
    }
  #endif

  // Decodes backup settings from the existing defaults payload.
  func loadBackupSettings() -> BackupSettings {
    guard
      let data = userDefaults.data(forKey: Keys.backupSettings),
      let settings = try? JSONDecoder().decode(BackupSettings.self, from: data)
    else {
      return .default
    }

    return settings
  }

  // Persists backup settings using the existing defaults key.
  func saveBackupSettings(_ settings: BackupSettings) throws {
    let data = try JSONEncoder().encode(settings)
    userDefaults.set(data, forKey: Keys.backupSettings)
  }

  // Loads templates from defaults and seeds the starter only once for each install.
  func loadNoteTemplates() -> [NoteTemplate] {
    if let data = userDefaults.data(forKey: Keys.noteTemplates),
      let templates = try? JSONDecoder().decode([NoteTemplate].self, from: data)
    {
      return sortedTemplates(templates.map { $0.normalizedForCurrentVersion() })
    }

    guard !userDefaults.bool(forKey: Keys.noteTemplatesSeeded) else {
      return []
    }

    let starterTemplates = [NoteTemplate.starterMeeting]
    if let data = try? JSONEncoder().encode(starterTemplates) {
      userDefaults.set(data, forKey: Keys.noteTemplates)
    }
    userDefaults.set(true, forKey: Keys.noteTemplatesSeeded)
    return starterTemplates
  }

  // Encodes custom templates to UserDefaults so they are restored on launch.
  func saveNoteTemplates(_ templates: [NoteTemplate]) throws {
    let data = try JSONEncoder().encode(templates)
    userDefaults.set(data, forKey: Keys.noteTemplates)
    userDefaults.set(true, forKey: Keys.noteTemplatesSeeded)
  }

  private func sortedTemplates(_ templates: [NoteTemplate]) -> [NoteTemplate] {
    templates.sorted {
      $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
    }
  }
}
