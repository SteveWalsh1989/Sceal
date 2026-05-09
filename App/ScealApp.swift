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

  var body: some Scene {
    WindowGroup {
      AppRootView(store: noteStore)
        .preferredColorScheme(noteStore.appearanceSettings.preferredColorScheme)
    }
    .windowStyle(.hiddenTitleBar)
    .commands {
      ScealCommands(noteStore: noteStore)
    }
    .onChange(of: scenePhase) { _, newScenePhase in
      if newScenePhase != .active {
        noteStore.flushPendingSaves()
        if noteStore.backupSettings.backupOnInactive {
          noteStore.checkAndRunBackupIfDue(trigger: .inactive)
        }
      }
    }

    Window("Sceal Settings", id: "settings") {
      SettingsRootView(store: noteStore)
        .preferredColorScheme(noteStore.appearanceSettings.preferredColorScheme)
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
