import Foundation

// Writes a full standalone backup archive containing daily notes, list notes, and metadata.
nonisolated enum ScealBackupArchiveExporter {
  nonisolated static let managedFolderName = "Sceal Backup"
  nonisolated private static let metadataFileName = "backup-metadata.json"
  nonisolated private static let dailyNotesFolderName = "Notes"
  nonisolated private static let listNotesFolderName = "ListNotes"
  nonisolated private static let structuredDailyNotesFolderName = "StructuredNotes"
  nonisolated private static let structuredListNotesFolderName = "StructuredListNotes"
  nonisolated private static let manifestFileName = "groups.json"
  nonisolated private static let settingsFileName = "settings.json"
  nonisolated private static let legacyMetadataVersion = 1
  nonisolated private static let structuredMetadataVersion = 2

  // Creates a backup zip in a temporary directory and returns the archive URL.
  nonisolated static func exportBackup(
    dailyNotes: [DayNote],
    listNotes: [DayNote],
    manifest: ListNotesManifest,
    templates: [NoteTemplate] = [],
    structuredDailyNotes: [StructuredNoteDocument] = [],
    structuredListNotes: [StructuredNoteDocument] = [],
    structuredListManifest: ListNotesManifest? = nil,
    settings: ScealArchiveSettings? = nil,
    authority: ScealArchiveAuthority = .legacy,
    legacySourceFiles: LegacyArchiveSourceFiles? = nil,
    kind: BackupArchiveKind,
    createdAt: Date = .now,
    attachmentsRootURL: URL? = nil
  ) throws -> URL {
    let isStructuredArchive =
      authority == .structured || settings != nil || structuredListManifest != nil
      || !structuredDailyNotes.isEmpty
      || !structuredListNotes.isEmpty
    if isStructuredArchive {
      guard let settings else {
        throw ScealBackupArchiveExporterError.missingStructuredSettings
      }
      try settings.validate()
      try validateStructuredArchive(
        dailyDocuments: structuredDailyNotes,
        listDocuments: structuredListNotes,
        listManifest: structuredListManifest ?? .empty
      )
    }

    let temporaryDirectories = try ZipArchiveWriter.makeTemporaryStagingDirectory(
      prefix: "sceal-backup",
      rootFolderName: managedFolderName
    )
    let stagingDirectoryURL = temporaryDirectories.stagingDirectoryURL
    let dailyNotesDirectoryURL = stagingDirectoryURL.appendingPathComponent(
      dailyNotesFolderName,
      isDirectory: true
    )
    let listNotesDirectoryURL = stagingDirectoryURL.appendingPathComponent(
      listNotesFolderName,
      isDirectory: true
    )

    try FileManager.default.createDirectory(
      at: dailyNotesDirectoryURL, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: listNotesDirectoryURL, withIntermediateDirectories: true)

    if legacySourceFiles == nil {
      for note in dailyNotes {
        let fileURL = dailyNotesDirectoryURL.appendingPathComponent(note.fileName)
        let contents = try MarkdownNoteCodec.encode(note)
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
      }

      for note in listNotes {
        let fileURL = listNotesDirectoryURL.appendingPathComponent(note.fileName)
        let contents = try MarkdownNoteCodec.encode(note)
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
      }
    }

    let manifestURL = listNotesDirectoryURL.appendingPathComponent(manifestFileName)
    let metadataURL = stagingDirectoryURL.appendingPathComponent(metadataFileName)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
    if let legacySourceFiles {
      try legacySourceFiles.daily.write(to: dailyNotesDirectoryURL)
      try legacySourceFiles.list.write(to: listNotesDirectoryURL)
    }
    try NoteTemplateArchive.write(templates, to: stagingDirectoryURL)

    if isStructuredArchive {
      let structuredDailyDirectoryURL = stagingDirectoryURL.appendingPathComponent(
        structuredDailyNotesFolderName,
        isDirectory: true
      )
      let structuredListDirectoryURL = stagingDirectoryURL.appendingPathComponent(
        structuredListNotesFolderName,
        isDirectory: true
      )
      try writeStructuredNotes(structuredDailyNotes, to: structuredDailyDirectoryURL)
      try writeStructuredNotes(structuredListNotes, to: structuredListDirectoryURL)
      try encoder.encode(structuredListManifest ?? .empty).write(
        to: structuredListDirectoryURL.appendingPathComponent(manifestFileName),
        options: .atomic
      )
      if let settings {
        try encoder.encode(settings).write(
          to: stagingDirectoryURL.appendingPathComponent(settingsFileName),
          options: .atomic
        )
      }
    }

    if let attachmentsRootURL {
      let targetAttachmentRootURL = stagingDirectoryURL.appendingPathComponent(
        NoteImageAttachmentStore.attachmentsFolderName,
        isDirectory: true
      )
      // Recovery attachments may outlive active notes and must remain in full backups.
      try LibraryArchiveFiles.read(from: attachmentsRootURL).write(to: targetAttachmentRootURL)
    }

    let metadata = BackupArchiveMetadata(
      appVersion: appVersionDescription(),
      backupFormatVersion: isStructuredArchive
        ? structuredMetadataVersion : legacyMetadataVersion,
      backupKind: kind,
      createdAt: createdAt,
      sourceStoreDescription: "~/Library/Application Support/Sceal",
      dailyNoteCount: legacySourceFiles?.daily.markdownFileCount ?? dailyNotes.count,
      listNoteCount: legacySourceFiles?.list.markdownFileCount ?? listNotes.count,
      templateCount: templates.count,
      includesManifest: true,
      structuredDailyNoteCount: structuredDailyNotes.count,
      structuredListNoteCount: structuredListNotes.count,
      includesStructuredManifest: isStructuredArchive,
      includesSettings: settings != nil,
      structuredStorageIsAuthoritative: isStructuredArchive ? authority == .structured : nil
    )
    try encoder.encode(metadata).write(to: metadataURL, options: .atomic)

    let archiveFileName = archiveFileName(for: kind, date: createdAt)
    let zipURL = temporaryDirectories.temporaryBaseURL.appendingPathComponent(archiveFileName)
    try ZipArchiveWriter.createZip(from: stagingDirectoryURL, to: zipURL)
    try? FileManager.default.removeItem(at: stagingDirectoryURL)
    return zipURL
  }

  // Returns the managed backup directory inside the user-selected parent folder.
  nonisolated static func managedBackupDirectoryURL(in selectedFolderURL: URL) -> URL {
    selectedFolderURL.appendingPathComponent(managedFolderName, isDirectory: true)
  }

  // Produces a stable archive name so automatic backups can be pruned safely.
  nonisolated static func archiveFileName(for kind: BackupArchiveKind, date: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
    let prefix = kind == .manual ? "sceal-backup-manual" : "sceal-backup-auto"
    return "\(prefix)-\(formatter.string(from: date)).zip"
  }

  nonisolated private static func appVersionDescription() -> String {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    return version ?? "unknown"
  }

  // Writes validated structured documents using their canonical stable-ID filenames.
  nonisolated private static func writeStructuredNotes(
    _ documents: [StructuredNoteDocument],
    to directoryURL: URL
  ) throws {
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    for document in documents {
      try document.validate()
      let fileURL =
        directoryURL
        .appendingPathComponent(document.id)
        .appendingPathExtension(StructuredNoteRepository.fileExtension)
      try StructuredNoteDocumentCodec.write(document, to: fileURL)
    }
  }

  // Rejects duplicate, unsafe, or mismatched structured entries before staging archive files.
  nonisolated private static func validateStructuredArchive(
    dailyDocuments: [StructuredNoteDocument],
    listDocuments: [StructuredNoteDocument],
    listManifest: ListNotesManifest
  ) throws {
    let dailyIDs = dailyDocuments.map(\.id)
    let listIDs = listDocuments.map(\.id)
    guard Set(dailyIDs).count == dailyIDs.count,
      Set(listIDs).count == listIDs.count
    else {
      throw ScealBackupArchiveExporterError.duplicateStructuredNoteID
    }
    guard listManifest.allNoteIDs == Set(listIDs) else {
      throw ScealBackupArchiveExporterError.structuredManifestMismatch
    }
    let orderedListIDs = listManifest.ungroupedNoteIDs + listManifest.groups.flatMap(\.noteIDs)
    guard orderedListIDs.count == Set(orderedListIDs).count,
      Set(listManifest.groups.map(\.id)).count == listManifest.groups.count
    else {
      throw ScealBackupArchiveExporterError.structuredManifestMismatch
    }

    for document in dailyDocuments + listDocuments {
      try document.validate()
      guard !document.id.isEmpty,
        !document.id.contains("/"),
        !document.id.contains(":"),
        document.id != ".",
        document.id != ".."
      else {
        throw ScealBackupArchiveExporterError.unsafeStructuredNoteID(document.id)
      }
    }
    for document in dailyDocuments {
      let expectedID = NoteDateFormatters.storageDate.string(from: document.date)
      guard document.id == expectedID else {
        throw ScealBackupArchiveExporterError.invalidDailyStructuredNoteID(document.id)
      }
    }
  }
}

