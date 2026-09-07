import Foundation

// A damaged library cannot supply a parsed safety snapshot; preserve its entire tree before replacing it.
nonisolated enum LibraryRecoveryRestore {
  static func perform(
    from archiveURL: URL, at location: ScealLibraryLocation, settings: ScealArchiveSettings,
    templates: [NoteTemplate], fileManager: FileManager = .default
  ) throws -> URL {
    let stagingRoot = fileManager.temporaryDirectory.appendingPathComponent(
      "sceal-recovery-validation-\(UUID().uuidString)")
    defer { try? fileManager.removeItem(at: stagingRoot) }
    let staging = ScealLibraryLocation.test(rootURL: stagingRoot)
    // Invalid archives fail before creating a hold or touching the existing library.
    let restored = try ScealBackupArchiveImporter.restoreLibrary(
      from: archiveURL, currentDailyNotes: [], currentListNotes: [], currentManifest: .empty,
      destinationURLs: LibraryRepository(libraryLocation: staging, fileManager: fileManager)
        .storageURLs(),
      safetyArchiveDirectoryURL: staging.restoreSafetyArchiveDirectoryURL(fileManager: fileManager),
      fileManager: fileManager
    )
    let original = try LibraryArchiveFiles.read(from: location.rootURL, fileManager: fileManager)
    let preserved = location.rootURL.deletingLastPathComponent().appendingPathComponent(
      "\(location.rootURL.lastPathComponent) Recovery \(UUID().uuidString)")
    try original.write(to: preserved, fileManager: fileManager)
    guard try LibraryArchiveFiles.read(from: preserved, fileManager: fileManager) == original,
      try LibraryArchiveFiles.read(from: location.rootURL, fileManager: fileManager) == original
    else { throw LibraryArchiveFilesError.sourceChanged }
    try fileManager.createDirectory(at: location.rootURL, withIntermediateDirectories: true)
    try fileManager.copyItem(
      at: archiveURL,
      to: preserved.appendingPathComponent("Selected Archive \(UUID().uuidString).zip"))
    try JSONEncoder().encode(settings).write(
      to: preserved.appendingPathComponent("Recovery Settings \(UUID().uuidString).json"),
      options: .atomic)
    try JSONEncoder().encode(templates).write(
      to: preserved.appendingPathComponent("Recovery Templates \(UUID().uuidString).json"),
      options: .atomic)
    let recoveryID = try LibraryInstallTransaction.holdForRecovery(
      at: location.rootURL, preservedCopyURL: preserved)
    let quarantined = preserved.appendingPathComponent(
      "Retired Recovery Records \(UUID().uuidString)")
    try fileManager.createDirectory(at: quarantined, withIntermediateDirectories: true)
    for name in try fileManager.contentsOfDirectory(atPath: location.rootURL.path)
    where name == LibraryInstallTransaction.journalURL(in: location.rootURL).lastPathComponent
      || name == location.structuredLibraryStateURL.lastPathComponent
      || name.hasPrefix(".sceal-structured-rollback-")
    {
      try fileManager.moveItem(
        at: location.rootURL.appendingPathComponent(name),
        to: quarantined.appendingPathComponent(name))
    }
    let attachmentURL = location.rootURL.appendingPathComponent("Attachments")
    var attachments = try LibraryArchiveFiles.read(from: attachmentURL, fileManager: fileManager)
    let stagedAttachmentsURL = stagingRoot.appendingPathComponent("Attachments")
    let incoming = try LibraryArchiveFiles.read(
      from: stagedAttachmentsURL, fileManager: fileManager)
    attachments.files.merge(incoming.files) { _, archived in archived }
    try attachments.write(to: stagedAttachmentsURL, fileManager: fileManager)
    var transaction = try LibraryInstallTransaction.prepare(
      at: location.rootURL,
      replacements: [
        "StructuredNotes": staging.structuredNotesDirectoryURL,
        "StructuredListNotes": staging.structuredListNotesDirectoryURL,
        "Attachments": stagedAttachmentsURL,
      ], configuration: .init(settings: restored.settings, templates: restored.templates),
      fileManager: fileManager, recoveryID: recoveryID
    )
    for folder in transaction.record.folders { try transaction.installFolder(named: folder.name) }
    try transaction.markAwaitingConfiguration()
    return preserved
  }
}
