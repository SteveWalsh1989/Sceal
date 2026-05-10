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
            "Shows four in-memory daily notes dated from today through the previous three days. Real notes are restored when this is turned off."
          )
          .font(.footnote)
          .foregroundStyle(.secondary)
        }

        Section("File-backed Developer Library") {
          Button("Reset and seed developer library", role: .destructive) {
            store.resetDeveloperLibrary()
          }
          .disabled(!store.canResetDeveloperLibrary)

          Text(
            "Replaces the active non-production library with deterministic daily notes, one list note, a group manifest, and a fixture attachment."
          )
          .font(.footnote)
          .foregroundStyle(.secondary)
        }

        Section("Storage") {
          LabeledContent("Active library") {
            Text(store.libraryLocation.rootURL.path)
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
