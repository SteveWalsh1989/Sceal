//
//  SettingsImportView.swift
//

// Settings panel for importing notes from Markdown apps or previous exports.

import SwiftUI

struct SettingsImportView: View {
  @ObservedObject var store: NotesStore

  var body: some View {
    Form {
      Section {
        Text("Import notes from Markdown-based apps or previous Scéal exports.")
          .foregroundStyle(.secondary)
      }

      Section("Markdown") {
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text("Import from Markdown")
              .font(.body)
            Text(
              "Supports dated Markdown folders from Obsidian, Logseq, Joplin, Bear, Apple Notes, and similar apps."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
          }

          Spacer()

          Button("Import\u{2026}") {
            store.importFromMarkdown()
          }
        }
      }

      Section("Scéal") {
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text("Import from Scéal")
              .font(.body)
            Text("Select an unzipped Scéal export folder.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          Spacer()

          Button("Import\u{2026}") {
            store.importFromSceal()
          }
        }
      }

      Section("Diarly") {
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text("Import from Diarly")
              .font(.body)
            Text("Select an unzipped Diarly markdown export folder.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          Spacer()

          Button("Import\u{2026}") {
            store.importFromDiarly()
          }
        }
      }
    }
    .formStyle(.grouped)
  }
}
