//
//  NoteEditorView.swift
//  dayra
//
//

import SwiftUI

struct NoteEditorView: View {
  @ObservedObject var store: NoteStore
  let noteID: DayNote.ID

  var body: some View {
    if let note = store.note(withID: noteID) {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .center, spacing: 12) {
          Text(note.editorDateText)
            .font(.callout)
            .foregroundStyle(.secondary)

          Spacer()

          TextField("Tags", text: store.tagsBinding(for: noteID))
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)

          Button {
            store.selectToday()
          } label: {
            Label("Today", systemImage: "calendar")
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
        }

        TextField("Title", text: store.titleBinding(for: noteID))
          .textFieldStyle(.plain)
          .font(.system(size: 30, weight: .bold))

        ZStack(alignment: .topLeading) {
          if note.body.isEmpty {
            Text("Start writing today's note here.")
              .foregroundStyle(.secondary)
              .padding(.horizontal, 34)
              .padding(.vertical, 30)
          }

          MarkdownTextView(text: store.bodyBinding(for: noteID))
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
