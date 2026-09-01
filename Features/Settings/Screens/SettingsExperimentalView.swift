//
//  SettingsExperimentalView.swift
//

// Opt-in controls and storage diagnostics for work-in-progress product modes.

import SwiftUI

struct SettingsExperimentalView: View {
  @ObservedObject var store: NotesStore

  var body: some View {
    Form {
      Section {
        Label("Structured Notes V2", systemImage: "square.stack.3d.up")
          .font(.headline)

        Text(
          "This mode stores daily notes as editable structured sections in a separate folder. It remains opt-in while section controls and feature parity are built."
        )
        .foregroundStyle(.secondary)
      }

      Section("Daily-note mode") {
        Toggle(
          "Use Structured Notes V2",
          isOn: Binding(
            get: { store.dailyNoteStorageMode == .structuredExperimental },
            set: {
              store.updateDailyNoteStorageMode(
                $0 ? .structuredExperimental : .legacyMarkdown
              )
            }
          )
        )

        LabeledContent("Active mode") {
          Text(store.dailyNoteStorageMode.displayName)
            .foregroundStyle(.secondary)
        }

        Text(
          "Switching modes does not migrate, replace, or synchronize files. Each mode keeps its own selection and search state."
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
      }

      Section("Create structured copies") {
        Button("Copy legacy daily notes into structured library") {
          store.copyLegacyDailyNotesToStructuredLibrary()
        }
        .disabled(store.isPerformingFileOperation)

        Text(
          "Scéal validates every source note first, writes separate .scealnote files, and keeps existing structured copies when the action is run again. The original Markdown files are never changed."
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
      }

      Section("Storage") {
        storagePath("Library root", url: store.libraryLocation.rootURL)
        storagePath("Active daily-note folder", url: store.activeDailyNotesStorageURL)
        storagePath("Legacy Markdown folder", url: store.legacyDailyNotesStorageURL)
        storagePath("Structured notes folder", url: store.structuredDailyNotesStorageURL)
      }

      Section("Current limitations") {
        Text(
          "Basic section editing is available. Section splitting, options, and keyboard boundary navigation arrive in Stage 5. Portable export is connected in Stage 9, and lossless structured backup and restore arrive in Stage 10. Those legacy-only actions stay blocked to prevent incomplete results."
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
  }

  private func storagePath(_ title: String, url: URL) -> some View {
    LabeledContent(title) {
      Text(url.path)
        .font(.caption)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
    }
  }
}
