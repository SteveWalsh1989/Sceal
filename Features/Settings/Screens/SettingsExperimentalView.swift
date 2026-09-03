//
//  SettingsExperimentalView.swift
//

// Opt-in controls and storage diagnostics for work-in-progress product modes.

import SwiftUI

struct SettingsExperimentalView: View {
  @ObservedObject var store: NotesStore
  @State private var isShowingUpgradeConfirmation = false

  var body: some View {
    Form {
      Section {
        Label("Structured Notes V2", systemImage: "square.stack.3d.up")
          .font(.headline)

        Text(
          "This mode stores daily and list notes as editable structured sections in separate folders. It remains opt-in during real-library testing."
        )
        .foregroundStyle(.secondary)
      }

      Section("Note storage mode") {
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
        .disabled(
          store.enforcesStructuredCutover
            && store.structuredNotesCutoverStatus != .completed
        )

        LabeledContent("Active mode") {
          Text(store.dailyNoteStorageMode.displayName)
            .foregroundStyle(.secondary)
        }

        if store.enforcesStructuredCutover {
          LabeledContent("Conversion") {
            Text(cutoverStatusLabel)
              .foregroundStyle(.secondary)
          }
        }

        Text(
          "Switching back to Legacy Markdown is the rollback path. Changing this toggle never deletes, replaces, or synchronizes either library."
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
      }

      Section("Full-library upgrade") {
        Button(fullLibraryUpgradeButtonTitle) {
          isShowingUpgradeConfirmation = true
        }
        .disabled(store.isPerformingFileOperation || store.isBackupRunning)

        Text(
          "Creates a complete safety archive first, imports daily notes, list notes, and list-library groups without changing Markdown, then writes a migration comparison report. It does not enable structured mode automatically."
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
      }

      Section("Individual copy tools") {
        Button("Copy legacy daily notes into structured library") {
          store.copyLegacyDailyNotesToStructuredLibrary()
        }
        .disabled(store.isPerformingFileOperation)

        Button("Copy legacy list notes into structured library") {
          do {
            _ = try store.copyLegacyListNotesToStructuredLibrary()
            store.showTransientMessage("Legacy list notes copied.", kind: .info)
          } catch {
            store.report(error, context: "Copying legacy list notes failed")
          }
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
        storagePath("Structured list notes folder", url: store.structuredListNotesStorageURL)
      }
    }
    .formStyle(.grouped)
    .confirmationDialog(
      "Upgrade the full library?",
      isPresented: $isShowingUpgradeConfirmation,
      titleVisibility: .visible
    ) {
      Button("Create Safety Backup and Upgrade") {
        if store.enforcesStructuredCutover {
          store.backUpAndConvertLegacyLibrary()
        } else {
          store.upgradeFullLibraryToStructured()
        }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(fullLibraryUpgradeConfirmationMessage)
    }
  }

  private var fullLibraryUpgradeButtonTitle: String {
    store.enforcesStructuredCutover
      ? "Back Up and Convert to Structured Notes V2..."
      : "Upgrade full library to Structured Notes V2..."
  }

  private var cutoverStatusLabel: String {
    switch store.structuredNotesCutoverStatus {
    case .notStarted:
      return "Not started"
    case .conversionRequired:
      return "Required"
    case .completed:
      return "Validated"
    case .failedValidation:
      return "Needs attention"
    }
  }

  private var fullLibraryUpgradeConfirmationMessage: String {
    if store.enforcesStructuredCutover {
      return
        "Scéal will keep all legacy Markdown files for rollback and activate structured mode only after the staged conversion passes exact validation. Existing experimental structured copies will be retained in the safety backup before being replaced."
    }
    return
      "Scéal will keep all legacy Markdown files for rollback. Structured mode remains off until you enable it after reviewing the migration report."
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
