//
//  SettingsSection.swift
//

// Defines sidebar sections for the settings navigation.

// Sidebar sections for the settings window.
enum SettingsSection: String, Identifiable, Hashable {
  case appearance
  case themes
  case templates
  case backup
  case importData
  case exportData
  case experimental
  #if DEBUG
    case developer
  #endif

  static var allCases: [SettingsSection] {
    var sections: [SettingsSection] = [
      .appearance,
      .themes,
      .templates,
      .backup,
      .importData,
      .exportData,
      .experimental,
    ]
    #if DEBUG
      sections.append(.developer)
    #endif
    return sections
  }

  var id: String { rawValue }

  var title: String {
    switch self {
    case .appearance: return "Appearance"
    case .themes: return "Themes"
    case .templates: return "Templates"
    case .backup: return "Backup"
    case .importData: return "Import"
    case .exportData: return "Export"
    case .experimental: return "Experimental"
    #if DEBUG
      case .developer: return "Developer"
    #endif
    }
  }

  var systemImage: String {
    switch self {
    case .appearance: return "paintbrush"
    case .themes: return "paintpalette"
    case .templates: return "text.badge.plus"
    case .backup: return "externaldrive.badge.timemachine"
    case .importData: return "square.and.arrow.down"
    case .exportData: return "square.and.arrow.up"
    case .experimental: return "testtube.2"
    #if DEBUG
      case .developer: return "hammer"
    #endif
    }
  }
}
