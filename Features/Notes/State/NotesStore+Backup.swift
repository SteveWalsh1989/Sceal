import AppKit
import Foundation
import OSLog

// NotesStore extension for folder-backed automatic backups that never modify live note storage.
extension NotesStore {
  private static let backupLogger = Logger(subsystem: "com.sceal.app", category: "backup")
  private static let backupCheckIntervalNanoseconds: UInt64 = 300_000_000_000

  // Persists the selected automatic backup schedule.
  func updateBackupSchedule(_ schedule: BackupSchedule) {
    backupSettings.schedule = schedule
    backupSettings.lastBackupErrorDescription = nil
    persistBackupSettings()
    refreshBackupHealth()
  }

  // Persists whether backups should run when the app becomes inactive.
  func updateBackupOnInactive(_ value: Bool) {
    backupSettings.backupOnInactive = value
    persistBackupSettings()
  }

  // Opens a folder picker, stores bookmark access, and creates the initial backup snapshot.
  func chooseBackupFolder() {
    guard !isBackupRunning else {
      userMessage = (text: "A backup is already running.", kind: .info)
      return
    }

    let panel = NSOpenPanel()
    panel.title = "Choose Backup Folder"
    panel.message =
      "Choose a folder for Scéal backups. A 'Sceal Backup' folder will be created inside it."
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false

    guard panel.runModal() == .OK, let selectedFolderURL = panel.url else {
      return
    }

    do {
      let bookmarkData = try bookmarkData(for: selectedFolderURL)
      try validateBackupFolder(at: selectedFolderURL, bookmarkData: bookmarkData)

      backupSettings.folderBookmarkData = bookmarkData
      backupSettings.folderDisplayPath = selectedFolderURL.path
      backupSettings.lastSuccessfulBackupAt = nil
      backupSettings.lastAttemptedBackupAt = nil
      backupSettings.lastBackupErrorDescription = nil
      backupSettings.lastBackupArchiveName = nil
      backupSettings.lastBackupBytes = nil
      persistBackupSettings()
      refreshBackupHealth()
      performBackup(trigger: .locationConfigured, respectSchedule: false)
    } catch {
      report(error, context: "Choosing backup folder failed")
      refreshBackupHealth()
    }
  }

  // Clears the configured backup folder without touching any existing backup archives.
  func removeBackupFolder() {
    guard !isBackupRunning else {
      userMessage = (
        text: "Wait for the current backup to finish before removing the folder.", kind: .info
      )
      return
    }

    backupSettings.folderBookmarkData = nil
    backupSettings.folderDisplayPath = nil
    backupSettings.lastSuccessfulBackupAt = nil
    backupSettings.lastAttemptedBackupAt = nil
    backupSettings.lastBackupErrorDescription = nil
    backupSettings.lastBackupArchiveName = nil
    backupSettings.lastBackupBytes = nil
    persistBackupSettings()
    refreshBackupHealth()
  }

  // Reveals the managed backup folder in Finder if it is accessible.
  func revealBackupFolderInFinder() {
    do {
      let backupFolderURL = try resolveManagedBackupFolderURL()
      NSWorkspace.shared.activateFileViewerSelecting([backupFolderURL])
    } catch {
      report(error, context: "Opening backup folder failed")
      refreshBackupHealth()
    }
  }

  // Forces a backup immediately, regardless of schedule.
  func runBackupNow() {
    performBackup(trigger: .manual, respectSchedule: false)
  }

  // Runs an automatic backup when the configured schedule says one is due.
  func checkAndRunBackupIfDue(trigger: BackupTrigger) {
    performBackup(trigger: trigger, respectSchedule: true)
  }

  // Refreshes the published backup status after settings or filesystem changes.
  func refreshBackupHealth(now: Date = .now) {
    if isBackupRunning {
      backupHealth = .running
      return
    }

    guard backupSettings.isConfigured else {
      backupHealth = .notConfigured
      return
    }

    do {
      let backupFolderURL = try resolveManagedBackupFolderURL()
      guard fileManager.fileExists(atPath: backupFolderURL.path) else {
        backupHealth = .folderUnavailable
        return
      }
    } catch {
      backupHealth = backupDestinationHealth(for: error)
      return
    }

    if backupSettings.schedule != .manualOnly, isBackupDue(at: now) {
      backupHealth = .overdue
      return
    }

    backupHealth = backupSettings.lastBackupErrorDescription == nil ? .healthy : .failed
  }

  // Returns the next automatic backup date when a schedule is configured.
  func nextBackupDueDate(from referenceDate: Date = .now) -> Date? {
    guard backupSettings.isConfigured, let interval = backupSettings.schedule.automaticInterval
    else {
      return nil
    }

    guard let lastSuccessfulBackupAt = backupSettings.lastSuccessfulBackupAt else {
      return referenceDate
    }

    return lastSuccessfulBackupAt.addingTimeInterval(interval)
  }

