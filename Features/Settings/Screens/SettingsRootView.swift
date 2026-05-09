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
  @AppStorage("settings.sidebarWidth") private var settingsSidebarWidth = 180.0
  @State private var settingsSidebarDragStartWidth: CGFloat?

  private let minimumSettingsSidebarWidth: CGFloat = 160
  private let maximumSettingsSidebarWidth: CGFloat = 280
  private let minimumSettingsDetailWidth: CGFloat = 520
  private let settingsSidebarResizeHandleWidth: CGFloat = 6

  var body: some View {
    GeometryReader { proxy in
      HStack(spacing: 0) {
        settingsSidebar
          .frame(width: resolvedSettingsSidebarWidth(totalWidth: proxy.size.width))

        settingsSidebarResizeHandle(totalWidth: proxy.size.width)

        detailView
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      }
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

  private var settingsSidebar: some View {
    List(SettingsSection.allCases, selection: $selectedSection) { section in
      Label(section.title, systemImage: section.systemImage)
        .tag(section)
    }
    .listStyle(.sidebar)
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

  private func resolvedSettingsSidebarWidth(totalWidth: CGFloat) -> CGFloat {
    clampedSettingsSidebarWidth(CGFloat(settingsSidebarWidth), totalWidth: totalWidth)
  }

  private func clampedSettingsSidebarWidth(_ proposedWidth: CGFloat, totalWidth: CGFloat) -> CGFloat
  {
    let availableWidth = totalWidth - minimumSettingsDetailWidth - settingsSidebarResizeHandleWidth
    let maximumWidth = min(
      maximumSettingsSidebarWidth, max(minimumSettingsSidebarWidth, availableWidth))
    return min(max(proposedWidth, minimumSettingsSidebarWidth), maximumWidth)
  }

  private func settingsSidebarResizeHandle(totalWidth: CGFloat) -> some View {
    Rectangle()
      .fill(Color.primary.opacity(0.001))
      .frame(width: settingsSidebarResizeHandleWidth)
      .overlay {
        Rectangle()
          .fill(Color.primary.opacity(0.14))
          .frame(width: 1)
      }
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            let startWidth =
              settingsSidebarDragStartWidth ?? resolvedSettingsSidebarWidth(totalWidth: totalWidth)
            settingsSidebarDragStartWidth = startWidth
            settingsSidebarWidth = Double(
              clampedSettingsSidebarWidth(
                startWidth + value.translation.width, totalWidth: totalWidth)
            )
          }
          .onEnded { _ in
            settingsSidebarDragStartWidth = nil
          }
      )
      .help("Resize settings sidebar")
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
