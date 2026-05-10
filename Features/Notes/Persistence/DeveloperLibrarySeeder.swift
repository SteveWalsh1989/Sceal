//
//  DeveloperLibrarySeeder.swift
//

// DEBUG-only file-backed seed data for safe persistence and archive testing.

#if DEBUG
  import Foundation

  struct DeveloperLibrarySeedSnapshot: Sendable {
    let dailyNotes: [DayNote]
    let listNotes: [DayNote]
    let manifest: ListNotesManifest
  }

  enum DeveloperLibrarySeeder {
    private static let listNoteID = "developer-library-checklist"
    private static let attachmentFileName = "developer-attachment.png"

    // Replaces a non-production library root with deterministic file-backed developer data.
    static func resetLibrary(
      at location: ScealLibraryLocation,
      fileManager: FileManager = .default,
      calendar: Calendar = .current,
      referenceDate: Date = .now
    ) throws -> DeveloperLibrarySeedSnapshot {
      try validateResetRoot(location.rootURL, fileManager: fileManager)

      if fileManager.fileExists(atPath: location.rootURL.path) {
        try fileManager.removeItem(at: location.rootURL)
      }

      let repository = LibraryRepository(libraryLocation: location, fileManager: fileManager)
      let dailyNotes = DayNote.demoModeNotes(relativeTo: referenceDate, calendar: calendar)
      let listNote = makeListNote(referenceDate: referenceDate, calendar: calendar)
      let manifest = ListNotesManifest(
        ungroupedNoteIDs: [],
        groups: [NoteGroup(name: "Developer QA", noteIDs: [listNote.id])]
      )

      for note in dailyNotes {
        try repository.saveDailyNote(note)
      }
      try repository.saveListNote(listNote)
      try repository.saveListNotesManifest(manifest)
      try writeAttachment(for: listNote.id, repository: repository, fileManager: fileManager)
      _ = try repository.restoreSafetyArchiveDirectoryURL()

      return DeveloperLibrarySeedSnapshot(
        dailyNotes: dailyNotes,
        listNotes: [listNote],
        manifest: manifest
      )
    }

    // Returns whether reset is allowed without touching the production app-support library.
    static func canResetLibrary(
      at rootURL: URL,
      fileManager: FileManager = .default
    ) -> Bool {
      (try? validateResetRoot(rootURL, fileManager: fileManager)) != nil
    }

    // Refuses roots that could target production or broad user directories.
    static func validateResetRoot(_ rootURL: URL, fileManager: FileManager = .default) throws {
      let targetURL = rootURL.standardizedFileURL
      let productionURL = ScealLibraryLocation.production(fileManager: fileManager)
        .rootURL
        .standardizedFileURL
      let homeURL = fileManager.homeDirectoryForCurrentUser.standardizedFileURL
      let applicationSupportURL = productionURL.deletingLastPathComponent().standardizedFileURL

      guard targetURL != productionURL else {
        throw DeveloperLibrarySeederError.refusingProductionLibrary
      }
      guard targetURL != homeURL, targetURL != applicationSupportURL else {
        throw DeveloperLibrarySeederError.refusingBroadLibraryRoot(targetURL)
      }
      guard targetURL.pathComponents.count >= 3 else {
        throw DeveloperLibrarySeederError.refusingBroadLibraryRoot(targetURL)
      }
    }

    private static func makeListNote(referenceDate: Date, calendar: Calendar) -> DayNote {
      let date = calendar.startOfDay(for: referenceDate)
      return DayNote(
        date: date,
        id: listNoteID,
        title: "Developer Library Checklist",
        tags: ["developer", "fixture"],
        body: """
          # Developer Library Checklist

          - Verify file-backed persistence
          - Test import, export, backup, and restore flows
          - Switch Free/Paid gates in Developer settings

          ![Developer attachment](../Attachments/\(listNoteID)/\(attachmentFileName))
          """
      )
    }

    private static func writeAttachment(
      for noteID: DayNote.ID,
      repository: LibraryRepository,
      fileManager: FileManager
    ) throws {
      let attachmentsRootURL = try repository.attachmentsRootDirectoryURL()
      let noteAttachmentDirectoryURL = attachmentsRootURL.appendingPathComponent(
        noteID,
        isDirectory: true
      )
      try fileManager.createDirectory(
        at: noteAttachmentDirectoryURL,
        withIntermediateDirectories: true
      )
      try Data("developer fixture attachment".utf8).write(
        to: noteAttachmentDirectoryURL.appendingPathComponent(attachmentFileName)
      )
    }
  }

  enum DeveloperLibrarySeederError: LocalizedError, Equatable {
    case refusingProductionLibrary
    case refusingBroadLibraryRoot(URL)

    var errorDescription: String? {
      switch self {
      case .refusingProductionLibrary:
        return "Refusing to reset the production Scéal library."
      case .refusingBroadLibraryRoot(let rootURL):
        return "Refusing to reset broad library root: \(rootURL.path)"
      }
    }
  }
#endif