nonisolated enum ScealBackupArchiveExporterError: LocalizedError, Equatable, Sendable {
  case duplicateStructuredNoteID
  case missingStructuredSettings
  case structuredManifestMismatch
  case unsafeStructuredNoteID(String)
  case invalidDailyStructuredNoteID(String)

  var errorDescription: String? {
    switch self {
    case .duplicateStructuredNoteID:
      return "The structured archive contains duplicate note IDs."
    case .missingStructuredSettings:
      return "A version 2 archive must include portable settings."
    case .structuredManifestMismatch:
      return "The structured list-note manifest does not match its documents."
    case .unsafeStructuredNoteID(let noteID):
      return "Structured note ID \(noteID) is unsafe for archive storage."
    case .invalidDailyStructuredNoteID(let noteID):
      return "Structured daily note \(noteID) does not use its date-based storage ID."
    }
  }
}

nonisolated struct BackupArchiveMetadata: Codable, Equatable, Sendable {
  let appVersion: String
  let backupFormatVersion: Int
  let backupKind: BackupArchiveKind
  let createdAt: Date
  let sourceStoreDescription: String
  let dailyNoteCount: Int
  let listNoteCount: Int
  let templateCount: Int
  let includesManifest: Bool
  let structuredDailyNoteCount: Int
  let structuredListNoteCount: Int
  let includesStructuredManifest: Bool
  let includesSettings: Bool
  let structuredStorageIsAuthoritative: Bool?

  init(
    appVersion: String,
    backupFormatVersion: Int,
    backupKind: BackupArchiveKind,
    createdAt: Date,
    sourceStoreDescription: String,
    dailyNoteCount: Int,
    listNoteCount: Int,
    templateCount: Int = 0,
    includesManifest: Bool,
    structuredDailyNoteCount: Int = 0,
    structuredListNoteCount: Int = 0,
    includesStructuredManifest: Bool = false,
    includesSettings: Bool = false,
    structuredStorageIsAuthoritative: Bool? = nil
  ) {
    self.appVersion = appVersion
    self.backupFormatVersion = backupFormatVersion
    self.backupKind = backupKind
    self.createdAt = createdAt
    self.sourceStoreDescription = sourceStoreDescription
    self.dailyNoteCount = dailyNoteCount
    self.listNoteCount = listNoteCount
    self.templateCount = templateCount
    self.includesManifest = includesManifest
    self.structuredDailyNoteCount = structuredDailyNoteCount
    self.structuredListNoteCount = structuredListNoteCount
    self.includesStructuredManifest = includesStructuredManifest
    self.includesSettings = includesSettings
    self.structuredStorageIsAuthoritative = structuredStorageIsAuthoritative
  }

  private enum CodingKeys: String, CodingKey {
    case appVersion
    case backupFormatVersion
    case backupKind
    case createdAt
    case sourceStoreDescription
    case dailyNoteCount
    case listNoteCount
    case templateCount
    case includesManifest
    case structuredDailyNoteCount
    case structuredListNoteCount
    case includesStructuredManifest
    case includesSettings
    case structuredStorageIsAuthoritative
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      appVersion: try container.decode(String.self, forKey: .appVersion),
      backupFormatVersion: try container.decode(Int.self, forKey: .backupFormatVersion),
      backupKind: try container.decode(BackupArchiveKind.self, forKey: .backupKind),
      createdAt: try container.decode(Date.self, forKey: .createdAt),
      sourceStoreDescription: try container.decode(String.self, forKey: .sourceStoreDescription),
      dailyNoteCount: try container.decode(Int.self, forKey: .dailyNoteCount),
      listNoteCount: try container.decode(Int.self, forKey: .listNoteCount),
      templateCount: try container.decodeIfPresent(Int.self, forKey: .templateCount) ?? 0,
      includesManifest: try container.decode(Bool.self, forKey: .includesManifest),
      structuredDailyNoteCount: try container.decodeIfPresent(
        Int.self,
        forKey: .structuredDailyNoteCount
      ) ?? 0,
      structuredListNoteCount: try container.decodeIfPresent(
        Int.self,
        forKey: .structuredListNoteCount
      ) ?? 0,
      includesStructuredManifest: try container.decodeIfPresent(
        Bool.self,
        forKey: .includesStructuredManifest
      ) ?? false,
      includesSettings: try container.decodeIfPresent(Bool.self, forKey: .includesSettings)
        ?? false,
      structuredStorageIsAuthoritative:
        try container.decodeIfPresent(Bool.self, forKey: .structuredStorageIsAuthoritative)
    )
  }
}
