//
//  ScealApp.swift
//
//

// App entry point — owns the NotesStore and configures app windows.

import SwiftUI

@main
struct ScealApp: App {
  @Environment(\.scenePhase) private var scenePhase
  @StateObject private var noteStore = NotesStore()

  #if DEBUG
    private let enablesDemoModeOnLaunch = true
  #else
    private let enablesDemoModeOnLaunch = false
  #endif

  var body: some Scene {
    WindowGroup {
      AppRootView(store: noteStore, enablesDemoModeOnLaunch: enablesDemoModeOnLaunch)
        .preferredColorScheme(noteStore.effectiveAppearanceSettings.preferredColorScheme)
    }
    .windowStyle(.hiddenTitleBar)
    .commands {
      ScealCommands(noteStore: noteStore)
    }
    .onChange(of: scenePhase) { _, newScenePhase in
      if newScenePhase != .active {
        noteStore.flushPendingSaves()
        if noteStore.isBackupOnInactiveAvailable && noteStore.backupSettings.backupOnInactive {
          noteStore.checkAndRunBackupIfDue(trigger: .inactive)
        }
      }
    }

    Window("Sceal Settings", id: "settings") {
      SettingsRootView(store: noteStore)
        .disabled(!noteStore.isLibraryReadyForEditing || noteStore.isPerformingFileOperation)
        .preferredColorScheme(noteStore.effectiveAppearanceSettings.preferredColorScheme)
    }
    .defaultSize(width: 1080, height: 780)
  }
}

private struct ScealCommands: Commands {
  @Environment(\.openWindow) private var openWindow
  let noteStore: NotesStore

  var body: some Commands {
    CommandGroup(replacing: .appSettings) {
      Button("Settings…") {
        openWindow(id: "settings")
      }
      .keyboardShortcut(",", modifiers: .command)
    }

    CommandGroup(after: .importExport) {
      Button("Import from Diarly…") {
        noteStore.importFromDiarly()
      }
    }
  }
}
