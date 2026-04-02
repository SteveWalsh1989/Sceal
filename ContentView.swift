//
//  ContentView.swift
//
//

import SwiftUI

struct ContentView: View {
  @ObservedObject var store: NoteStore
  @State private var notePendingDeletionID: DayNote.ID?

  var body: some View {
    NavigationSplitView {
      SidebarView(store: store) { noteID in
        notePendingDeletionID = noteID
      }
      .navigationSplitViewColumnWidth(min: 240, ideal: 290, max: 360)
    } detail: {
      Group {
        if let selectedNoteID = store.selectedNoteID {
          NoteEditorView(store: store, noteID: selectedNoteID) { noteID in
            notePendingDeletionID = noteID
          }
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
      .ignoresSafeArea(.container, edges: .top)
    }
    .navigationSplitViewStyle(.balanced)
    .task {
      store.loadIfNeeded()
    }
    .alert("Delete this note?", isPresented: isShowingDeleteConfirmation) {
      Button("Delete", role: .destructive) {
        guard let notePendingDeletionID else {
          return
        }

        store.delete(noteID: notePendingDeletionID)
        self.notePendingDeletionID = nil
      }

      Button("Cancel", role: .cancel) {
        notePendingDeletionID = nil
      }
    } message: {
      Text("This cannot be undone.")
    }
    .overlay(alignment: .top) {
      if let message = store.userMessage {
        ErrorBanner(message: message.text, kind: message.kind) {
          store.dismissMessage()
        }
        .padding(.top, 12)
      }
    }
  }

  // Keeps delete confirmation shared between header settings and sidebar actions.
  private var isShowingDeleteConfirmation: Binding<Bool> {
    Binding(
      get: { notePendingDeletionID != nil },
      set: { isPresented in
        if !isPresented {
          notePendingDeletionID = nil
        }
      }
    )
  }
}

private struct ErrorBanner: View {
  let message: String
  let kind: UserMessageKind
  let dismiss: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: kind == .error ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
        .foregroundStyle(kind == .error ? .orange : .green)

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
