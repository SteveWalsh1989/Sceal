//
//  ImportSettingsView.swift
//

import SwiftUI

struct ImportSettingsView: View {
  @ObservedObject var store: NoteStore

  var body: some View {
    Form {
      Section {
        Text("Import notes from other journaling apps into Scéal.")
          .foregroundStyle(.secondary)
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
