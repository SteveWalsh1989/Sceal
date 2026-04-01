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
      VStack(alignment: .leading, spacing: 18) {
        TextField("Title", text: store.titleBinding(for: noteID))
          .textFieldStyle(.plain)
          .font(.system(size: 30, weight: .bold))

        HStack(alignment: .center, spacing: 12) {
          Text(note.editorDateText)
            .font(.callout)
            .foregroundStyle(.secondary)

          Spacer()

          Button {
            store.selectToday()
          } label: {
            Label("Today", systemImage: "calendar")
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
        }

        TextField("Tags", text: store.tagsBinding(for: noteID))
          .textFieldStyle(.plain)
          .font(.system(size: 14, weight: .medium))
          .padding(.horizontal, 14)
          .padding(.vertical, 10)
          .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
              .fill(Color.primary.opacity(0.04))
          )

        ZStack(alignment: .topLeading) {
          RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color.primary.opacity(0.04))

          if note.body.isEmpty {
            Text("Start writing today's note here.")
              .foregroundStyle(.secondary)
              .padding(.horizontal, 22)
              .padding(.vertical, 18)
          }

          MarkdownTextView(text: store.bodyBinding(for: noteID))
            .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .padding(24)
    } else {
      ContentUnavailableView(
        "Note unavailable",
        systemImage: "square.and.pencil",
        description: Text("Select another day from the sidebar.")
      )
    }
  }
}
