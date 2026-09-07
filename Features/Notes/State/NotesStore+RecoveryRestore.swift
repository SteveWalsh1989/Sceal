import AppKit
import Foundation
import UniformTypeIdentifiers

extension NotesStore {
  // Recovery can preserve damaged files even when normal backup snapshot validation cannot pass.
  func restoreLibraryFromRecoveryScreen() {
    guard !hasLoaded, !isPerformingFileOperation, !isBackupRunning else { return }
    let panel = NSOpenPanel()
    panel.title = "Select a Scéal backup to recover"
    panel.allowedContentTypes = [.zip]
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let archiveURL = panel.url else { return }
    let confirmation = NSAlert()
    confirmation.alertStyle = .warning
    confirmation.messageText = "Recover from this backup?"
    confirmation.informativeText =
      "Scéal will validate the archive and preserve a complete copy of the current library before replacing structured notes. Original Markdown stays untouched. Existing recovery records are retained with the preserved copy."
    confirmation.addButton(withTitle: "Recover Library")
    confirmation.addButton(withTitle: "Cancel")
    guard confirmation.runModal() == .alertFirstButtonReturn else { return }
    let location = libraryLocation
    let manager = fileManager
    let settings: ScealArchiveSettings
    do { settings = try makeArchiveSettings() } catch {
      report(error, context: "Preserving current recovery settings failed")
      return
    }
    let templates = noteTemplates
    isPerformingFileOperation = true
    progressMessage = "Validating backup and preserving recovery files..."
    Task { [weak self] in
      do {
        let preserved = try await Task.detached {
          let accessed = archiveURL.startAccessingSecurityScopedResource()
          defer { if accessed { archiveURL.stopAccessingSecurityScopedResource() } }
          return try LibraryRecoveryRestore.perform(
            from: archiveURL, at: location, settings: settings, templates: templates,
            fileManager: manager)
        }.value
        guard let self else { return }
        try self.recoverPendingLibraryInstallation()
        self.isPerformingFileOperation = false
        self.progressMessage = nil
        self.prepareStructuredCutoverForProductionLaunch()
        self.userMessage = (
          text: "Library recovered. Previous files are preserved at \(preserved.path).", kind: .info
        )
      } catch {
        guard let self else { return }
        self.isPerformingFileOperation = false
        self.progressMessage = nil
        self.isLibraryRecoveryBlocked = true
        self.structuredNotesCutoverFailureDescription = error.localizedDescription
        self.setStructuredCutoverStatus(.recoveryRequired)
        self.report(error, context: "Recovering from backup failed")
      }
    }
  }
}
