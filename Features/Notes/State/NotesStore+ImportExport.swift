//
//  NotesStore+ImportExport.swift
//

// NotesStore extension for importing and exporting notes.

import AppKit
import UniformTypeIdentifiers

// MARK: - Import & Export

extension NotesStore {

  // Opens a file picker and imports notes from a Day One JSON export.
  func importFromDayOne() {
    let cal = calendar
    importFromFile(
      panelTitle: "Select Day One Export",
      panelMessage: "Choose a Day One JSON export zip or extracted JSON file.",
      allowedContentTypes: [.zip, .json],
      context: "Importing from Day One failed",
      emptyMessage: "No Day One entries found in the selected export."
    ) { fileURL, existingIDs in
      let result = try DayOneImporter.importNotes(
        from: fileURL,
        existingNoteIDs: existingIDs,
        calendar: cal
      )

      let mediaDetails = [
        result.omittedPhotos > 0 ? "\(result.omittedPhotos) photos omitted" : nil,
        result.omittedVideos > 0 ? "\(result.omittedVideos) videos omitted" : nil,
        result.omittedAudios > 0 ? "\(result.omittedAudios) audio files omitted" : nil,
        result.omittedPDFs > 0 ? "\(result.omittedPDFs) PDFs omitted" : nil,
      ].compactMap { $0 }

      let extraDetails = [
        result.merged > 0 ? "\(result.merged) same-day entries merged" : nil,
        result.missingTimeZone > 0
          ? "\(result.missingTimeZone) missing or invalid time zones" : nil,
        result.failed > 0 ? "\(result.failed) failed to parse" : nil,
        mediaDetails.isEmpty ? nil : mediaDetails.joined(separator: ", "),
      ].compactMap { $0 }

      return ImportOutcome(
        imported: result.imported,
        skipped: result.skipped,
        extraDetail: extraDetails.isEmpty ? nil : extraDetails.joined(separator: ", ")
      )
    }
  }

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
    let templatesSnapshot = noteTemplates
    let attachmentsRootURL = libraryRepository.attachmentsRootURL
    Task.detached { [weak self] in
      do {
        let zipURL = try ScealArchiveExporter.exportNotes(
          filtered,
          templates: templatesSnapshot,
          attachmentsRootURL: attachmentsRootURL
        )

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

  // Exports the whole library, including list notes, groups, metadata, and attachments.
  func exportFullLibrary() {
    #if DEBUG
      if isDemoModeEnabled {
        userMessage = (
          text: "Turn off Demo Library before exporting your real library.", kind: .info
        )
        return
      }
    #endif

    guard !isPerformingFileOperation else {
      userMessage = (text: "Wait for the current file operation to finish.", kind: .info)
      return
    }

    flushPendingSaves()

    let dailyNotesSnapshot = notes
    let listNotesSnapshot = listNotes
    let manifestSnapshot = listNoteManifest
    let templatesSnapshot = noteTemplates
    guard !dailyNotesSnapshot.isEmpty || !listNotesSnapshot.isEmpty else {
      userMessage = (text: "There are no notes to export.", kind: .info)
      return
    }

    let panel = NSSavePanel()
    panel.title = "Export Full Library"
    panel.nameFieldStringValue = "sceal-library-export.zip"
    panel.allowedContentTypes = [.zip]

    guard panel.runModal() == .OK, let saveURL = panel.url else { return }

    let attachmentsRootURL: URL?
    do {
      attachmentsRootURL = try libraryRepository.attachmentsRootDirectoryURL(
        createIfNeeded: false
      )
    } catch {
      report(error, context: "Preparing full-library export failed")
      return
    }

    isPerformingFileOperation = true
    progressMessage = "Exporting library..."

    let fm = fileManager
    Task.detached { [weak self] in
      do {
        let zipURL = try ScealBackupArchiveExporter.exportBackup(
          dailyNotes: dailyNotesSnapshot,
          listNotes: listNotesSnapshot,
          manifest: manifestSnapshot,
          templates: templatesSnapshot,
          kind: .manual,
          attachmentsRootURL: attachmentsRootURL
        )

        if fm.fileExists(atPath: saveURL.path) {
          try fm.removeItem(at: saveURL)
        }
        try fm.moveItem(at: zipURL, to: saveURL)

        ZipArchiveWriter.cleanUp(zipURL: zipURL)

        await MainActor.run { [weak self] in
          self?.userMessage = (
            text:
              "Exported \(dailyNotesSnapshot.count) daily notes and \(listNotesSnapshot.count) list notes.",
            kind: .info
          )
          self?.isPerformingFileOperation = false
          self?.progressMessage = nil
        }
      } catch {
        await MainActor.run { [weak self] in
          self?.report(error, context: "Exporting full library failed")
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
        templates: result.templates,
        skipped: result.skipped,
        extraDetail: result.failed > 0 ? "\(result.failed) failed to parse" : nil,
        attachmentSourceRootURL: NoteImageAttachmentStore.attachmentRootInArchive(
          rootURL: folderURL
        )
      )
    }
  }

  // Restores a full-library archive after confirmation, replacing current note storage.
  func restoreFullLibraryFromArchive() {
    #if DEBUG
      if isDemoModeEnabled {
        userMessage = (
          text: "Turn off Demo Library before restoring your real library.", kind: .info
        )
        return
      }
    #endif

    guard !isPerformingFileOperation else {
      userMessage = (text: "Wait for the current file operation to finish.", kind: .info)
      return
    }

    guard !isBackupRunning else {
      userMessage = (text: "Wait for the current backup to finish before restoring.", kind: .info)
      return
    }

    guard
      let archiveURL = selectImportFile(
        title: "Select Scéal Library Archive",
        message: "Choose a full-library Scéal backup or library export zip.",
        allowedContentTypes: [.zip]
      )
    else {
      return
    }

    guard confirmLibraryRestore() else {
      return
    }

    flushPendingSaves()

    let storageURLs: ScealLibraryStorageURLs
    let safetyArchiveDirectoryURL: URL
    do {
      storageURLs = try libraryStorageURLs()
      safetyArchiveDirectoryURL = try restoreSafetyArchiveDirectoryURL()
    } catch {
      report(error, context: "Preparing library restore failed")
      return
    }

    let currentDailyNotes = notes
    let currentListNotes = listNotes
    let currentManifest = listNoteManifest
    let currentTemplates = noteTemplates
    let fm = fileManager
    let didStartAccessing = archiveURL.startAccessingSecurityScopedResource()

    isPerformingFileOperation = true
    progressMessage = "Restoring library..."

    Task.detached { [weak self] in
      defer {
        if didStartAccessing {
          archiveURL.stopAccessingSecurityScopedResource()
        }
      }

      do {
        let result = try ScealBackupArchiveImporter.restoreLibrary(
          from: archiveURL,
          currentDailyNotes: currentDailyNotes,
          currentListNotes: currentListNotes,
          currentManifest: currentManifest,
          currentTemplates: currentTemplates,
          destinationURLs: storageURLs,
          safetyArchiveDirectoryURL: safetyArchiveDirectoryURL,
          fileManager: fm
        )

        await MainActor.run { [weak self] in
          guard let self else { return }
          self.notes = result.dailyNotes
          self.listNotes = result.listNotes
          self.listNoteManifest = result.manifest
          self.replaceNoteTemplates(result.templates)
          self.rebuildNoteIndex()
          self.rebuildListNoteIndex()
          self.selectedNoteID = result.dailyNotes.first?.id
          self.selectedListNoteID = result.listNotes.first?.id
          self.searchText = ""
          self.listSearchText = ""

          if self.sidebarMode == .list, result.listNotes.isEmpty {
            self.sidebarMode = .daily
          } else if self.sidebarMode != .list, result.dailyNotes.isEmpty, !result.listNotes.isEmpty
          {
            self.sidebarMode = .list
          }

          self.userMessage = (
            text:
              "Restored \(result.dailyNotes.count) daily notes and \(result.listNotes.count) list notes. Safety backup: \(result.safetyArchiveURL.lastPathComponent).",
            kind: .info
          )
          self.checkAndRunBackupIfDue(trigger: .postImport)
          self.isPerformingFileOperation = false
          self.progressMessage = nil
        }
      } catch {
        await MainActor.run { [weak self] in
          self?.report(error, context: "Restoring library failed")
          self?.isPerformingFileOperation = false
          self?.progressMessage = nil
        }
      }
    }
  }

  // Shared import payload used by folder import flows.
  private struct ImportOutcome: Sendable {
    let imported: [DayNote]
    var templates: [NoteTemplate] = []
    let skipped: Int
    let extraDetail: String?
    var attachmentSourceRootURL: URL? = nil
  }

  // Runs a folder-import flow with shared panel, persistence, and user-message handling.
  private func importFromFolder(
    panelTitle: String,
    panelMessage: String,
    context: String,
    emptyMessage: String,
    importBlock:
      @Sendable @escaping (_ sourceURL: URL, _ existingNoteIDs: Set<DayNote.ID>) throws ->
      ImportOutcome
  ) {
    guard let folderURL = selectImportFolder(title: panelTitle, message: panelMessage) else {
      return
    }

    runImport(
      from: folderURL,
      context: context,
      emptyMessage: emptyMessage,
      importBlock: importBlock
    )
  }

  // Runs a file-import flow with shared panel, persistence, and user-message handling.
  private func importFromFile(
    panelTitle: String,
    panelMessage: String,
    allowedContentTypes: [UTType],
    context: String,
    emptyMessage: String,
    importBlock:
      @Sendable @escaping (_ sourceURL: URL, _ existingNoteIDs: Set<DayNote.ID>) throws ->
      ImportOutcome
  ) {
    guard
      let fileURL = selectImportFile(
        title: panelTitle,
        message: panelMessage,
        allowedContentTypes: allowedContentTypes
      )
    else {
      return
    }

    runImport(
      from: fileURL,
      context: context,
      emptyMessage: emptyMessage,
      importBlock: importBlock
    )
  }

  // Runs shared background import, persistence, and result-message handling.
  private func runImport(
    from sourceURL: URL,
    context: String,
    emptyMessage: String,
    importBlock:
      @Sendable @escaping (_ sourceURL: URL, _ existingNoteIDs: Set<DayNote.ID>) throws ->
      ImportOutcome
  ) {
    let existingIDs = Set(notes.map(\.id))

    // Resolve notes directory on main actor and start background work.
    let notesDir: URL
    let attachmentsDir: URL
    do {
      notesDir = try notesDirectoryURL()
      attachmentsDir = try libraryRepository.attachmentsRootDirectoryURL()
    } catch {
      report(error, context: context)
      return
    }

    isPerformingFileOperation = true
    progressMessage = "Importing…"
    let fm = fileManager

    // Explicitly acquire security-scoped access so the detached task can
    // read the user-selected source inside the App Sandbox.
    let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()

    Task.detached { [weak self] in
      defer {
        if didStartAccessing { sourceURL.stopAccessingSecurityScopedResource() }
      }

      do {
        // Step 1: Parse on a background thread.
        let outcome = try importBlock(sourceURL, existingIDs)

        // If nothing to import, finish early on main.
        if outcome.imported.isEmpty && outcome.templates.isEmpty {
          await MainActor.run { [weak self] in
            self?.showImportMessage(outcome, emptyMessage: emptyMessage)
            self?.isPerformingFileOperation = false
            self?.progressMessage = nil
          }
          return
        }

        // Step 2: Write imported notes to disk off the main thread.
        if !outcome.imported.isEmpty {
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
        }

        if let sourceRootURL = outcome.attachmentSourceRootURL {
          try NoteImageAttachmentStore.copyAttachmentFolders(
            for: Set(outcome.imported.map(\.id)),
            from: sourceRootURL,
            to: attachmentsDir,
            fileManager: fm
          )
        }

        // Step 3: Update in-memory state and notify the user on the main actor.
        await MainActor.run { [weak self] in
          guard let self else { return }
          self.notes = (self.notes + outcome.imported).sorted(by: { $0.date > $1.date })
          self.rebuildNoteIndex()
          self.mergeImportedNoteTemplates(outcome.templates)
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

  // Opens a file picker configured for import flows.
  private func selectImportFile(
    title: String,
    message: String,
    allowedContentTypes: [UTType]
  ) -> URL? {
    let panel = NSOpenPanel()
    panel.title = title
    panel.message = message
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = allowedContentTypes

    guard panel.runModal() == .OK else {
      return nil
    }

    return panel.url
  }

  private func confirmLibraryRestore() -> Bool {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "Restore Scéal Library?"
    alert.informativeText =
      "This replaces all current daily notes, list notes, groups, and attachments with the selected archive. Scéal will write a safety backup before replacing anything."
    alert.addButton(withTitle: "Restore Library")
    alert.addButton(withTitle: "Cancel")
    return alert.runModal() == .alertFirstButtonReturn
  }

  private func libraryStorageURLs() throws -> ScealLibraryStorageURLs {
    try libraryRepository.storageURLs()
  }

  private func restoreSafetyArchiveDirectoryURL() throws -> URL {
    try libraryRepository.restoreSafetyArchiveDirectoryURL()
  }

  // Shows the user-facing import result message with consistent formatting across importers.
  private func showImportMessage(_ outcome: ImportOutcome, emptyMessage: String) {
    if outcome.imported.isEmpty && outcome.templates.isEmpty && outcome.skipped > 0 {
      userMessage = (
        text: "No new notes imported. \(outcome.skipped) dates already exist in Scéal.",
        kind: .info
      )
      return
    }

    guard !outcome.imported.isEmpty || !outcome.templates.isEmpty else {
      userMessage = (text: emptyMessage, kind: .info)
      return
    }

    var details: [String] = []
    if outcome.skipped > 0 { details.append("\(outcome.skipped) skipped") }
    if !outcome.templates.isEmpty { details.append("\(outcome.templates.count) templates") }
    if let extraDetail = outcome.extraDetail { details.append(extraDetail) }

    let suffix = details.isEmpty ? "" : " (\(details.joined(separator: ", ")))"
    if outcome.imported.isEmpty {
      userMessage = (text: "Imported \(outcome.templates.count) templates.", kind: .info)
    } else {
      userMessage = (text: "Imported \(outcome.imported.count) notes.\(suffix)", kind: .info)
    }
    if let firstImportedNoteID = outcome.imported.first?.id {
      selectedNoteID = firstImportedNoteID
    }
  }
}
