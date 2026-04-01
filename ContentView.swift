//
//  ContentView.swift
//  dayra
//
//

import SwiftUI

struct ContentView: View {
  @ObservedObject var store: NoteStore

  var body: some View {
    NavigationSplitView {
      SidebarView(store: store)
        .frame(minWidth: 300, idealWidth: 340)
    } detail: {
      Group {
        if let selectedNoteID = store.selectedNoteID {
          NoteEditorView(store: store, noteID: selectedNoteID)
        } else if store.isLoading {
          ProgressView("Loading notes…")
        } else {
          ContentUnavailableView(
            "No note selected",
            systemImage: "calendar",
            description: Text("Choose a day from the sidebar to start writing.")
          )
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Color.primary.opacity(0.02))
    }
    .navigationSplitViewStyle(.balanced)
    .task {
      store.loadIfNeeded()
    }
    .overlay(alignment: .top) {
      if let errorMessage = store.errorMessage {
        ErrorBanner(message: errorMessage) {
          store.dismissError()
        }
        .padding(.top, 12)
      }
    }
  }
}

private struct ErrorBanner: View {
  let message: String
  let dismiss: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)

      Text(message)
        .font(.callout)
        .lineLimit(2)

      Button("Dismiss", action: dismiss)
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(.regularMaterial, in: Capsule())
    .shadow(color: Color.black.opacity(0.12), radius: 18, y: 8)
  }
}
