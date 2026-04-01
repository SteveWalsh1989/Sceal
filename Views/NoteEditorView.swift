//
//  NoteEditorView.swift
//  dayra
//
//

import SwiftUI

struct NoteEditorView: View {
  @ObservedObject var store: NoteStore
  let noteID: DayNote.ID

  private var adjacentNoteIDs: (previous: DayNote.ID?, next: DayNote.ID?) {
    store.adjacentNoteIDs(for: noteID)
  }

  var body: some View {
    if let note = store.note(withID: noteID) {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .center, spacing: 12) {
          HStack(spacing: 8) {
            Text(note.editorDateText)
              .font(.callout)
              .foregroundStyle(.secondary)

            if let previousNoteID = adjacentNoteIDs.previous {
              HeaderNavigationButton(
                systemImage: "chevron.left",
                accessibilityLabel: "Open older note"
              ) {
                store.select(noteID: previousNoteID)
              }
            }

            if let nextNoteID = adjacentNoteIDs.next {
              HeaderNavigationButton(
                systemImage: "chevron.right",
                accessibilityLabel: "Open newer note"
              ) {
                store.select(noteID: nextNoteID)
              }
            }
          }

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
      .padding(.horizontal, 24)
      .padding(.bottom, 24)
      .padding(.top, 12)
    } else {
      ContentUnavailableView(
        "Note unavailable",
        systemImage: "square.and.pencil",
        description: Text("Select another day from the sidebar.")
      )
    }
  }
}

// Keeps header note-jump actions compact and visually aligned with the date.
private struct HeaderNavigationButton: View {
  let systemImage: String
  let accessibilityLabel: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
        .frame(width: 24, height: 24)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(accessibilityLabel)
  }
}
