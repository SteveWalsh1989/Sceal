//
//  ScealApp.swift
//
//

// App entry point — owns the NotesStore and configures the main window and settings scene.

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
      CommandGroup(after: .importExport) {
        Button("Import from Diarly…") {
          noteStore.importFromDiarly()
        }
      }
    }
    .onChange(of: scenePhase) { _, newScenePhase in
      if newScenePhase != .active {
        noteStore.flushPendingSaves()
      }
    }

    Settings {
      SettingsRootView(store: noteStore)
        .preferredColorScheme(noteStore.appearanceSettings.preferredColorScheme)
    }
  }
}
