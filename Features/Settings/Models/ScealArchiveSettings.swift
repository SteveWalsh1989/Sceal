//
//  ScealArchiveSettings.swift
//

// Portable settings included in lossless Scéal archives without OS-bound bookmark permissions.

import Foundation

nonisolated struct ScealArchiveSettings: Codable, Equatable, Sendable {
  static let currentVersion = 1

  let version: Int
  let appearanceSettingsData: Data
  let continuousSpellCheckingEnabled: Bool
  let newNoteDefaultRawValue: String
  let dailyNoteStorageModeRawValue: String
  let backupScheduleRawValue: String
  let backupOnInactive: Bool
  let themeID: String
  let includesCustomThemeColors: Bool
  let layoutSettings: ScealArchiveLayoutSettings

  init(
    appearanceSettingsData: Data,
    continuousSpellCheckingEnabled: Bool,
    newNoteDefaultRawValue: String,
    dailyNoteStorageModeRawValue: String,
    backupScheduleRawValue: String,
    backupOnInactive: Bool,
    themeID: String,
    includesCustomThemeColors: Bool,
    layoutSettings: ScealArchiveLayoutSettings
  ) {
    self.version = Self.currentVersion
    self.appearanceSettingsData = appearanceSettingsData
    self.continuousSpellCheckingEnabled = continuousSpellCheckingEnabled
    self.newNoteDefaultRawValue = newNoteDefaultRawValue
    self.dailyNoteStorageModeRawValue = dailyNoteStorageModeRawValue
    self.backupScheduleRawValue = backupScheduleRawValue
    self.backupOnInactive = backupOnInactive
    self.themeID = themeID
    self.includesCustomThemeColors = includesCustomThemeColors
    self.layoutSettings = layoutSettings
  }

  // Rejects unsupported or malformed portable settings before any library folder is replaced.
  func validate() throws {
    guard version == Self.currentVersion else {
      throw ScealArchiveSettingsError.unsupportedVersion(version)
    }
    guard
      let appearance = try? JSONDecoder().decode(
        ScealArchiveAppearancePayload.self,
        from: appearanceSettingsData
      ),
      appearance.isValid,
      appearance.themeID == themeID,
      (appearance.colorOverrides != nil) == includesCustomThemeColors,
      appearance.colorOverrides?.isValid ?? true
    else {
      throw ScealArchiveSettingsError.invalidAppearanceSettings
    }
    guard Self.isValidNewNoteDefault(newNoteDefaultRawValue) else {
      throw ScealArchiveSettingsError.invalidNewNoteDefault(newNoteDefaultRawValue)
    }
    guard DailyNoteStorageMode(rawValue: dailyNoteStorageModeRawValue) != nil else {
      throw ScealArchiveSettingsError.invalidStorageMode(dailyNoteStorageModeRawValue)
    }
    guard BackupSchedule(rawValue: backupScheduleRawValue) != nil else {
      throw ScealArchiveSettingsError.invalidBackupSchedule(backupScheduleRawValue)
    }
    guard layoutSettings.settingsSidebarWidth.isFinite,
      layoutSettings.settingsSidebarWidth > 0,
      layoutSettings.templatesListWidth.isFinite,
      layoutSettings.templatesListWidth > 0
    else {
      throw ScealArchiveSettingsError.invalidLayoutSettings
    }
  }

  // Restores portable preferences while making structured storage the active runtime.
  func normalizedForStructuredRuntime() -> ScealArchiveSettings {
    ScealArchiveSettings(
      appearanceSettingsData: appearanceSettingsData,
      continuousSpellCheckingEnabled: continuousSpellCheckingEnabled,
      newNoteDefaultRawValue: newNoteDefaultRawValue,
      dailyNoteStorageModeRawValue: DailyNoteStorageMode.structuredExperimental.rawValue,
      backupScheduleRawValue: backupScheduleRawValue,
      backupOnInactive: backupOnInactive,
      themeID: themeID,
      includesCustomThemeColors: includesCustomThemeColors,
      layoutSettings: layoutSettings
    )
  }

  private static func isValidNewNoteDefault(_ rawValue: String) -> Bool {
    rawValue == "blank" || rawValue == "copyPrevious"
      || (rawValue.hasPrefix("template:") && rawValue.count > "template:".count)
  }
}