  // Returns whether an automatic backup is currently due.
  func isBackupDue(at referenceDate: Date = .now) -> Bool {
    guard let nextBackupDueDate = nextBackupDueDate(from: referenceDate) else {
      return false
    }

    return referenceDate >= nextBackupDueDate
  }

  // Starts periodic due checks while the app is open.
  func startPeriodicBackupChecks() {
    periodicBackupCheckTask?.cancel()
    periodicBackupCheckTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: Self.backupCheckIntervalNanoseconds)
        guard !Task.isCancelled else { break }
        await MainActor.run {
          self?.checkAndRunBackupIfDue(trigger: .periodicTimer)
        }
      }
    }
  }

  private func performBackup(trigger: BackupTrigger, respectSchedule: Bool) {
    guard backupSettings.isConfigured else {
      return
    }

    guard !isBackupRunning else {
      if trigger == .manual {
        userMessage = (text: "A backup is already running.", kind: .info)
      }
      return
    }

    if respectSchedule && !isBackupDue() {
      refreshBackupHealth()
      return
    }

    let shouldShowProgress = trigger == .manual || trigger == .locationConfigured
    if shouldShowProgress {
      isPerformingFileOperation = true
      progressMessage = "Backing up…"
    }

    flushPendingSaves()
    let dailyNotesSnapshot = notes
    let listNotesSnapshot = listNotes
    let manifestSnapshot = listNoteManifest
    let backupSettingsSnapshot = backupSettings
    let backupDate = Date.now

    isBackupRunning = true
    backupHealth = .running
    backupSettings.lastAttemptedBackupAt = backupDate
    backupSettings.lastBackupErrorDescription = nil
    persistBackupSettings()

    let fm = fileManager
    Task.detached { [weak self] in
      do {
        let bookmarkData = try Self.requireBookmarkData(from: backupSettingsSnapshot)
        let archiveURL = try Self.writeBackupArchive(
          dailyNotes: dailyNotesSnapshot,
          listNotes: listNotesSnapshot,
          manifest: manifestSnapshot,
          bookmarkData: bookmarkData,
          kind: trigger.archiveKind,
          schedule: backupSettingsSnapshot.schedule,
          createdAt: backupDate,
          fileManager: fm
        )

        let archiveAttributes = try fm.attributesOfItem(atPath: archiveURL.path)
        let archiveSize = (archiveAttributes[.size] as? NSNumber)?.int64Value

        await MainActor.run { [weak self] in
          guard let self else { return }
          self.backupSettings.lastSuccessfulBackupAt = backupDate
          self.backupSettings.lastBackupErrorDescription = nil
          self.backupSettings.lastBackupArchiveName = archiveURL.lastPathComponent
          self.backupSettings.lastBackupBytes = archiveSize
          self.persistBackupSettings()
          self.isBackupRunning = false
          self.isPerformingFileOperation = false
          self.progressMessage = nil
          if trigger == .manual || trigger == .locationConfigured {
            self.userMessage = (text: "Backup complete.", kind: .info)
          }
          self.refreshBackupHealth(now: backupDate)
        }
      } catch {
        await MainActor.run { [weak self] in
          guard let self else { return }
          Self.backupLogger.error("Backup failed: \(error.localizedDescription)")
          self.backupSettings.lastBackupErrorDescription = error.localizedDescription
          self.persistBackupSettings()
          self.isBackupRunning = false
          self.isPerformingFileOperation = false
          self.progressMessage = nil
          self.report(error, context: "Backing up notes failed")
          self.refreshBackupHealth()
        }
      }
    }
  }

  private func bookmarkData(for folderURL: URL) throws -> Data {
    try folderURL.bookmarkData(
      options: [.withSecurityScope],
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )
  }

  private func validateBackupFolder(at folderURL: URL, bookmarkData: Data) throws {
    let backupFolderURL = try Self.accessBookmark(bookmarkData) { scopedFolderURL in
      let managedFolderURL = ScealBackupArchiveExporter.managedBackupDirectoryURL(
        in: scopedFolderURL)
      try fileManager.createDirectory(at: managedFolderURL, withIntermediateDirectories: true)
      let probeURL = managedFolderURL.appendingPathComponent("backup-access-check.tmp")
      let probeContents = Data("ok".utf8)
      try probeContents.write(to: probeURL, options: .atomic)
      try fileManager.removeItem(at: probeURL)
      return managedFolderURL
    }

    guard backupFolderURL.path.hasPrefix(folderURL.path) else {
      throw BackupFolderError.invalidManagedFolder
    }
  }

  private func resolveManagedBackupFolderURL() throws -> URL {
    let bookmarkData = try Self.requireBookmarkData(from: backupSettings)
    return try Self.accessBookmark(bookmarkData) { selectedFolderURL in
      ScealBackupArchiveExporter.managedBackupDirectoryURL(in: selectedFolderURL)
    }
  }

  nonisolated private static func accessBookmark<T>(
    _ bookmarkData: Data,
    accessBlock: (URL) throws -> T
  ) throws -> T {
    var isStale = false
    let selectedFolderURL = try URL(
      resolvingBookmarkData: bookmarkData,
      options: [.withSecurityScope, .withoutUI],
      relativeTo: nil,
      bookmarkDataIsStale: &isStale
    )

    if isStale {
      throw BackupFolderError.permissionRequired
    }

    let didStartAccessing = selectedFolderURL.startAccessingSecurityScopedResource()
    guard didStartAccessing else {
      throw BackupFolderError.permissionRequired
    }

    defer {
      selectedFolderURL.stopAccessingSecurityScopedResource()
    }

    return try accessBlock(selectedFolderURL)
  }

  private func backupDestinationHealth(for error: Error) -> BackupHealth {
    if let backupFolderError = error as? BackupFolderError {
      switch backupFolderError {
      case .folderNotConfigured:
        return .notConfigured
      case .permissionRequired:
        return .permissionRequired
      case .invalidManagedFolder:
        return .folderUnavailable
      }
    }

    return .failed
  }

  func persistBackupSettings() {
    do {
      let data = try JSONEncoder().encode(backupSettings)
      userDefaults.set(data, forKey: Self.backupSettingsDefaultsKey)
    } catch {
      report(error, context: "Saving backup settings failed")
    }
  }

  nonisolated static func loadBackupSettings(from userDefaults: UserDefaults) -> BackupSettings {
    guard
      let data = userDefaults.data(forKey: backupSettingsDefaultsKey),
      let settings = try? JSONDecoder().decode(BackupSettings.self, from: data)
    else {
      return .default
    }

    return settings
  }

  nonisolated private static func requireBookmarkData(from settings: BackupSettings) throws -> Data
  {
    guard let bookmarkData = settings.folderBookmarkData else {
      throw BackupFolderError.folderNotConfigured
    }

    return bookmarkData
  }

  nonisolated static func writeBackupArchive(
    dailyNotes: [DayNote],
    listNotes: [DayNote],
    manifest: ListNotesManifest,
    bookmarkData: Data,
    kind: BackupArchiveKind,
    schedule: BackupSchedule,
    createdAt: Date,
    fileManager: FileManager
  ) throws -> URL {
    try accessBookmark(bookmarkData) { selectedFolderURL in
      let managedFolderURL = ScealBackupArchiveExporter.managedBackupDirectoryURL(
        in: selectedFolderURL)
      try fileManager.createDirectory(at: managedFolderURL, withIntermediateDirectories: true)

      let temporaryArchiveURL = try ScealBackupArchiveExporter.exportBackup(
        dailyNotes: dailyNotes,
        listNotes: listNotes,
        manifest: manifest,
        kind: kind,
        createdAt: createdAt
      )
      let destinationArchiveURL = managedFolderURL.appendingPathComponent(
        temporaryArchiveURL.lastPathComponent
      )

      if fileManager.fileExists(atPath: destinationArchiveURL.path) {
        try fileManager.removeItem(at: destinationArchiveURL)
      }

      try fileManager.moveItem(at: temporaryArchiveURL, to: destinationArchiveURL)
      ZipArchiveWriter.cleanUp(zipURL: temporaryArchiveURL)

      if kind == .automatic {
        try pruneAutomaticBackups(
          in: managedFolderURL,
          schedule: schedule,
          fileManager: fileManager
        )
      }

      return destinationArchiveURL
    }
  }

  nonisolated static func pruneAutomaticBackups(
    in managedFolderURL: URL,
    schedule: BackupSchedule,
    fileManager: FileManager = .default
  ) throws {
    guard let retainedAutomaticBackupCount = schedule.retainedAutomaticBackupCount else {
      return
    }

    let automaticArchiveURLs = try fileManager.contentsOfDirectory(
      at: managedFolderURL,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )
    .filter { $0.lastPathComponent.hasPrefix("sceal-backup-auto-") && $0.pathExtension == "zip" }
    .sorted(by: { $0.lastPathComponent > $1.lastPathComponent })

    guard automaticArchiveURLs.count > retainedAutomaticBackupCount else {
      return
    }

    for archiveURL in automaticArchiveURLs.dropFirst(retainedAutomaticBackupCount) {
      try fileManager.removeItem(at: archiveURL)
    }
  }
}

enum BackupFolderError: LocalizedError {
  case folderNotConfigured
  case permissionRequired
  case invalidManagedFolder

  var errorDescription: String? {
    switch self {
    case .folderNotConfigured:
      return "Choose a backup folder first."
    case .permissionRequired:
      return "Scéal needs permission to access the backup folder again."
    case .invalidManagedFolder:
      return "Scéal could not prepare the managed backup folder."
    }
  }
}
