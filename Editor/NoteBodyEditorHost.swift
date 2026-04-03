//
//  NoteBodyEditorHost.swift
//

// Versioned editor host that keeps the current TextKit 1 editor as the safe fallback.

import SwiftUI

struct NoteBodyEditorHost: View {
  let noteID: DayNote.ID
  @Binding var text: String
  let appearanceSettings: NoteAppearanceSettings
  let editorVersion: EditorVersion

  var body: some View {
    ZStack(alignment: .topTrailing) {
      switch editorVersion {
      case .legacy:
        MarkdownTextView(
          noteID: noteID,
          text: $text,
          appearanceSettings: appearanceSettings
        )
      case .next:
        NextMarkdownTextView(
          noteID: noteID,
          text: $text,
          appearanceSettings: appearanceSettings
        )
      }

      if editorVersion == .next {
        NextEditorBadge()
          .padding(.top, 12)
          .padding(.trailing, 14)
      }
    }
  }
}

private struct NextEditorBadge: View {
  var body: some View {
    HStack(spacing: 6) {
      Circle()
        .fill(Color.teal)
        .frame(width: 7, height: 7)

      Text("Next Preview")
        .font(.system(size: 11, weight: .semibold))
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(.regularMaterial, in: Capsule())
    .overlay(
      Capsule()
        .strokeBorder(Color.teal.opacity(0.18), lineWidth: 1)
    )
  }
}
