//
//  SettingsView.swift
//

import SwiftUI

// Root settings view with sidebar navigation and swappable detail panel.
struct SettingsView: View {
  @ObservedObject var store: NoteStore
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

  @ViewBuilder
  private var detailView: some View {
    switch selectedSection {
    case .appearance:
      AppearanceSettingsView(store: store)
    case .themes:
      ThemesSettingsView(store: store)
    case .importData:
      ImportSettingsView(store: store)
    case .exportData:
      ExportSettingsView(store: store)
    }
  }
}
