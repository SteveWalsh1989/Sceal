import Foundation

// Writes a full standalone backup archive containing daily notes, list notes, and metadata.
enum ScealBackupArchiveExporter {
  static let managedFolderName = "Sceal Backup"
  private static let metadataFileName = "backup-metadata.json"
  private static let dailyNotesFolderName = "Notes"
  private static let listNotesFolderName = "ListNotes"
  private static let manifestFileName = "groups.json"
  private static let metadataVersion = 1

  // Creates a backup zip in a temporary directory and returns the archive URL.
  nonisolated static func exportBackup(
    dailyNotes: [DayNote],
    listNotes: [DayNote],
    manifest: ListNotesManifest,
    kind: BackupArchiveKind,
    createdAt: Date = .now
  ) throws -> URL {
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

    let manifestURL = listNotesDirectoryURL.appendingPathComponent(manifestFileName)
    let metadataURL = stagingDirectoryURL.appendingPathComponent(metadataFileName)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(manifest).write(to: manifestURL, options: .atomic)

    let metadata = BackupArchiveMetadata(
      appVersion: appVersionDescription(),
      backupFormatVersion: metadataVersion,
      backupKind: kind,
      createdAt: createdAt,
      sourceStoreDescription: "~/Library/Application Support/Sceal",
      dailyNoteCount: dailyNotes.count,
      listNoteCount: listNotes.count,
      includesManifest: true
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
}

struct BackupArchiveMetadata: Codable, Equatable, Sendable {
  let appVersion: String
  let backupFormatVersion: Int
  let backupKind: BackupArchiveKind
  let createdAt: Date
  let sourceStoreDescription: String
  let dailyNoteCount: Int
  let listNoteCount: Int
  let includesManifest: Bool
}
