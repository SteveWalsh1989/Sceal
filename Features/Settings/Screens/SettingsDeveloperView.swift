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
  }
#endif
