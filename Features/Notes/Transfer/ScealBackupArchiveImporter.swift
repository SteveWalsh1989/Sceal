import Foundation

nonisolated struct ScealLibraryStorageURLs: Sendable {
  let notesDirectoryURL: URL
  let listNotesDirectoryURL: URL
  let attachmentsRootURL: URL
}

// Validates and restores full-library Scéal backup archives.
nonisolated enum ScealBackupArchiveImporter {
  nonisolated private static let metadataFileName = "backup-metadata.json"
  nonisolated private static let dailyNotesFolderName = "Notes"
  nonisolated private static let listNotesFolderName = "ListNotes"
  nonisolated private static let manifestFileName = "groups.json"
  nonisolated private static let supportedBackupFormatVersion = 1

  nonisolated struct RestoreResult: Sendable {
    let dailyNotes: [DayNote]
    let listNotes: [DayNote]
    let manifest: ListNotesManifest
    let metadata: BackupArchiveMetadata
    let safetyArchiveURL: URL
  }

  private struct ValidatedArchive {
    let extractionBaseURL: URL
    let rootURL: URL
    let dailyNotes: [DayNote]
    let listNotes: [DayNote]
    let manifest: ListNotesManifest
    let metadata: BackupArchiveMetadata
    let attachmentRootURL: URL?
  }

  // Restores a validated archive by writing a safety archive first, then replacing live storage.
  nonisolated static func restoreLibrary(
    from archiveURL: URL,
    currentDailyNotes: [DayNote],
    currentListNotes: [DayNote],
    currentManifest: ListNotesManifest,
    destinationURLs: ScealLibraryStorageURLs,
    safetyArchiveDirectoryURL: URL,
    createdAt: Date = .now,
    fileManager: FileManager = .default
  ) throws -> RestoreResult {
    let archive = try validateArchive(at: archiveURL, fileManager: fileManager)
    defer {
      try? fileManager.removeItem(at: archive.extractionBaseURL)
    }

    try fileManager.createDirectory(
      at: safetyArchiveDirectoryURL,
      withIntermediateDirectories: true
    )

    let temporarySafetyArchiveURL = try ScealBackupArchiveExporter.exportBackup(
      dailyNotes: currentDailyNotes,
      listNotes: currentListNotes,
      manifest: currentManifest,
      kind: .manual,
      createdAt: createdAt,
      attachmentsRootURL: destinationURLs.attachmentsRootURL
    )
    defer {
      ZipArchiveWriter.cleanUp(zipURL: temporarySafetyArchiveURL)
    }

    let safetyArchiveURL = safetyArchiveDirectoryURL.appendingPathComponent(
      temporarySafetyArchiveURL.lastPathComponent
    )
    if fileManager.fileExists(atPath: safetyArchiveURL.path) {
      try fileManager.removeItem(at: safetyArchiveURL)
    }
    try fileManager.moveItem(at: temporarySafetyArchiveURL, to: safetyArchiveURL)

    let replacement = try makeReplacementStorageURLs(fileManager: fileManager)
    defer {
      try? fileManager.removeItem(at: replacement.temporaryBaseURL)
    }

    try writeSnapshot(
      dailyNotes: archive.dailyNotes,
      listNotes: archive.listNotes,
      manifest: archive.manifest,
      sourceAttachmentRootURL: archive.attachmentRootURL,
      destinationURLs: replacement.storageURLs,
      fileManager: fileManager
    )
    try replaceLibrary(
      replacementURLs: replacement.storageURLs,
      destinationURLs: destinationURLs,
      fileManager: fileManager
    )

    return RestoreResult(
      dailyNotes: archive.dailyNotes,
      listNotes: archive.listNotes,
      manifest: archive.manifest,
      metadata: archive.metadata,
      safetyArchiveURL: safetyArchiveURL
    )
  }

  private static func validateArchive(
    at archiveURL: URL,
    fileManager: FileManager
  ) throws -> ValidatedArchive {
    let extractionBaseURL = fileManager.temporaryDirectory
      .appendingPathComponent("sceal-restore-\(UUID().uuidString)", isDirectory: true)
    let extractionURL = extractionBaseURL.appendingPathComponent("Archive", isDirectory: true)
    try fileManager.createDirectory(at: extractionURL, withIntermediateDirectories: true)

    do {
      try ZipArchiveWriter.extractZip(from: archiveURL, to: extractionURL)
      let rootURL = try backupRootURL(in: extractionURL, fileManager: fileManager)
      let metadata = try decodeMetadata(in: rootURL)

      guard metadata.backupFormatVersion == supportedBackupFormatVersion else {
        throw ScealBackupArchiveImporterError.unsupportedFormat(
          metadata.backupFormatVersion
        )
      }

      let dailyNotesURL = rootURL.appendingPathComponent(
        dailyNotesFolderName,
        isDirectory: true
      )
      let listNotesURL = rootURL.appendingPathComponent(
        listNotesFolderName,
        isDirectory: true
      )
      let dailyNotes = try decodeMarkdownNotes(
        in: dailyNotesURL,
        usingFileNameID: false,
        fileManager: fileManager
      )
      let listNotes = try decodeMarkdownNotes(
        in: listNotesURL,
        usingFileNameID: true,
        fileManager: fileManager
      )
      let manifest = try decodeManifest(in: listNotesURL)

      try validateUniqueIDs(dailyNotes.map(\.id), context: "daily notes")
      try validateUniqueIDs(listNotes.map(\.id), context: "list notes")
      try validateManifest(manifest, listNoteIDs: Set(listNotes.map(\.id)))
      try validateMetadataCounts(
        metadata,
        dailyNoteCount: dailyNotes.count,
        listNoteCount: listNotes.count
      )

      let attachmentRootURL = NoteImageAttachmentStore.attachmentRootInArchive(
        rootURL: rootURL,
        fileManager: fileManager
      )

      return ValidatedArchive(
        extractionBaseURL: extractionBaseURL,
        rootURL: rootURL,
        dailyNotes: dailyNotes,
        listNotes: listNotes,
        manifest: manifest,
        metadata: metadata,
        attachmentRootURL: attachmentRootURL
      )
    } catch {
      try? fileManager.removeItem(at: extractionBaseURL)
      throw error
    }
  }

  private static func backupRootURL(in extractionURL: URL, fileManager: FileManager) throws -> URL {
    if fileManager.fileExists(
      atPath: extractionURL.appendingPathComponent(metadataFileName).path
    ) {
      return extractionURL
    }

    let managedRootURL = extractionURL.appendingPathComponent(
      ScealBackupArchiveExporter.managedFolderName,
      isDirectory: true
    )
    if fileManager.fileExists(
      atPath: managedRootURL.appendingPathComponent(metadataFileName).path
    ) {
      return managedRootURL
    }

    let contents = try fileManager.contentsOfDirectory(
      at: extractionURL,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    )
    for candidateURL in contents {
      if fileManager.fileExists(
        atPath: candidateURL.appendingPathComponent(metadataFileName).path
      ) {
        return candidateURL
      }
    }

    throw ScealBackupArchiveImporterError.missingMetadata
  }

  private static func decodeMetadata(in rootURL: URL) throws -> BackupArchiveMetadata {
    let metadataURL = rootURL.appendingPathComponent(metadataFileName)
    guard FileManager.default.fileExists(atPath: metadataURL.path) else {
      throw ScealBackupArchiveImporterError.missingMetadata
    }

    do {
      return try JSONDecoder().decode(
        BackupArchiveMetadata.self,
        from: Data(contentsOf: metadataURL)
      )
    } catch {
      throw ScealBackupArchiveImporterError.invalidMetadata(error)
    }
  }

  private static func decodeManifest(in listNotesURL: URL) throws -> ListNotesManifest {
    let manifestURL = listNotesURL.appendingPathComponent(manifestFileName)
    guard FileManager.default.fileExists(atPath: manifestURL.path) else {
      throw ScealBackupArchiveImporterError.missingManifest
    }

    do {
      return try JSONDecoder().decode(
        ListNotesManifest.self,
        from: Data(contentsOf: manifestURL)
      )
    } catch {
      throw ScealBackupArchiveImporterError.invalidManifest(error)
    }
  }

  private static func decodeMarkdownNotes(
    in directoryURL: URL,
    usingFileNameID: Bool,
    fileManager: FileManager
  ) throws -> [DayNote] {
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else {
      throw ScealBackupArchiveImporterError.missingDirectory(directoryURL.lastPathComponent)
    }

    let fileURLs = try fileManager.contentsOfDirectory(
      at: directoryURL,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )
    .filter { $0.pathExtension == "md" }
    .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })

    return
      try fileURLs
      .map { fileURL in
        let fileID = fileURL.deletingPathExtension().lastPathComponent
        do {
          let contents = try String(contentsOf: fileURL, encoding: .utf8)
          let note = try MarkdownNoteCodec.decode(
            contents: contents,
            sourceURL: fileURL,
            idOverride: usingFileNameID ? fileID : nil
          )

          if !usingFileNameID, note.id != fileID {
            throw ScealBackupArchiveImporterError.noteIDMismatch(
              fileNameID: fileID,
              decodedID: note.id
            )
          }

          return note
        } catch let error as ScealBackupArchiveImporterError {
          throw error
        } catch {
          throw ScealBackupArchiveImporterError.corruptNote(fileURL, error)
        }
      }
      .sorted(by: { $0.date > $1.date })
  }

  private static func validateUniqueIDs(_ ids: [DayNote.ID], context: String) throws {
    guard Set(ids).count == ids.count else {
      throw ScealBackupArchiveImporterError.duplicateNoteIDs(context)
    }
  }

  private static func validateManifest(
    _ manifest: ListNotesManifest,
    listNoteIDs: Set<DayNote.ID>
  ) throws {
    guard manifest.allNoteIDs == listNoteIDs else {
      throw ScealBackupArchiveImporterError.manifestMismatch
    }
  }

  private static func validateMetadataCounts(
    _ metadata: BackupArchiveMetadata,
    dailyNoteCount: Int,
    listNoteCount: Int
  ) throws {
    guard metadata.dailyNoteCount == dailyNoteCount,
      metadata.listNoteCount == listNoteCount,
      metadata.includesManifest
    else {
      throw ScealBackupArchiveImporterError.metadataMismatch
    }
  }

  private static func makeReplacementStorageURLs(fileManager: FileManager) throws -> (
    temporaryBaseURL: URL, storageURLs: ScealLibraryStorageURLs
  ) {
    let temporaryBaseURL = fileManager.temporaryDirectory
      .appendingPathComponent("sceal-replacement-\(UUID().uuidString)", isDirectory: true)
    let rootURL = temporaryBaseURL.appendingPathComponent("Sceal", isDirectory: true)
    try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)

    return (
      temporaryBaseURL,
      ScealLibraryStorageURLs(
        notesDirectoryURL: rootURL.appendingPathComponent(dailyNotesFolderName, isDirectory: true),
        listNotesDirectoryURL: rootURL.appendingPathComponent(
          listNotesFolderName,
          isDirectory: true
        ),
        attachmentsRootURL: rootURL.appendingPathComponent(
          NoteImageAttachmentStore.attachmentsFolderName,
          isDirectory: true
        )
      )
    )
  }

  private static func writeSnapshot(
    dailyNotes: [DayNote],
    listNotes: [DayNote],
    manifest: ListNotesManifest,
    sourceAttachmentRootURL: URL?,
    destinationURLs: ScealLibraryStorageURLs,
    fileManager: FileManager
  ) throws {
    try fileManager.createDirectory(
      at: destinationURLs.notesDirectoryURL,
      withIntermediateDirectories: true
    )
    try fileManager.createDirectory(
      at: destinationURLs.listNotesDirectoryURL,
      withIntermediateDirectories: true
    )
    try fileManager.createDirectory(
      at: destinationURLs.attachmentsRootURL,
      withIntermediateDirectories: true
    )

    for note in dailyNotes {
      let fileURL = destinationURLs.notesDirectoryURL.appendingPathComponent(note.fileName)
      let contents = try MarkdownNoteCodec.encode(note)
      try contents.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    for note in listNotes {
      let fileURL = destinationURLs.listNotesDirectoryURL.appendingPathComponent(note.fileName)
      let contents = try MarkdownNoteCodec.encode(note)
      try contents.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let manifestURL = destinationURLs.listNotesDirectoryURL.appendingPathComponent(
      manifestFileName
    )
    try encoder.encode(manifest).write(to: manifestURL, options: .atomic)

    guard let sourceAttachmentRootURL else { return }

    try NoteImageAttachmentStore.copyAttachmentFolders(
      for: Set((dailyNotes + listNotes).map(\.id)),
      from: sourceAttachmentRootURL,
      to: destinationURLs.attachmentsRootURL,
      fileManager: fileManager
    )
  }

  private static func replaceLibrary(
    replacementURLs: ScealLibraryStorageURLs,
    destinationURLs: ScealLibraryStorageURLs,
    fileManager: FileManager
  ) throws {
    let rollbackBaseURL = fileManager.temporaryDirectory
      .appendingPathComponent("sceal-restore-rollback-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: rollbackBaseURL, withIntermediateDirectories: true)

    let items = [
      (
        name: dailyNotesFolderName,
        replacementURL: replacementURLs.notesDirectoryURL,
        destinationURL: destinationURLs.notesDirectoryURL
      ),
      (
        name: listNotesFolderName,
        replacementURL: replacementURLs.listNotesDirectoryURL,
        destinationURL: destinationURLs.listNotesDirectoryURL
      ),
      (
        name: NoteImageAttachmentStore.attachmentsFolderName,
        replacementURL: replacementURLs.attachmentsRootURL,
        destinationURL: destinationURLs.attachmentsRootURL
      ),
    ]
    var movedOriginals: [(originalURL: URL, rollbackURL: URL)] = []

    do {
      for item in items {
        try fileManager.createDirectory(
          at: item.destinationURL.deletingLastPathComponent(),
          withIntermediateDirectories: true
        )

        guard fileManager.fileExists(atPath: item.destinationURL.path) else {
          continue
        }

        let rollbackURL = rollbackBaseURL.appendingPathComponent(
          item.name,
          isDirectory: true
        )
        try fileManager.moveItem(at: item.destinationURL, to: rollbackURL)
        movedOriginals.append((item.destinationURL, rollbackURL))
      }

      for item in items {
        try fileManager.moveItem(at: item.replacementURL, to: item.destinationURL)
      }

      try? fileManager.removeItem(at: rollbackBaseURL)
    } catch {
      for item in items where fileManager.fileExists(atPath: item.destinationURL.path) {
        try? fileManager.removeItem(at: item.destinationURL)
      }

      for original in movedOriginals.reversed() {
        if fileManager.fileExists(atPath: original.rollbackURL.path) {
          try? fileManager.moveItem(at: original.rollbackURL, to: original.originalURL)
        }
      }

      try? fileManager.removeItem(at: rollbackBaseURL)
      throw error
    }
  }
}

enum ScealBackupArchiveImporterError: LocalizedError {
  case missingMetadata
  case invalidMetadata(Error)
  case unsupportedFormat(Int)
  case missingDirectory(String)
  case missingManifest
  case invalidManifest(Error)
  case corruptNote(URL, Error)
  case noteIDMismatch(fileNameID: String, decodedID: String)
  case duplicateNoteIDs(String)
  case manifestMismatch
  case metadataMismatch

  var errorDescription: String? {
    switch self {
    case .missingMetadata:
      return "The archive is missing backup metadata."
    case .invalidMetadata(let error):
      return "The archive metadata is invalid. \(error.localizedDescription)"
    case .unsupportedFormat(let version):
      return "The archive uses unsupported backup format version \(version)."
    case .missingDirectory(let name):
      return "The archive is missing the \(name) folder."
    case .missingManifest:
      return "The archive is missing the list-note groups manifest."
    case .invalidManifest(let error):
      return "The list-note groups manifest is invalid. \(error.localizedDescription)"
    case .corruptNote(let url, let error):
      return "The note file \(url.lastPathComponent) is invalid. \(error.localizedDescription)"
    case .noteIDMismatch(let fileNameID, let decodedID):
      return "The note file \(fileNameID).md decodes as \(decodedID)."
    case .duplicateNoteIDs(let context):
      return "The archive contains duplicate \(context)."
    case .manifestMismatch:
      return "The list-note groups manifest does not match the archive's list notes."
    case .metadataMismatch:
      return "The archive metadata does not match the archive contents."
    }
  }
}
