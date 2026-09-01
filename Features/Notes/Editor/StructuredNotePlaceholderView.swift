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
          "Create a blank note for today or make structured copies of your legacy daily notes."
        )
      } actions: {
        HStack {
          Button("Create today's note") {
            store.selectToday()
          }
          .buttonStyle(.borderedProminent)

          Button("Copy legacy daily notes") {
            store.copyLegacyDailyNotesToStructuredLibrary()
          }
          .buttonStyle(.bordered)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
