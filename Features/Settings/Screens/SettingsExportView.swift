//
//  SettingsExportView.swift
//

// Settings panel for exporting notes within a date range.

import SwiftUI

struct SettingsExportView: View {
  @ObservedObject var store: NotesStore
  @State private var startDate = Date.now
  @State private var endDate = Date.now

  var body: some View {
    Form {
      Section {
        Text("Export your notes as a zip archive of markdown files.")
          .foregroundStyle(.secondary)
      }

      Section("Date Range") {
        DatePicker("From", selection: $startDate, displayedComponents: .date)
        DatePicker("To", selection: $endDate, displayedComponents: .date)
      }

      Section("Scéal Export") {
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text("Export notes")
              .font(.body)
            Text("Creates a zip with your notes organized by year.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          Spacer()

          Button("Export\u{2026}") {
            store.exportNotes(startDate: startDate, endDate: endDate)
          }
        }
      }
    }
    .formStyle(.grouped)
    .onAppear {
      initializeDateRange()
    }
  }

  // Sets the date pickers to cover the full range of existing notes.
  private func initializeDateRange() {
    let dates = store.notes.map(\.date)
    if let earliest = dates.min(), let latest = dates.max() {
      startDate = earliest
      endDate = latest
    }
  }
}
