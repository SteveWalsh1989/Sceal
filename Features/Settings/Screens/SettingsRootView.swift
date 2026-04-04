//
//  SettingsRootView.swift
//

// Root settings window with sidebar navigation and swappable detail panel.

import SwiftUI

// Root settings view with sidebar navigation and swappable detail panel.
struct SettingsRootView: View {
  @ObservedObject var store: NotesStore
  @State private var selectedSection: SettingsSection = .appearance

  var body: some View {
    NavigationSplitView {
      List(SettingsSection.allCases, selection: $selectedSection) { section in
        Label(section.title, systemImage: section.systemImage)
          .tag(section)
      }
      .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
    } detail: {
      detailView
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    .frame(width: 860, height: 730)
  }

  // Returns the settings detail view for the current sidebar selection.
  @ViewBuilder
  private var detailView: some View {
    switch selectedSection {
    case .appearance:
      SettingsAppearanceView(store: store)
    case .themes:
      SettingsThemesView(store: store)
    case .importData:
      SettingsImportView(store: store)
    case .exportData:
      SettingsExportView(store: store)
    }
  }
}
