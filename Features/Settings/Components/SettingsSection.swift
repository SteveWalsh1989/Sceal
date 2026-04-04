//
//  SettingsSection.swift
//

// Defines sidebar sections for the settings navigation.

// Sidebar sections for the settings window.
enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
  case appearance
  case themes
  case importData
  case exportData

  var id: String { rawValue }

  var title: String {
    switch self {
    case .appearance: return "Appearance"
    case .themes: return "Themes"
    case .importData: return "Import"
    case .exportData: return "Export"
    }
  }

  var systemImage: String {
    switch self {
    case .appearance: return "paintbrush"
    case .themes: return "paintpalette"
    case .importData: return "square.and.arrow.down"
    case .exportData: return "square.and.arrow.up"
    }
  }
}
