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
    Group {
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
    }
  }
}

private struct NextMarkdownTextView: View {
  let noteID: DayNote.ID
  @Binding var text: String
  let appearanceSettings: NoteAppearanceSettings

  var body: some View {
    // Stage 1 keeps both paths behavior-identical while the TextKit 2 shell is built.
    MarkdownTextView(
      noteID: noteID,
      text: $text,
      appearanceSettings: appearanceSettings
    )
  }
}
