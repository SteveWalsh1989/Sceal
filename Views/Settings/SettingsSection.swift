//
//  SettingsSection.swift
//  dayra
//

// Sidebar sections for the settings window.
enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
  case appearance
  case templates
  case importData
  case exportData

  var id: String { rawValue }

  var title: String {
    switch self {
    case .appearance: return "Appearance"
    case .templates: return "Templates"
    case .importData: return "Import"
    case .exportData: return "Export"
    }
  }

  var systemImage: String {
    switch self {
    case .appearance: return "paintbrush"
    case .templates: return "doc.text"
    case .importData: return "square.and.arrow.down"
    case .exportData: return "square.and.arrow.up"
    }
  }
}
