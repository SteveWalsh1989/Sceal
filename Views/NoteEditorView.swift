//
//  NoteEditorView.swift
//  dayra
//
//  Created by Steve Walsh on 01/04/2026.
//

import SwiftUI

struct NoteEditorView: View {
  @ObservedObject var store: NoteStore
  let noteID: DayNote.ID

  var body: some View {
    if let note = store.note(withID: noteID) {
      VStack(alignment: .leading, spacing: 24) {
        editorHeader(for: note)

        VStack(alignment: .leading, spacing: 12) {
          Text("Title")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

          TextField("Add a title for this day", text: store.titleBinding(for: noteID))
            .textFieldStyle(.plain)
            .font(.system(size: 28, weight: .semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(
              RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.primary.opacity(0.04))
            )
        }

        VStack(alignment: .leading, spacing: 12) {
          Text("Tags")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

          TextField("Add comma-separated tags", text: store.tagsBinding(for: noteID))
            .textFieldStyle(.plain)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
              RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.primary.opacity(0.04))
            )
        }

        VStack(alignment: .leading, spacing: 12) {
          Text("Note")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

          ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
              .fill(Color.primary.opacity(0.04))

            if note.body.isEmpty {
              Text("Start writing today's note here.")
                .foregroundStyle(.secondary)
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
            }

            TextEditor(text: store.bodyBinding(for: noteID))
              .font(.system(size: 15))
              .scrollContentBackground(.hidden)
              .padding(12)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
      .padding(28)
    } else {
      ContentUnavailableView(
        "Note unavailable",
        systemImage: "square.and.pencil",
        description: Text("Select another day from the sidebar.")
      )
    }
  }

  private func editorHeader(for note: DayNote) -> some View {
    HStack(alignment: .top) {
      VStack(alignment: .leading, spacing: 6) {
        Text(note.editorDateText)
          .font(.title3.weight(.semibold))

        Text("One note per day, stored locally as markdown.")
          .font(.callout)
          .foregroundStyle(.secondary)
      }

      Spacer()

      Button {
        store.selectToday()
      } label: {
        Label("Today", systemImage: "calendar")
      }
      .buttonStyle(.bordered)
    }
  }
}
