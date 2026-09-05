import Foundation

nonisolated struct ScealLibraryStorageURLs: Sendable {
  let notesDirectoryURL: URL
  let listNotesDirectoryURL: URL
  let structuredNotesDirectoryURL: URL
  let structuredListNotesDirectoryURL: URL
  let attachmentsRootURL: URL

  init(
    notesDirectoryURL: URL,
    listNotesDirectoryURL: URL,
    structuredNotesDirectoryURL: URL? = nil,
    structuredListNotesDirectoryURL: URL? = nil,
    attachmentsRootURL: URL
  ) {
    let rootURL = notesDirectoryURL.deletingLastPathComponent()
    self.notesDirectoryURL = notesDirectoryURL
    self.listNotesDirectoryURL = listNotesDirectoryURL
    self.structuredNotesDirectoryURL =
      structuredNotesDirectoryURL
      ?? rootURL.appendingPathComponent("StructuredNotes", isDirectory: true)
    self.structuredListNotesDirectoryURL =
      structuredListNotesDirectoryURL
      ?? rootURL.appendingPathComponent("StructuredListNotes", isDirectory: true)
    self.attachmentsRootURL = attachmentsRootURL
  }
}

// Validates and restores full-library Scéal backup archives.
nonisolated enum ScealBackupArchiveImporter {
  nonisolated private static let metadataFileName = "backup-metadata.json"
  nonisolated private static let dailyNotesFolderName = "Notes"
  nonisolated private static let listNotesFolderName = "ListNotes"
  nonisolated private static let structuredDailyNotesFolderName = "StructuredNotes"
  nonisolated private static let structuredListNotesFolderName = "StructuredListNotes"
  nonisolated private static let manifestFileName = "groups.json"
  nonisolated private static let settingsFileName = "settings.json"
  nonisolated private static let supportedBackupFormatVersions = 1...2

  nonisolated struct RestoreResult: Sendable {
    let dailyNotes: [DayNote]
    let listNotes: [DayNote]
    let manifest: ListNotesManifest
    let structuredDailyNotes: [StructuredNoteDocument]
    let structuredListNotes: [StructuredNoteDocument]
    let structuredListManifest: ListNotesManifest
    let templates: [NoteTemplate]
    let settings: ScealArchiveSettings?
    let metadata: BackupArchiveMetadata
    let safetyArchiveURL: URL
    let retainedArchiveURL: URL
  }

  private struct ValidatedArchive {
    let extractionBaseURL: URL
    let rootURL: URL
    let dailyNotes: [DayNote]
    let listNotes: [DayNote]
    let manifest: ListNotesManifest
    let structuredDailyNotes: [StructuredNoteDocument]
    let structuredListNotes: [StructuredNoteDocument]
    let structuredListManifest: ListNotesManifest
    let templates: [NoteTemplate]
    let settings: ScealArchiveSettings?
    let metadata: BackupArchiveMetadata
    let attachmentRootURL: URL?
  }

  private struct ResolvedStructuredContent {
    let dailyNotes: [StructuredNoteDocument]
    let listNotes: [StructuredNoteDocument]
    let listManifest: ListNotesManifest
  }

  // Restores a validated archive by writing a safety archive first, then replacing live storage.
  nonisolated static func restoreLibrary(
    from archiveURL: URL,
    currentDailyNotes: [DayNote],
    currentListNotes: [DayNote],
    currentManifest: ListNotesManifest,
    currentTemplates: [NoteTemplate] = [],
    currentStructuredDailyNotes: [StructuredNoteDocument] = [],
    currentStructuredListNotes: [StructuredNoteDocument] = [],
    currentStructuredListManifest: ListNotesManifest = .empty,
    currentSettings: ScealArchiveSettings? = nil,
    currentAuthority: ScealArchiveAuthority = .legacy,
    currentLegacySourceFiles: LegacyArchiveSourceFiles? = nil,
    destinationURLs: ScealLibraryStorageURLs,
    safetyArchiveDirectoryURL: URL,
    createdAt: Date = .now,
    fileManager: FileManager = .default
  ) throws -> RestoreResult {
    let archive = try validateArchive(at: archiveURL, fileManager: fileManager)
    defer {
      try? fileManager.removeItem(at: archive.extractionBaseURL)
    }
    let structuredContent = try resolveStructuredContent(in: archive)
    let restoredSettings = archive.settings?.normalizedForStructuredRuntime()
    let originalSources = try LegacyArchiveSourceFiles.read(
      dailyURL: destinationURLs.notesDirectoryURL, listURL: destinationURLs.listNotesDirectoryURL,
      fileManager: fileManager
    )
    if let currentLegacySourceFiles, currentLegacySourceFiles != originalSources {
      throw LibraryArchiveFilesError.sourceChanged
    }
    let originalAttachments = try LibraryArchiveFiles.read(
      from: destinationURLs.attachmentsRootURL, fileManager: fileManager
    )
    var restoredAttachments = originalAttachments
    if let attachmentRootURL = archive.attachmentRootURL {
      let incomingAttachments = try LibraryArchiveFiles.read(
        from: attachmentRootURL, fileManager: fileManager)
      // Archive bytes must win conflicts so restored notes display their original images.
      restoredAttachments.files.merge(incomingAttachments.files) { _, incoming in incoming }
    }

    try fileManager.createDirectory(
      at: safetyArchiveDirectoryURL,
      withIntermediateDirectories: true
    )

    let temporarySafetyArchiveURL = try ScealBackupArchiveExporter.exportBackup(
      dailyNotes: currentDailyNotes,
      listNotes: currentListNotes,
      manifest: currentManifest,
      templates: currentTemplates,
      structuredDailyNotes: currentStructuredDailyNotes,
      structuredListNotes: currentStructuredListNotes,
      structuredListManifest: currentSettings == nil
        && currentStructuredDailyNotes.isEmpty
        && currentStructuredListNotes.isEmpty
        ? nil : currentStructuredListManifest,
      settings: currentSettings,
      authority: currentAuthority,
      legacySourceFiles: originalSources,
      kind: .manual,
      createdAt: createdAt,
      attachmentsRootURL: destinationURLs.attachmentsRootURL
    )
    defer {
      ZipArchiveWriter.cleanUp(zipURL: temporarySafetyArchiveURL)
    }

    var safetyArchiveURL = safetyArchiveDirectoryURL.appendingPathComponent(
      temporarySafetyArchiveURL.lastPathComponent
    )
    if fileManager.fileExists(atPath: safetyArchiveURL.path) {
      safetyArchiveURL = safetyArchiveDirectoryURL.appendingPathComponent(
        "\(temporarySafetyArchiveURL.deletingPathExtension().lastPathComponent)-\(UUID().uuidString).zip"
      )
    }
    try fileManager.moveItem(at: temporarySafetyArchiveURL, to: safetyArchiveURL)
    guard
      try LibraryArchiveFiles.read(
        from: destinationURLs.attachmentsRootURL, fileManager: fileManager)
        == originalAttachments
    else { throw LibraryArchiveFilesError.sourceChanged }

    // Retain incoming recovery sources without installing them over the user's original Markdown.
    let retainedArchiveURL = safetyArchiveDirectoryURL.appendingPathComponent(
      "restored-source-\(UUID().uuidString).zip"
    )
    try fileManager.copyItem(at: archiveURL, to: retainedArchiveURL)

    let replacement = try makeReplacementStorageURLs(fileManager: fileManager)
    defer {
      try? fileManager.removeItem(at: replacement.temporaryBaseURL)
    }

    try writeSnapshot(
      structuredDailyNotes: structuredContent.dailyNotes,
      structuredListNotes: structuredContent.listNotes,
      structuredListManifest: structuredContent.listManifest,
      attachments: restoredAttachments,
      destinationURLs: replacement.storageURLs,
      fileManager: fileManager
    )
    try validateReplacementStorage(
      replacement.storageURLs,
      expectedDailyNotes: structuredContent.dailyNotes,
      expectedListNotes: structuredContent.listNotes,
      expectedListManifest: structuredContent.listManifest,
      expectedAttachments: restoredAttachments,
      fileManager: fileManager
    )
    try replaceLibrary(
      replacementURLs: replacement.storageURLs,
      destinationURLs: destinationURLs,
      originalSources: originalSources,
      expectedAttachments: restoredAttachments,
      expectedStructuredDailyNotes: structuredContent.dailyNotes,
      expectedStructuredListNotes: structuredContent.listNotes,
      expectedStructuredListManifest: structuredContent.listManifest,
      fileManager: fileManager
    )

    return RestoreResult(
      dailyNotes: currentDailyNotes,
      listNotes: currentListNotes,
      manifest: currentManifest,
      structuredDailyNotes: structuredContent.dailyNotes,
      structuredListNotes: structuredContent.listNotes,
      structuredListManifest: structuredContent.listManifest,
      templates: archive.templates,
      settings: restoredSettings,
      metadata: archive.metadata,
      safetyArchiveURL: safetyArchiveURL,
      retainedArchiveURL: retainedArchiveURL
    )
  }

  // Treats authoritative structured snapshots as exact and fills incomplete historical archives.
  private static func resolveStructuredContent(
    in archive: ValidatedArchive
  ) throws -> ResolvedStructuredContent {
    if archive.metadata.backupFormatVersion >= 2,
      archive.metadata.structuredStorageIsAuthoritative == true
    {
      return ResolvedStructuredContent(
        dailyNotes: archive.structuredDailyNotes,
        listNotes: archive.structuredListNotes,
        listManifest: archive.structuredListManifest
      )
    }
    if archive.metadata.backupFormatVersion == 1
      || archive.metadata.structuredStorageIsAuthoritative == false
    {
      return try resolveLegacyAuthoritativeContent(in: archive)
    }

    // Archives written before the authority marker preserve every exact structured copy.
    var dailyDocumentsByID = Dictionary(
      uniqueKeysWithValues: archive.structuredDailyNotes.map { ($0.id, $0) }
    )
    for note in archive.dailyNotes where dailyDocumentsByID[note.id] == nil {
      dailyDocumentsByID[note.id] = try LegacyMarkdownStructuredNoteAdapter.importDocument(note)
    }

    var listDocumentsByID = Dictionary(
      uniqueKeysWithValues: archive.structuredListNotes.map { ($0.id, $0) }
    )
    let missingListNoteIDs = Set(archive.listNotes.map(\.id)).subtracting(listDocumentsByID.keys)
    for note in archive.listNotes where listDocumentsByID[note.id] == nil {
      listDocumentsByID[note.id] = try LegacyMarkdownStructuredNoteAdapter.importDocument(note)
    }

    var listManifest = archive.structuredListManifest
    appendMissingListNotes(
      missingListNoteIDs,
      from: archive.manifest,
      to: &listManifest
    )
    try validateManifest(listManifest, listNoteIDs: Set(listDocumentsByID.keys))

    return ResolvedStructuredContent(
      dailyNotes: dailyDocumentsByID.values.sorted(by: { $0.date > $1.date }),
      listNotes: listDocumentsByID.values.sorted(by: { $0.date > $1.date }),
      listManifest: listManifest
    )
  }

  // Converts every active legacy note while retaining structured-only recovery entries.
  private static func resolveLegacyAuthoritativeContent(
    in archive: ValidatedArchive
  ) throws -> ResolvedStructuredContent {
    var dailyDocumentsByID = Dictionary(
      uniqueKeysWithValues: try archive.dailyNotes.map {
        let document = try LegacyMarkdownStructuredNoteAdapter.importDocument($0)
        return (document.id, document)
      }
    )
    for document in archive.structuredDailyNotes where dailyDocumentsByID[document.id] == nil {
      dailyDocumentsByID[document.id] = document
    }

    var listDocumentsByID = Dictionary(
      uniqueKeysWithValues: try archive.listNotes.map {
        let document = try LegacyMarkdownStructuredNoteAdapter.importDocument($0)
        return (document.id, document)
      }
    )
    let structuredOnlyListNoteIDs = Set(archive.structuredListNotes.map(\.id)).subtracting(
      listDocumentsByID.keys
    )
    for document in archive.structuredListNotes where listDocumentsByID[document.id] == nil {
      listDocumentsByID[document.id] = document
    }

    var listManifest = archive.manifest
    appendMissingListNotes(
      structuredOnlyListNoteIDs,
      from: archive.structuredListManifest,
      to: &listManifest
    )
    try validateManifest(listManifest, listNoteIDs: Set(listDocumentsByID.keys))

    return ResolvedStructuredContent(
      dailyNotes: dailyDocumentsByID.values.sorted(by: { $0.date > $1.date }),
      listNotes: listDocumentsByID.values.sorted(by: { $0.date > $1.date }),
      listManifest: listManifest
    )
  }

  // Preserves existing structured grouping while placing only converted legacy list notes.
  private static func appendMissingListNotes(
    _ missingNoteIDs: Set<String>,
    from source: ListNotesManifest,
    to destination: inout ListNotesManifest
  ) {
    for noteID in source.ungroupedNoteIDs where missingNoteIDs.contains(noteID) {
      destination.ungroupedNoteIDs.append(noteID)
    }
    for sourceGroup in source.groups {
      let noteIDs = sourceGroup.noteIDs.filter(missingNoteIDs.contains)
      guard !noteIDs.isEmpty else { continue }

      if let groupIndex = destination.groups.firstIndex(where: { $0.id == sourceGroup.id }) {
        destination.groups[groupIndex].noteIDs.append(contentsOf: noteIDs)
      } else {
        var group = sourceGroup
        group.noteIDs = noteIDs
        destination.groups.append(group)
      }
    }
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

      guard supportedBackupFormatVersions.contains(metadata.backupFormatVersion) else {
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
      let rawSources = try LegacyArchiveSourceFiles.read(
        dailyURL: dailyNotesURL, listURL: listNotesURL, fileManager: fileManager
      )
      let structuredIsAuthoritative =
        metadata.backupFormatVersion >= 2
        && metadata.structuredStorageIsAuthoritative == true
      let dailyNotes =
        structuredIsAuthoritative
        ? []
        : try decodeMarkdownNotes(
          in: dailyNotesURL,
          usingFileNameID: false,
          fileManager: fileManager
        )
      let listNotes =
        structuredIsAuthoritative
        ? []
        : try decodeMarkdownNotes(
          in: listNotesURL,
          usingFileNameID: true,
          fileManager: fileManager
        )
      let manifest = structuredIsAuthoritative ? .empty : try decodeManifest(in: listNotesURL)
      let templates = try NoteTemplateArchive.read(from: rootURL)
      let structuredDailyNotes: [StructuredNoteDocument]
      let structuredListNotes: [StructuredNoteDocument]
      let structuredListManifest: ListNotesManifest
      let settings: ScealArchiveSettings?
      if metadata.backupFormatVersion >= 2 {
        let structuredDailyURL = rootURL.appendingPathComponent(
          structuredDailyNotesFolderName,
          isDirectory: true
        )
        let structuredListURL = rootURL.appendingPathComponent(
          structuredListNotesFolderName,
          isDirectory: true
        )
        structuredDailyNotes = try decodeStructuredNotes(
          in: structuredDailyURL,
          kind: .daily,
          fileManager: fileManager
        )
        structuredListNotes = try decodeStructuredNotes(
          in: structuredListURL,
          kind: .list,
          fileManager: fileManager
        )
        structuredListManifest = try decodeManifest(in: structuredListURL)
        settings = try decodeSettings(in: rootURL)
      } else {
        structuredDailyNotes = []
        structuredListNotes = []
        structuredListManifest = .empty
        settings = nil
      }

      try validateUniqueIDs(dailyNotes.map(\.id), context: "daily notes")
      try validateUniqueIDs(listNotes.map(\.id), context: "list notes")
      try validateManifest(manifest, listNoteIDs: Set(listNotes.map(\.id)))
      try validateUniqueIDs(
        structuredDailyNotes.map(\.id),
        context: "structured daily notes"
      )
      try validateUniqueIDs(
        structuredListNotes.map(\.id),
        context: "structured list notes"
      )
      try validateManifest(
        structuredListManifest,
        listNoteIDs: Set(structuredListNotes.map(\.id))
      )
      try validateMetadataCounts(
        metadata,
        dailyNoteCount: rawSources.daily.markdownFileCount,
        listNoteCount: rawSources.list.markdownFileCount,
        templateCount: templates.count,
        structuredDailyNoteCount: structuredDailyNotes.count,
        structuredListNoteCount: structuredListNotes.count,
        hasSettings: settings != nil
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
        structuredDailyNotes: structuredDailyNotes,
        structuredListNotes: structuredListNotes,
        structuredListManifest: structuredListManifest,
        templates: templates,
        settings: settings,
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

  // Decodes portable settings only when metadata declares that the archive contains them.
  private static func decodeSettings(in rootURL: URL) throws -> ScealArchiveSettings {
    let settingsURL = rootURL.appendingPathComponent(settingsFileName)
    guard FileManager.default.fileExists(atPath: settingsURL.path) else {
      throw ScealBackupArchiveImporterError.missingSettings
    }
    do {
      let settings = try JSONDecoder().decode(
        ScealArchiveSettings.self,
        from: Data(contentsOf: settingsURL)
      )
      try settings.validate()
      return settings
    } catch {
      throw ScealBackupArchiveImporterError.invalidSettings(error)
    }
  }

  // Reads exact structured documents and validates canonical filenames before replacement.
  private static func decodeStructuredNotes(
    in directoryURL: URL,
    kind: StructuredNoteRepositoryKind,
    fileManager: FileManager
  ) throws -> [StructuredNoteDocument] {
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else {
      throw ScealBackupArchiveImporterError.missingDirectory(directoryURL.lastPathComponent)
    }

    return try fileManager.contentsOfDirectory(
      at: directoryURL,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )
    .filter { $0.pathExtension == StructuredNoteRepository.fileExtension }
    .map { fileURL in
      do {
        let document = try StructuredNoteDocumentCodec.read(from: fileURL)
        try document.validate()
        guard !document.id.isEmpty,
          !document.id.contains("/"),
          !document.id.contains(":"),
          document.id != ".",
          document.id != ".."
        else {
          throw ScealBackupArchiveImporterError.unsafeStructuredNoteID(document.id)
        }
        guard fileURL.deletingPathExtension().lastPathComponent == document.id else {
          throw ScealBackupArchiveImporterError.noteIDMismatch(
            fileNameID: fileURL.deletingPathExtension().lastPathComponent,
            decodedID: document.id
          )
        }
        if kind == .daily {
          let expectedID = NoteDateFormatters.storageDate.string(from: document.date)
          guard document.id == expectedID else {
            throw ScealBackupArchiveImporterError.noteIDMismatch(
              fileNameID: expectedID,
              decodedID: document.id
            )
          }
        }
        return document
      } catch let error as ScealBackupArchiveImporterError {
        throw error
      } catch {
        throw ScealBackupArchiveImporterError.corruptNote(fileURL, error)
      }
    }
    .sorted(by: { $0.date > $1.date })
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
    let orderedNoteIDs = manifest.ungroupedNoteIDs + manifest.groups.flatMap(\.noteIDs)
    guard manifest.allNoteIDs == listNoteIDs,
      orderedNoteIDs.count == Set(orderedNoteIDs).count,
      Set(manifest.groups.map(\.id)).count == manifest.groups.count
    else {
      throw ScealBackupArchiveImporterError.manifestMismatch
    }
  }

  private static func validateMetadataCounts(
    _ metadata: BackupArchiveMetadata,
    dailyNoteCount: Int,
    listNoteCount: Int,
    templateCount: Int,
    structuredDailyNoteCount: Int,
    structuredListNoteCount: Int,
    hasSettings: Bool
  ) throws {
    guard metadata.dailyNoteCount == dailyNoteCount,
      metadata.listNoteCount == listNoteCount,
      metadata.templateCount == templateCount,
      metadata.includesManifest,
      metadata.structuredDailyNoteCount == structuredDailyNoteCount,
      metadata.structuredListNoteCount == structuredListNoteCount,
      metadata.includesStructuredManifest == (metadata.backupFormatVersion >= 2),
      metadata.includesSettings == hasSettings
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
    structuredDailyNotes: [StructuredNoteDocument],
    structuredListNotes: [StructuredNoteDocument],
    structuredListManifest: ListNotesManifest,
    attachments: LibraryArchiveFiles,
    destinationURLs: ScealLibraryStorageURLs,
    fileManager: FileManager
  ) throws {
    try fileManager.createDirectory(
      at: destinationURLs.attachmentsRootURL,
      withIntermediateDirectories: true
    )
    try fileManager.createDirectory(
      at: destinationURLs.structuredNotesDirectoryURL,
      withIntermediateDirectories: true
    )
    try fileManager.createDirectory(
      at: destinationURLs.structuredListNotesDirectoryURL,
      withIntermediateDirectories: true
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    for document in structuredDailyNotes {
      try StructuredNoteDocumentCodec.write(
        document,
        to: destinationURLs.structuredNotesDirectoryURL
          .appendingPathComponent(document.id)
          .appendingPathExtension(StructuredNoteRepository.fileExtension)
      )
    }

    for document in structuredListNotes {
      try StructuredNoteDocumentCodec.write(
        document,
        to: destinationURLs.structuredListNotesDirectoryURL
          .appendingPathComponent(document.id)
          .appendingPathExtension(StructuredNoteRepository.fileExtension)
      )
    }
    try encoder.encode(structuredListManifest).write(
      to: destinationURLs.structuredListNotesDirectoryURL.appendingPathComponent(
        manifestFileName
      ),
      options: .atomic
    )

    try attachments.write(to: destinationURLs.attachmentsRootURL, fileManager: fileManager)
  }

  // Reloads the staged structured replacement before any live folder can be moved.
  private static func validateReplacementStorage(
    _ storageURLs: ScealLibraryStorageURLs,
    expectedDailyNotes: [StructuredNoteDocument],
    expectedListNotes: [StructuredNoteDocument],
    expectedListManifest: ListNotesManifest,
    expectedAttachments: LibraryArchiveFiles,
    fileManager: FileManager
  ) throws {
    let dailyRepository = StructuredNoteRepository(
      storageDirectoryURL: storageURLs.structuredNotesDirectoryURL,
      legacyNotesDirectoryURL: storageURLs.notesDirectoryURL,
      fileManager: fileManager,
      kind: .daily
    )
    let listRepository = StructuredNoteRepository(
      storageDirectoryURL: storageURLs.structuredListNotesDirectoryURL,
      legacyNotesDirectoryURL: storageURLs.listNotesDirectoryURL,
      fileManager: fileManager,
      kind: .list
    )
    let dailyNotes = try dailyRepository.loadDocuments()
    let listNotes = try listRepository.loadDocuments()
    let manifestData = try Data(
      contentsOf: storageURLs.structuredListNotesDirectoryURL.appendingPathComponent(
        manifestFileName
      )
    )
    let listManifest = try JSONDecoder().decode(ListNotesManifest.self, from: manifestData)
    guard dailyNotes == expectedDailyNotes.sorted(by: { $0.date > $1.date }),
      listNotes == expectedListNotes.sorted(by: { $0.date > $1.date }),
      listManifest == expectedListManifest,
      try LibraryArchiveFiles.read(from: storageURLs.attachmentsRootURL, fileManager: fileManager)
        == expectedAttachments
    else {
      throw ScealBackupArchiveImporterError.replacementValidationFailed
    }
  }

  private static func replaceLibrary(
    replacementURLs: ScealLibraryStorageURLs,
    destinationURLs: ScealLibraryStorageURLs,
    originalSources: LegacyArchiveSourceFiles,
    expectedAttachments: LibraryArchiveFiles,
    expectedStructuredDailyNotes: [StructuredNoteDocument],
    expectedStructuredListNotes: [StructuredNoteDocument],
    expectedStructuredListManifest: ListNotesManifest,
    fileManager: FileManager
  ) throws {
    guard
      try LegacyArchiveSourceFiles.read(
        dailyURL: destinationURLs.notesDirectoryURL, listURL: destinationURLs.listNotesDirectoryURL,
        fileManager: fileManager
      ) == originalSources
    else { throw LibraryArchiveFilesError.sourceChanged }
    let rollbackBaseURL = fileManager.temporaryDirectory
      .appendingPathComponent("sceal-restore-rollback-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: rollbackBaseURL, withIntermediateDirectories: true)

    var items = [
      (
        name: NoteImageAttachmentStore.attachmentsFolderName,
        replacementURL: replacementURLs.attachmentsRootURL,
        destinationURL: destinationURLs.attachmentsRootURL
      )
    ]
    items.append(
      (
        name: structuredDailyNotesFolderName,
        replacementURL: replacementURLs.structuredNotesDirectoryURL,
        destinationURL: destinationURLs.structuredNotesDirectoryURL
      )
    )
    items.append(
      (
        name: structuredListNotesFolderName,
        replacementURL: replacementURLs.structuredListNotesDirectoryURL,
        destinationURL: destinationURLs.structuredListNotesDirectoryURL
      )
    )
    var movedOriginals: [(originalURL: URL, rollbackURL: URL)] = []
    var installedURLs: [URL] = []

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
        installedURLs.append(item.destinationURL)
      }

      try validateReplacementStorage(
        destinationURLs,
        expectedDailyNotes: expectedStructuredDailyNotes,
        expectedListNotes: expectedStructuredListNotes,
        expectedListManifest: expectedStructuredListManifest,
        expectedAttachments: expectedAttachments,
        fileManager: fileManager
      )
      guard
        try LegacyArchiveSourceFiles.read(
          dailyURL: destinationURLs.notesDirectoryURL,
          listURL: destinationURLs.listNotesDirectoryURL,
          fileManager: fileManager
        ) == originalSources
      else { throw LibraryArchiveFilesError.sourceChanged }
      try? fileManager.removeItem(at: rollbackBaseURL)
    } catch {
      let replacementError = error
      do {
        for installedURL in installedURLs.reversed() {
          try fileManager.removeItem(at: installedURL)
        }

        for original in movedOriginals.reversed() {
          if fileManager.fileExists(atPath: original.rollbackURL.path) {
            try fileManager.moveItem(at: original.rollbackURL, to: original.originalURL)
          }
        }

        try fileManager.removeItem(at: rollbackBaseURL)
      } catch {
        throw ScealBackupArchiveImporterError.rollbackFailed(error.localizedDescription)
      }
      throw replacementError
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
  case invalidSettings(Error)
  case missingSettings
  case corruptNote(URL, Error)
  case noteIDMismatch(fileNameID: String, decodedID: String)
  case duplicateNoteIDs(String)
  case manifestMismatch
  case unsafeStructuredNoteID(String)
  case metadataMismatch
  case replacementValidationFailed
  case rollbackFailed(String)

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
    case .invalidSettings(let error):
      return "The archive settings are invalid. \(error.localizedDescription)"
    case .missingSettings:
      return "The version 2 archive is missing portable settings."
    case .corruptNote(let url, let error):
      return "The note file \(url.lastPathComponent) is invalid. \(error.localizedDescription)"
    case .noteIDMismatch(let fileNameID, let decodedID):
      return "The note file \(fileNameID).md decodes as \(decodedID)."
    case .duplicateNoteIDs(let context):
      return "The archive contains duplicate \(context)."
    case .manifestMismatch:
      return "The list-note groups manifest does not match the archive's list notes."
    case .unsafeStructuredNoteID(let noteID):
      return "Structured note ID \(noteID) is unsafe for archive storage."
    case .metadataMismatch:
      return "The archive metadata does not match the archive contents."
    case .replacementValidationFailed:
      return "The staged structured library did not reload exactly before restore."
    case .rollbackFailed(let reason):
      return "Restoring the previous library after a failed replacement also failed. \(reason)"
    }
  }
}
