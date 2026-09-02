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
          "This mode stores daily notes as editable structured sections in a separate folder. It remains opt-in while lossless full-library migration is completed."
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
          "Daily-note editing and portable Markdown export are available. Lossless structured backup and restore, list-note migration, and final cutover checks arrive in Stage 10. Those full-library actions stay blocked to prevent incomplete results."
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