private nonisolated struct ScealArchiveAppearancePayload: Decodable {
  let bodyFontName: String
  let bodyFontSize: Double
  let lineHeight: Double
  let listItemSpacing: Double
  let bulletSize: Double
  let sectionDividerGapScale: Double
  let sidebarFontSize: Double
  let showEditorScrollbar: Bool
  let highlightsFocusedSectionBorder: Bool
  let accentColorName: String
  let sidebarShowsTags: Bool
  let sidebarDateFormat: String
  let calendarHidesWeekends: Bool
  let themeID: String
  let colorOverrides: ScealArchiveThemeColorSet?

  var isValid: Bool {
    let themeIDs: Set<String> = [
      "default-dark", "midnight", "charcoal", "slate", "ember",
      "default-light", "paper", "ivory", "cloud", "sand",
    ]
    let accentNames: Set<String> = [
      "blue", "turquoise", "pink", "red", "purple", "orange", "grey", "white",
    ]
    let sidebarDateFormats: Set<String> = [
      "yearMonthDay", "dayMonthYear", "dayMonthYearSlashes", "monthDayYear",
      "monthDayYearSlashes", "dayShortMonthContextual",
    ]
    return !bodyFontName.isEmpty
      && (11...24).contains(bodyFontSize)
      && (0.8...1.8).contains(lineHeight)
      && (0...6).contains(listItemSpacing)
      && (12...30).contains(bulletSize)
      && (1...3).contains(sectionDividerGapScale)
      && (12...18).contains(sidebarFontSize)
      && accentNames.contains(accentColorName)
      && sidebarDateFormats.contains(sidebarDateFormat)
      && themeIDs.contains(themeID)
  }
}

private nonisolated struct ScealArchiveThemeColorSet: Decodable {
  let sidebarBackground: ScealArchiveThemeColor
  let editorBackground: ScealArchiveThemeColor
  let selectedCard: ScealArchiveThemeColor
  let unselectedCard: ScealArchiveThemeColor
  let sectionCardFill: ScealArchiveThemeColor
  let controlBackground: ScealArchiveThemeColor
  let divider: ScealArchiveThemeColor
  let noteBodyBorder: ScealArchiveThemeColor

  var isValid: Bool {
    [
      sidebarBackground,
      editorBackground,
      selectedCard,
      unselectedCard,
      sectionCardFill,
      controlBackground,
      divider,
      noteBodyBorder,
    ].allSatisfy(\.isValid)
  }
}

private nonisolated struct ScealArchiveThemeColor: Decodable {
  let red: Double
  let green: Double
  let blue: Double
  let alpha: Double

  var isValid: Bool {
    [red, green, blue, alpha].allSatisfy { component in
      component.isFinite && (0...1).contains(component)
    }
  }
}

nonisolated struct ScealArchiveLayoutSettings: Codable, Equatable, Sendable {
  let settingsSidebarWidth: Double
  let templatesListWidth: Double
  let templatesListCollapsed: Bool
}

nonisolated enum ScealArchiveSettingsError: LocalizedError, Equatable, Sendable {
  case unsupportedVersion(Int)
  case invalidAppearanceSettings
  case invalidNewNoteDefault(String)
  case invalidStorageMode(String)
  case invalidBackupSchedule(String)
  case invalidLayoutSettings

  var errorDescription: String? {
    switch self {
    case .unsupportedVersion(let version):
      return "The archive uses unsupported settings version \(version)."
    case .invalidAppearanceSettings:
      return "The archive appearance settings are invalid."
    case .invalidNewNoteDefault(let rawValue):
      return "The archive new-note default \(rawValue) is invalid."
    case .invalidStorageMode(let rawValue):
      return "The archive storage mode \(rawValue) is invalid."
    case .invalidBackupSchedule(let rawValue):
      return "The archive backup schedule \(rawValue) is invalid."
    case .invalidLayoutSettings:
      return "The archive window layout settings are invalid."
    }
  }
}
