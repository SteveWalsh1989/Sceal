//
//  SettingsDeveloperView.swift
//

// DEBUG-only settings for local testing and screenshot workflows.

#if DEBUG
  import SwiftUI

  struct SettingsDeveloperView: View {
    @ObservedObject var store: NotesStore

    var body: some View {
      Form {
        Section("Plan") {
          Picker(
            "Active plan",
            selection: Binding(
              get: { store.activePlan },
              set: { scheduleDeveloperPlanUpdate($0) }
            )
          ) {
            ForEach(AppPlan.allCases) { plan in
              Text(plan.displayName).tag(plan)
            }
          }
          .pickerStyle(.segmented)

          ForEach(AppCapability.allCases) { capability in
            LabeledContent(capability.displayName) {
              if store.hasAccess(to: capability) {
                Text("Included")
                  .foregroundStyle(.secondary)
              } else {
                Text("Locked")
                  .foregroundStyle(.orange)
              }
            }
          }
        }

        Section("Demo Library") {
          Toggle(
            "Use demo notes",
            isOn: Binding(
              get: { store.isDemoModeEnabled },
              set: { store.setDemoModeEnabled($0) }
            )
          )

          Text(
            "Shows four structured daily notes in disposable storage. Your real library and selection return when this is turned off. Demo edits are not copied back."
          )
          .font(.footnote)
          .foregroundStyle(.secondary)
        }

        Section("File-backed Developer Library") {
          Button("Copy production library to developer library") {
            store.copyProductionLibraryToDeveloperLibrary()
          }
          .disabled(
            !store.canCopyProductionLibraryToDeveloper || store.isDemoModeEnabled
          )

          Button("Reset and seed developer library", role: .destructive) {
            store.resetDeveloperLibrary()
          }
          .disabled(!store.canResetDeveloperLibrary || store.isDemoModeEnabled)

          Text(
            "Use the production copy when you need real notes in DEBUG without writing to the production library. Reset preserves the previous developer folder beside it and creates deterministic structured test data."
          )
          .font(.footnote)
          .foregroundStyle(.secondary)
        }

        Section("Storage") {
          LabeledContent("Daily-note mode") {
            Text("Structured notes")
              .foregroundStyle(.secondary)
          }

          LabeledContent("Active library") {
            Text(store.libraryLocation.rootURL.path)
              .font(.caption)
              .foregroundStyle(.secondary)
              .textSelection(.enabled)
          }

          LabeledContent("Active daily-note folder") {
            Text(store.activeDailyNotesStorageURL.path)
              .font(.caption)
              .foregroundStyle(.secondary)
              .textSelection(.enabled)
          }

          LabeledContent("Original Markdown (recovery)") {
            Text(store.legacyDailyNotesStorageURL.path)
              .font(.caption)
              .foregroundStyle(.secondary)
              .textSelection(.enabled)
          }

          LabeledContent("Structured notes folder") {
            Text(store.structuredDailyNotesStorageURL.path)
              .font(.caption)
              .foregroundStyle(.secondary)
              .textSelection(.enabled)
          }
        }
      }
      .formStyle(.grouped)
    }

    private func scheduleDeveloperPlanUpdate(_ plan: AppPlan) {
      Task { @MainActor in
        store.updateDeveloperPlan(plan)
      }
    }
  }
#endif
