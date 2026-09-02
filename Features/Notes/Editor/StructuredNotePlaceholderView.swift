//
//  StructuredNotePlaceholderView.swift
//

// Empty state for an enabled structured library that does not contain a selected note.

import SwiftUI

struct StructuredNotePlaceholderView: View {
  @ObservedObject var store: NotesStore

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        Label("Structured Notes V2", systemImage: "square.stack.3d.up")
          .font(.headline)

        Text("EXPERIMENTAL")
          .font(.caption2.weight(.bold))
          .tracking(0.7)
          .foregroundStyle(.orange)
          .padding(.horizontal, 7)
          .padding(.vertical, 3)
          .background(.orange.opacity(0.12), in: Capsule())

        Spacer()
      }
      .padding(.horizontal, 24)
      .padding(.vertical, 16)

      Divider()

      ContentUnavailableView {
        Label("No structured notes yet", systemImage: "square.stack.3d.up.slash")
      } description: {
        Text(
          store.sidebarMode == .list
            ? "Create a blank list note or upgrade your legacy list-note library."
            : "Create a blank note for today or make structured copies of your legacy daily notes."
        )
      } actions: {
        HStack {
          Button(store.sidebarMode == .list ? "Create list note" : "Create today's note") {
            if store.sidebarMode == .list {
              store.createListNote()
            } else {
              store.selectToday()
            }
          }
          .buttonStyle(.borderedProminent)

          Button(store.sidebarMode == .list ? "Copy legacy list notes" : "Copy legacy daily notes")
          {
            if store.sidebarMode == .list {
              do {
                _ = try store.copyLegacyListNotesToStructuredLibrary()
              } catch {
                store.showTransientMessage(error.localizedDescription, kind: .error)
              }
            } else {
              store.copyLegacyDailyNotesToStructuredLibrary()
            }
          }
          .buttonStyle(.bordered)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
