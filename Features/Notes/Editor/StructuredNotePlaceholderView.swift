//
//  StructuredNotePlaceholderView.swift
//

// Empty state for a library that does not contain a selected note.

import SwiftUI

struct StructuredNotePlaceholderView: View {
  @ObservedObject var store: NotesStore

  var body: some View {
    ContentUnavailableView {
      Label("No notes yet", systemImage: "note.text")
    } description: {
      Text(
        store.sidebarMode == .list
          ? "Create a list note to get started."
          : "Create today's note to get started."
      )
    } actions: {
      Button(store.sidebarMode == .list ? "Create list note" : "Create today's note") {
        if store.sidebarMode == .list {
          store.createListNote()
        } else {
          store.selectToday()
        }
      }
      .buttonStyle(.borderedProminent)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
