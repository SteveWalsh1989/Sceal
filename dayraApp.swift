//
//  dayraApp.swift
//  dayra
//
//

import SwiftUI

@main
struct DayraApp: App {
  @Environment(\.scenePhase) private var scenePhase
  @StateObject private var noteStore = NoteStore()

  var body: some Scene {
    WindowGroup {
      ContentView(store: noteStore)
    }
    .onChange(of: scenePhase) { _, newScenePhase in
      if newScenePhase != .active {
        noteStore.flushPendingSaves()
      }
    }
  }
}
