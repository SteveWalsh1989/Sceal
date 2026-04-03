//
//  NoteStore+ImportExport.swift
//

import AppKit
import UniformTypeIdentifiers

// MARK: - Import & Export

extension NoteStore {

  // Opens a folder picker and imports notes from an unzipped Diarly export.
  func importFromDiarly() {
    let panel = NSOpenPanel()
    panel.title = "Select Diarly Export Folder"
    panel.message = "Choose the unzipped Diarly export folder (e.g. Export)"
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false

    guard panel.runModal() == .OK, let folderURL = panel.url else { return }

    let existingIDs = Set(notes.map(\.id))

    do {
      let result = try DiarlyImporter.importNotes(
        from: folderURL, existingNoteIDs: existingIDs, calendar: calendar)

      for note in result.imported {
        try save(note)
      }

      notes = (notes + result.imported).sorted(by: { $0.date > $1.date })
      rebuildNoteIndex()

      if result.imported.isEmpty && result.skipped > 0 {
        userMessage = (
          text: "No new notes imported. \(result.skipped) dates already exist in Scéal.",
          kind: .info
        )
      } else if result.imported.isEmpty {
        userMessage = (text: "No Diarly notes found in the selected folder.", kind: .info)
      } else {
        var details: [String] = []
        if result.skipped > 0 { details.append("\(result.skipped) skipped") }
        if result.merged > 0 { details.append("\(result.merged) same-day entries merged") }
        let suffix = details.isEmpty ? "" : " (\(details.joined(separator: ", ")))"
        userMessage = (text: "Imported \(result.imported.count) notes.\(suffix)", kind: .info)
        selectedNoteID = result.imported.first?.id
      }
    } catch {
      report(error, context: "Importing from Diarly failed")
    }
  }

  // Exports notes within a date range to a zip file at a user-chosen location.
  func exportNotes(startDate: Date, endDate: Date) {
    flushPendingSaves()

    let filtered = notes.filter { note in
      let noteDay = calendar.startOfDay(for: note.date)
      return noteDay >= calendar.startOfDay(for: startDate)
        && noteDay <= calendar.startOfDay(for: endDate)
    }

    guard !filtered.isEmpty else {
      userMessage = (text: "No notes found in the selected date range.", kind: .info)
      return
    }

    let panel = NSSavePanel()
    panel.title = "Export Notes"
    panel.nameFieldStringValue = "sceal-export.zip"
    panel.allowedContentTypes = [.zip]

    guard panel.runModal() == .OK, let saveURL = panel.url else { return }

    let fm = fileManager
    let noteCount = filtered.count
    // Run the heavy export (file staging + ditto zip) off the main actor.
    Task.detached { [weak self] in
      do {
        let zipURL = try await MainActor.run { try ScealExporter.exportNotes(filtered) }

        if fm.fileExists(atPath: saveURL.path) {
          try fm.removeItem(at: saveURL)
        }
        try fm.moveItem(at: zipURL, to: saveURL)

        await MainActor.run {
          ScealExporter.cleanUp(zipURL: zipURL)
        }
        await MainActor.run {
          self?.userMessage = (text: "Exported \(noteCount) notes.", kind: .info)
        }
      } catch {
        await MainActor.run {
          self?.report(error, context: "Exporting notes failed")
        }
      }
    }
  }

  // Opens a folder picker and imports notes from an unzipped Scéal export.
  func importFromSceal() {
    let panel = NSOpenPanel()
    panel.title = "Select Scéal Export Folder"
    panel.message = "Choose the unzipped Scéal export folder"
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false

    guard panel.runModal() == .OK, let folderURL = panel.url else { return }

    let existingIDs = Set(notes.map(\.id))

    do {
      let result = try ScealImporter.importNotes(
        from: folderURL, existingNoteIDs: existingIDs)

      for note in result.imported {
        try save(note)
      }

      notes = (notes + result.imported).sorted(by: { $0.date > $1.date })
      rebuildNoteIndex()

      if result.imported.isEmpty && result.skipped > 0 {
        userMessage = (
          text: "No new notes imported. \(result.skipped) dates already exist in Scéal.",
          kind: .info
        )
      } else if result.imported.isEmpty {
        userMessage = (text: "No Scéal notes found in the selected folder.", kind: .info)
      } else {
        var details: [String] = []
        if result.skipped > 0 { details.append("\(result.skipped) skipped") }
        if result.failed > 0 { details.append("\(result.failed) failed to parse") }
        let suffix = details.isEmpty ? "" : " (\(details.joined(separator: ", ")))"
        userMessage = (text: "Imported \(result.imported.count) notes.\(suffix)", kind: .info)
        selectedNoteID = result.imported.first?.id
      }
    } catch {
      report(error, context: "Importing from Scéal failed")
    }
  }
}
