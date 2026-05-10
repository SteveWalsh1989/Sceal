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
    let developerBackupURL: URL?

    init(
      dailyNotes: [DayNote],
      listNotes: [DayNote],
      manifest: ListNotesManifest,
      developerBackupURL: URL? = nil
    ) {
      self.dailyNotes = dailyNotes
      self.listNotes = listNotes
      self.manifest = manifest
      self.developerBackupURL = developerBackupURL
    }
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

    // Copies production data into the DEBUG library without mutating the production source.
    static func copyProductionLibraryToDeveloper(
      at developerLocation: ScealLibraryLocation,
      productionLocation: ScealLibraryLocation = .production(),
      fileManager: FileManager = .default
    ) throws -> DeveloperLibrarySeedSnapshot {
      try validateProductionCopy(
        from: productionLocation.rootURL,
        to: developerLocation.rootURL,
        fileManager: fileManager
      )

      let sourceRootURL = productionLocation.rootURL.standardizedFileURL
      let destinationRootURL = developerLocation.rootURL.standardizedFileURL
      let parentURL = destinationRootURL.deletingLastPathComponent()
      try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)

      let timestamp = timestampString()
      let stagingURL = uniqueSiblingURL(
        in: parentURL,
        folderName: "\(ScealLibraryLocation.developerFolderName) Import \(timestamp)",
        fileManager: fileManager
      )
      let backupURL = uniqueSiblingURL(
        in: parentURL,
        folderName: "\(ScealLibraryLocation.developerFolderName) Backup \(timestamp)",
        fileManager: fileManager
      )

      try fileManager.copyItem(at: sourceRootURL, to: stagingURL)

      let existingDeveloperLibraryWasBackedUp: Bool
      if fileManager.fileExists(atPath: destinationRootURL.path) {
        try fileManager.moveItem(at: destinationRootURL, to: backupURL)
        existingDeveloperLibraryWasBackedUp = true
      } else {
        existingDeveloperLibraryWasBackedUp = false
      }

      do {
        try fileManager.moveItem(at: stagingURL, to: destinationRootURL)
      } catch {
        if existingDeveloperLibraryWasBackedUp,
          !fileManager.fileExists(atPath: destinationRootURL.path)
        {
          try? fileManager.moveItem(at: backupURL, to: destinationRootURL)
        }
        throw error
      }

      let repository = LibraryRepository(
        libraryLocation: developerLocation, fileManager: fileManager)
      let dailyNotes = try repository.loadDailyNotes()
      let listSnapshot = try repository.loadListNotes()
      _ = try repository.restoreSafetyArchiveDirectoryURL()

      return DeveloperLibrarySeedSnapshot(
        dailyNotes: dailyNotes,
        listNotes: listSnapshot.notes,
        manifest: listSnapshot.manifest,
        developerBackupURL: existingDeveloperLibraryWasBackedUp ? backupURL : nil
      )
    }

    // Returns whether production can be copied into the active DEBUG library.
    static func canCopyProductionLibraryToDeveloper(
      at developerLocation: ScealLibraryLocation,
      productionLocation: ScealLibraryLocation = .production(),
      fileManager: FileManager = .default
    ) -> Bool {
      (try? validateProductionCopy(
        from: productionLocation.rootURL,
        to: developerLocation.rootURL,
        fileManager: fileManager
      )) != nil
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

    private static func validateProductionCopy(
      from productionRootURL: URL,
      to developerRootURL: URL,
      fileManager: FileManager
    ) throws {
      try validateResetRoot(developerRootURL, fileManager: fileManager)

      let sourceRootURL = productionRootURL.standardizedFileURL
      let destinationRootURL = developerRootURL.standardizedFileURL
      guard sourceRootURL != destinationRootURL else {
        throw DeveloperLibrarySeederError.refusingMatchingSourceAndDestination
      }

      var isDirectory = ObjCBool(false)
      guard fileManager.fileExists(atPath: sourceRootURL.path, isDirectory: &isDirectory),
        isDirectory.boolValue
      else {
        throw DeveloperLibrarySeederError.missingProductionLibrary(sourceRootURL)
      }
    }

    private static func timestampString(date: Date = .now) -> String {
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.dateFormat = "yyyyMMdd-HHmmss"
      return formatter.string(from: date)
    }

    private static func uniqueSiblingURL(
      in parentURL: URL,
      folderName: String,
      fileManager: FileManager
    ) -> URL {
      var candidateURL = parentURL.appendingPathComponent(folderName, isDirectory: true)
      var suffix = 2

      while fileManager.fileExists(atPath: candidateURL.path) {
        candidateURL = parentURL.appendingPathComponent(
          "\(folderName)-\(suffix)",
          isDirectory: true
        )
        suffix += 1
      }

      return candidateURL
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
    case refusingMatchingSourceAndDestination
    case missingProductionLibrary(URL)

    var errorDescription: String? {
      switch self {
      case .refusingProductionLibrary:
        return "Refusing to reset the production Scéal library."
      case .refusingBroadLibraryRoot(let rootURL):
        return "Refusing to reset broad library root: \(rootURL.path)"
      case .refusingMatchingSourceAndDestination:
        return "Refusing to copy a library onto itself."
      case .missingProductionLibrary(let rootURL):
        return "Production Scéal library was not found at \(rootURL.path)."
      }
    }
  }
#endif
