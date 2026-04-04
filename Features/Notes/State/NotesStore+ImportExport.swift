//
//  NotesStore+ImportExport.swift
//

// NotesStore extension for importing and exporting notes.

import AppKit
import UniformTypeIdentifiers

// MARK: - Import & Export

extension NotesStore {

  // Opens a folder picker and imports notes from an unzipped Diarly export.
  func importFromDiarly() {
    importFromFolder(
      panelTitle: "Select Diarly Export Folder",
      panelMessage: "Choose the unzipped Diarly export folder (e.g. Export)",
      context: "Importing from Diarly failed",
      emptyMessage: "No Diarly notes found in the selected folder."
    ) { folderURL, existingIDs in
      let result = try DiarlyImporter.importNotes(
        from: folderURL,
        existingNoteIDs: existingIDs,
        calendar: calendar
      )

      return ImportOutcome(
        imported: result.imported,
        skipped: result.skipped,
        extraDetail: result.merged > 0 ? "\(result.merged) same-day entries merged" : nil
      )
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
    Task { [weak self] in
      do {
        let zipURL = try ScealArchiveExporter.exportNotes(filtered)

        if fm.fileExists(atPath: saveURL.path) {
          try fm.removeItem(at: saveURL)
        }
        try fm.moveItem(at: zipURL, to: saveURL)

        ScealArchiveExporter.cleanUp(zipURL: zipURL)

        self?.userMessage = (text: "Exported \(noteCount) notes.", kind: .info)
      } catch {
        self?.report(error, context: "Exporting notes failed")
      }
    }
  }

  // Opens a folder picker and imports notes from an unzipped Scéal export.
  func importFromSceal() {
    importFromFolder(
      panelTitle: "Select Scéal Export Folder",
      panelMessage: "Choose the unzipped Scéal export folder",
      context: "Importing from Scéal failed",
      emptyMessage: "No Scéal notes found in the selected folder."
    ) { folderURL, existingIDs in
      let result = try ScealArchiveImporter.importNotes(
        from: folderURL,
        existingNoteIDs: existingIDs
      )

      return ImportOutcome(
        imported: result.imported,
        skipped: result.skipped,
        extraDetail: result.failed > 0 ? "\(result.failed) failed to parse" : nil
      )
    }
  }

  // Shared import payload used by both Diarly and Scéal folder import flows.
  private struct ImportOutcome {
    let imported: [DayNote]
    let skipped: Int
    let extraDetail: String?
  }

  // Runs a folder-import flow with shared panel, persistence, and user-message handling.
  private func importFromFolder(
    panelTitle: String,
    panelMessage: String,
    context: String,
    emptyMessage: String,
    importBlock: (_ folderURL: URL, _ existingNoteIDs: Set<DayNote.ID>) throws -> ImportOutcome
  ) {
    guard let folderURL = selectImportFolder(title: panelTitle, message: panelMessage) else {
      return
    }

    let existingIDs = Set(notes.map(\.id))

    do {
      let outcome = try importBlock(folderURL, existingIDs)
      try persistImportedNotes(outcome.imported)
      showImportMessage(outcome, emptyMessage: emptyMessage)
    } catch {
      report(error, context: context)
    }
  }

  // Opens a folder picker configured for import flows.
  private func selectImportFolder(title: String, message: String) -> URL? {
    let panel = NSOpenPanel()
    panel.title = title
    panel.message = message
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false

    guard panel.runModal() == .OK else {
      return nil
    }

    return panel.url
  }

  // Persists imported notes, then updates in-memory state and index in one place.
  private func persistImportedNotes(_ imported: [DayNote]) throws {
    for note in imported {
      try save(note)
    }

    notes = (notes + imported).sorted(by: { $0.date > $1.date })
    rebuildNoteIndex()
  }

  // Shows the user-facing import result message with consistent formatting across importers.
  private func showImportMessage(_ outcome: ImportOutcome, emptyMessage: String) {
    if outcome.imported.isEmpty && outcome.skipped > 0 {
      userMessage = (
        text: "No new notes imported. \(outcome.skipped) dates already exist in Scéal.",
        kind: .info
      )
      return
    }

    guard !outcome.imported.isEmpty else {
      userMessage = (text: emptyMessage, kind: .info)
      return
    }

    var details: [String] = []
    if outcome.skipped > 0 { details.append("\(outcome.skipped) skipped") }
    if let extraDetail = outcome.extraDetail { details.append(extraDetail) }

    let suffix = details.isEmpty ? "" : " (\(details.joined(separator: ", ")))"
    userMessage = (text: "Imported \(outcome.imported.count) notes.\(suffix)", kind: .info)
    selectedNoteID = outcome.imported.first?.id
  }
}
