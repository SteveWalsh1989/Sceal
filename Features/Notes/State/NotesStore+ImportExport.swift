//
//  NotesStore+ImportExport.swift
//

// NotesStore extension for importing and exporting notes.

import AppKit
import UniformTypeIdentifiers

// MARK: - Import & Export

extension NotesStore {

  // Opens a folder picker and imports dated Markdown files from common note apps.
  func importFromMarkdown() {
    let cal = calendar
    importFromFolder(
      panelTitle: "Select Markdown Folder",
      panelMessage:
        "Choose a folder of dated Markdown files from Obsidian, Logseq, Joplin, Bear, Apple Notes, or a similar app.",
      context: "Importing Markdown notes failed",
      emptyMessage: "No dated Markdown notes found in the selected folder."
    ) { folderURL, existingIDs in
      let result = try GenericMarkdownImporter.importNotes(
        from: folderURL,
        existingNoteIDs: existingIDs,
        calendar: cal
      )

      let extraDetails = [
        result.merged > 0 ? "\(result.merged) same-day files merged" : nil,
        result.missingDate > 0 ? "\(result.missingDate) missing dates" : nil,
        result.failed > 0 ? "\(result.failed) failed to parse" : nil,
      ].compactMap { $0 }

      return ImportOutcome(
        imported: result.imported,
        skipped: result.skipped,
        extraDetail: extraDetails.isEmpty ? nil : extraDetails.joined(separator: ", ")
      )
    }
  }

  // Opens a folder picker and imports notes from an unzipped Diarly export.
  func importFromDiarly() {
    let cal = calendar
    importFromFolder(
      panelTitle: "Select Diarly Export Folder",
      panelMessage: "Choose the unzipped Diarly export folder (e.g. Export)",
      context: "Importing from Diarly failed",
      emptyMessage: "No Diarly notes found in the selected folder."
    ) { folderURL, existingIDs in
      let result = try DiarlyImporter.importNotes(
        from: folderURL,
        existingNoteIDs: existingIDs,
        calendar: cal
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

    isPerformingFileOperation = true
    progressMessage = "Exporting…"

    let fm = fileManager
    let noteCount = filtered.count
    Task.detached { [weak self] in
      do {
        let zipURL = try ScealArchiveExporter.exportNotes(filtered)

        if fm.fileExists(atPath: saveURL.path) {
          try fm.removeItem(at: saveURL)
        }
        try fm.moveItem(at: zipURL, to: saveURL)

        ScealArchiveExporter.cleanUp(zipURL: zipURL)

        await MainActor.run { [weak self] in
          self?.userMessage = (text: "Exported \(noteCount) notes.", kind: .info)
          self?.isPerformingFileOperation = false
          self?.progressMessage = nil
        }
      } catch {
        await MainActor.run { [weak self] in
          self?.report(error, context: "Exporting notes failed")
          self?.isPerformingFileOperation = false
          self?.progressMessage = nil
        }
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

  // Shared import payload used by folder import flows.
  private struct ImportOutcome: Sendable {
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
    importBlock:
      @Sendable @escaping (_ folderURL: URL, _ existingNoteIDs: Set<DayNote.ID>) throws ->
      ImportOutcome
  ) {
    guard let folderURL = selectImportFolder(title: panelTitle, message: panelMessage) else {
      return
    }

    let existingIDs = Set(notes.map(\.id))

    // Resolve notes directory on main actor and start background work.
    let notesDir: URL
    do {
      notesDir = try notesDirectoryURL()
    } catch {
      report(error, context: context)
      return
    }

    isPerformingFileOperation = true
    progressMessage = "Importing…"

    // Explicitly acquire security-scoped access so the detached task can
    // read the user-selected folder inside the App Sandbox.
    let didStartAccessing = folderURL.startAccessingSecurityScopedResource()

    Task.detached { [weak self] in
      defer {
        if didStartAccessing { folderURL.stopAccessingSecurityScopedResource() }
      }

      do {
        // Step 1: Parse on a background thread.
        let outcome = try importBlock(folderURL, existingIDs)

        // If nothing to import, finish early on main.
        if outcome.imported.isEmpty {
          await MainActor.run { [weak self] in
            self?.showImportMessage(outcome, emptyMessage: emptyMessage)
            self?.isPerformingFileOperation = false
            self?.progressMessage = nil
          }
          return
        }

        // Step 2: Write imported notes to disk off the main thread.
        for (idx, note) in outcome.imported.enumerated() {
          let fileURL = notesDir.appendingPathComponent(note.fileName)
          let contents = try MarkdownNoteCodec.encode(note)
          try contents.write(to: fileURL, atomically: true, encoding: .utf8)

          if idx % 10 == 0 || idx == outcome.imported.count - 1 {
            await MainActor.run { [weak self] in
              self?.progressMessage = "Saving \(idx + 1)/\(outcome.imported.count)…"
            }
          }
        }

        // Step 3: Update in-memory state and notify the user on the main actor.
        await MainActor.run { [weak self] in
          guard let self else { return }
          self.notes = (self.notes + outcome.imported).sorted(by: { $0.date > $1.date })
          self.rebuildNoteIndex()
          self.showImportMessage(outcome, emptyMessage: emptyMessage)
          self.checkAndRunBackupIfDue(trigger: .postImport)
          self.isPerformingFileOperation = false
          self.progressMessage = nil
        }
      } catch {
        await MainActor.run { [weak self] in
          self?.report(error, context: context)
          self?.isPerformingFileOperation = false
          self?.progressMessage = nil
        }
      }
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
