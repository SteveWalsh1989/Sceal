import CryptoKit
import Darwin
import Foundation

// The journal is published only after immutable before/after copies are durable on the library disk.
nonisolated struct LibraryInstallTransaction {
  enum Phase: String, Codable { case installing, configuration, committed }

  struct Configuration: Codable {
    let settings: ScealArchiveSettings?
    let templates: [NoteTemplate]
  }

  struct Folder: Codable {
    let name: String
    let original: [String: String]?
    let replacement: [String: String]
  }

  struct Record: Codable {
    let version: Int
    let id: UUID
    var phase: Phase
    let folders: [Folder]
    let configuration: Configuration
    let recoveryID: UUID?
  }

  private struct RecoveryHold: Codable {
    let id: UUID
    let preservedLibrary: String
  }

  let rootURL: URL
  private(set) var record: Record
  private let fileManager: FileManager
  private static let allowedFolders = ["StructuredNotes", "StructuredListNotes", "Attachments"]

  var workspaceURL: URL {
    rootURL.appendingPathComponent(".sceal-install-\(record.id.uuidString)", isDirectory: true)
  }

  // A fixed, library-local journal is checked before any note loading or creation.
  static func journalURL(in rootURL: URL) -> URL {
    rootURL.appendingPathComponent(".sceal-install.json")
  }

  // Missing is distinct from malformed: damaged recovery metadata must block editing.
  static func read(at rootURL: URL, fileManager: FileManager = .default, recoveryID: UUID? = nil)
    throws -> Self?
  {
    let holdURL = recoveryHoldURL(in: rootURL)
    let hold =
      fileManager.fileExists(atPath: holdURL.path)
      ? try JSONDecoder().decode(RecoveryHold.self, from: Data(contentsOf: holdURL)) : nil
    let data: Data
    do { data = try Data(contentsOf: journalURL(in: rootURL)) } catch CocoaError.fileReadNoSuchFile
    {
      if let hold, hold.id != recoveryID {
        throw LibraryInstallTransactionError.pendingRecovery
      }
      if fileManager.fileExists(atPath: rootURL.path),
        try fileManager.contentsOfDirectory(atPath: rootURL.path).contains(where: {
          $0.hasPrefix(".sceal-structured-rollback-")
        })
      {
        throw LibraryInstallTransactionError.untrackedRecovery
      }
      return nil
    }
    let record = try JSONDecoder().decode(Record.self, from: data)
    // An older journal must never finish a newly requested recovery restore.
    if let hold, hold.id != record.recoveryID {
      throw LibraryInstallTransactionError.pendingRecovery
    }
    let names = record.folders.map(\.name)
    guard record.version == 1, Set(names).count == names.count,
      Set(names).isSubset(of: Set(allowedFolders)),
      names.contains("StructuredNotes"), names.contains("StructuredListNotes")
    else { throw LibraryInstallTransactionError.invalidJournal }
    try record.configuration.settings?.validate()
    return Self(rootURL: rootURL, record: record, fileManager: fileManager)
  }

  // Preparation cannot modify live folders and cannot replace another unfinished operation.
  static func prepare(
    at rootURL: URL, replacements: [String: URL], configuration: Configuration,
    fileManager: FileManager = .default, recoveryID: UUID? = nil
  ) throws -> Self {
    guard try read(at: rootURL, fileManager: fileManager, recoveryID: recoveryID) == nil else {
      throw LibraryInstallTransactionError.pendingRecovery
    }
    guard Set(replacements.keys).isSubset(of: Set(allowedFolders)),
      replacements["StructuredNotes"] != nil, replacements["StructuredListNotes"] != nil
    else { throw LibraryInstallTransactionError.invalidJournal }
    let id = UUID()
    let workspace = rootURL.appendingPathComponent(
      ".sceal-install-\(id.uuidString)", isDirectory: true)
    var published = false
    defer { if !published { try? fileManager.removeItem(at: workspace) } }
    var folders: [Folder] = []
    for name in allowedFolders where replacements[name] != nil {
      let destination = rootURL.appendingPathComponent(name, isDirectory: true)
      let original: [String: String]?
      if fileManager.fileExists(atPath: destination.path) {
        let files = try LibraryArchiveFiles.read(from: destination, fileManager: fileManager)
        original = fingerprint(files)
        try files.write(
          to: workspace.appendingPathComponent("Original/\(name)"), fileManager: fileManager)
      } else {
        original = nil
      }
      guard let source = replacements[name] else {
        throw LibraryInstallTransactionError.invalidJournal
      }
      guard try source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
        throw LibraryInstallTransactionError.invalidJournal
      }
      let files = try LibraryArchiveFiles.read(from: source, fileManager: fileManager)
      try files.write(
        to: workspace.appendingPathComponent("Replacement/\(name)"), fileManager: fileManager)
      folders.append(Folder(name: name, original: original, replacement: fingerprint(files)))
    }
    let transaction = Self(
      rootURL: rootURL,
      record: Record(
        version: 1, id: id, phase: .installing, folders: folders, configuration: configuration,
        recoveryID: recoveryID),
      fileManager: fileManager
    )
    try synchronizeTree(workspace, fileManager: fileManager)
    published = true
    try transaction.writeRecord()
    return transaction
  }

  // Each installation step is independently restartable from the untouched recovery copies.
  func installFolder(named name: String) throws {
    guard record.phase == .installing,
      let folder = record.folders.first(where: { $0.name == name })
    else { throw LibraryInstallTransactionError.invalidJournal }
    let source = workspaceURL.appendingPathComponent("Replacement/\(name)")
    try verify(source, expected: folder.replacement)
    try replaceDirectory(named: name, from: source)
  }

  // Settings are applied only after both semantic validation and exact byte validation succeed.
  mutating func markAwaitingConfiguration() throws {
    try validateInstalled()
    record.phase = .configuration
    try writeRecord()
  }

  // Recovery must reject missing or altered installed files instead of committing a partial library.
  func validateInstalled() throws {
    for folder in record.folders {
      try verify(rootURL.appendingPathComponent(folder.name), expected: folder.replacement)
    }
  }

  // Keep original copies until rollback is fully verified; another interruption can repeat it safely.
  func rollback() throws {
    guard record.phase == .installing else { throw LibraryInstallTransactionError.pendingRecovery }
    for folder in record.folders {
      if let original = folder.original {
        try verify(
          workspaceURL.appendingPathComponent("Original/\(folder.name)"), expected: original)
      }
    }
    for folder in record.folders {
      let destination = rootURL.appendingPathComponent(folder.name)
      if let original = folder.original {
        try replaceDirectory(
          named: folder.name, from: workspaceURL.appendingPathComponent("Original/\(folder.name)"))
        try verify(destination, expected: original)
      } else if fileManager.fileExists(atPath: destination.path) {
        try fileManager.removeItem(at: destination)
      }
    }
    try discard()
  }

  // Commit after portable settings, templates, mode, and completion record have been persisted.
  mutating func finish() throws {
    let completionURL = rootURL.appendingPathComponent("structured-library.json")
    let handle = try FileHandle(forWritingTo: completionURL)
    defer { try? handle.close() }
    try handle.synchronize()
    record.phase = .committed
    try writeRecord()
    try discard()
  }

  // Retain a blocking record across recovery-restore preparation and any subsequent rollback.
  static func recoveryHoldURL(in rootURL: URL) -> URL {
    rootURL.appendingPathComponent(".sceal-recovery-restore.json")
  }

  static func holdForRecovery(at rootURL: URL, preservedCopyURL: URL) throws -> UUID {
    let url = recoveryHoldURL(in: rootURL)
    let id = UUID()
    try synchronizeTree(preservedCopyURL, fileManager: .default)
    try JSONEncoder().encode(RecoveryHold(id: id, preservedLibrary: preservedCopyURL.path)).write(
      to: url, options: .atomic)
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.synchronize()
    try synchronizeDirectory(rootURL)
    return id
  }

  // Removing the journal first makes leftover workspace cleanup harmless after completion.
  func discard() throws {
    if record.phase == .committed, record.recoveryID != nil {
      let holdURL = Self.recoveryHoldURL(in: rootURL)
      if fileManager.fileExists(atPath: holdURL.path) { try fileManager.removeItem(at: holdURL) }
    }
    try fileManager.removeItem(at: Self.journalURL(in: rootURL))
    try Self.synchronizeDirectory(rootURL)
    try? fileManager.removeItem(at: workspaceURL)
  }

  // Copy to a sibling first so the live destination is absent only across a bounded rename window.
  private func replaceDirectory(named name: String, from source: URL) throws {
    let temporary = workspaceURL.appendingPathComponent("Installing-\(name)")
    if fileManager.fileExists(atPath: temporary.path) { try fileManager.removeItem(at: temporary) }
    try fileManager.copyItem(at: source, to: temporary)
    try Self.synchronizeTree(temporary, fileManager: fileManager)
    let destination = rootURL.appendingPathComponent(name)
    if fileManager.fileExists(atPath: destination.path) {
      try fileManager.removeItem(at: destination)
    }
    try fileManager.moveItem(at: temporary, to: destination)
    try Self.synchronizeDirectory(rootURL)
  }

  // Digests keep the journal small while comparing every file, including recovery-only attachments.
  private static func fingerprint(_ files: LibraryArchiveFiles) -> [String: String] {
    files.files.mapValues { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() }
  }

  private func verify(_ directory: URL, expected: [String: String]) throws {
    guard try directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true,
      Self.fingerprint(try LibraryArchiveFiles.read(from: directory, fileManager: fileManager))
        == expected
    else { throw LibraryInstallTransactionError.changedFiles(directory) }
  }

  // Atomic replacement plus synchronization prevents a torn journal from authorizing file changes.
  private func writeRecord() throws {
    let url = Self.journalURL(in: rootURL)
    try JSONEncoder().encode(record).write(to: url, options: .atomic)
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.synchronize()
    try Self.synchronizeDirectory(rootURL)
  }

  private static func synchronizeTree(_ directory: URL, fileManager: FileManager) throws {
    for url in try fileManager.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: [.isDirectoryKey])
    {
      if try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
        try synchronizeTree(url, fileManager: fileManager)
      } else {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.synchronize()
      }
    }
    try synchronizeDirectory(directory)
  }

  private static func synchronizeDirectory(_ directory: URL) throws {
    let descriptor = open(directory.path, O_RDONLY)
    guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    defer { close(descriptor) }
    guard fsync(descriptor) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
  }
}

nonisolated enum LibraryInstallTransactionError: LocalizedError {
  case invalidJournal
  case pendingRecovery
  case changedFiles(URL)
  case untrackedRecovery

  var errorDescription: String? {
    switch self {
    case .invalidJournal:
      return
        "The library recovery record is invalid or unsupported. No recovery files were removed."
    case .pendingRecovery:
      return
        "An unfinished library installation must be recovered before editing or starting another operation."
    case .changedFiles(let url):
      return
        "Library recovery validation failed at \(url.path). Recovery copies and safety archives were retained."
    case .untrackedRecovery:
      return
        "An older interrupted conversion left rollback files without a recovery record. Restore a known safety archive before editing; the rollback files have been preserved."
    }
  }
}
