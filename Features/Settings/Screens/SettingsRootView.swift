//
//  SettingsRootView.swift
//

// Root settings window with sidebar navigation and swappable detail panel.

import AppKit
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
    .frame(
      minWidth: 760,
      idealWidth: 1080,
      maxWidth: .infinity,
      minHeight: 560,
      idealHeight: 780,
      maxHeight: .infinity
    )
    .background(SettingsWindowConfigurator())
  }

  // Returns the settings detail view for the current sidebar selection.
  @ViewBuilder
  private var detailView: some View {
    switch selectedSection {
    case .appearance:
      SettingsAppearanceView(store: store)
    case .themes:
      SettingsThemesView(store: store)
    case .templates:
      SettingsTemplatesView(store: store)
    case .backup:
      SettingsBackupView(store: store)
    case .importData:
      SettingsImportView(store: store)
    case .exportData:
      SettingsExportView(store: store)
    #if DEBUG
      case .developer:
        SettingsDeveloperView(store: store)
    #endif
    }
  }
}

private struct SettingsWindowConfigurator: NSViewRepresentable {
  private let minimumContentSize = NSSize(width: 760, height: 560)
  private let maximumContentSize = NSSize(
    width: CGFloat.greatestFiniteMagnitude,
    height: CGFloat.greatestFiniteMagnitude
  )
  private let frameAutosaveName = "Sceal.Settings.WindowFrame"

  func makeNSView(context: Context) -> NSView {
    let view = SettingsWindowConfiguratorView(frame: .zero)
    view.onWindowChange = { window in
      configureWindow(window)
    }
    return view
  }

  func updateNSView(_ view: NSView, context: Context) {
    guard let view = view as? SettingsWindowConfiguratorView else { return }
    view.onWindowChange = { window in
      configureWindow(window)
    }
    configureWindow(view.window)
  }

  private func configureWindow(_ window: NSWindow?) {
    guard let window else { return }

    window.styleMask.insert(.resizable)
    window.minSize = minimumContentSize
    window.maxSize = maximumContentSize
    window.contentMinSize = minimumContentSize
    window.contentMaxSize = maximumContentSize
    _ = window.setFrameAutosaveName(frameAutosaveName)
  }

  private final class SettingsWindowConfiguratorView: NSView {
    var onWindowChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      onWindowChange?(window)
    }
  }
}
