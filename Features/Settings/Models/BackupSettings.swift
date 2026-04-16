import Foundation

enum BackupSchedule: String, CaseIterable, Codable, Sendable {
  case manualOnly
  case hourly
  case daily
  case weekly

  var displayName: String {
    switch self {
    case .manualOnly: return "Manual only"
    case .hourly: return "Hourly"
    case .daily: return "Daily"
    case .weekly: return "Weekly"
    }
  }

  var automaticInterval: TimeInterval? {
    switch self {
    case .manualOnly:
      return nil
    case .hourly:
      return 60 * 60
    case .daily:
      return 24 * 60 * 60
    case .weekly:
      return 7 * 24 * 60 * 60
    }
  }

  var retainedAutomaticBackupCount: Int? {
    switch self {
    case .manualOnly:
      return nil
    case .hourly:
      return 24
    case .daily:
      return 30
    case .weekly:
      return 26
    }
  }
}

enum BackupHealth: String, Sendable {
  case notConfigured
  case healthy
  case running
  case overdue
  case folderUnavailable
  case permissionRequired
  case failed

  var displayName: String {
    switch self {
    case .notConfigured: return "Not configured"
    case .healthy: return "Healthy"
    case .running: return "Running"
    case .overdue: return "Overdue"
    case .folderUnavailable: return "Folder unavailable"
    case .permissionRequired: return "Permission needed"
    case .failed: return "Last backup failed"
    }
  }
}

enum BackupArchiveKind: String, Codable, Sendable {
  case manual
  case automatic
}

enum BackupTrigger: Equatable, Sendable {
  case manual
  case locationConfigured
  case launchCatchUp
  case inactive
  case periodicTimer
  case postImport

  nonisolated var archiveKind: BackupArchiveKind {
    switch self {
    case .manual, .locationConfigured:
      return .manual
    case .launchCatchUp, .inactive, .periodicTimer, .postImport:
      return .automatic
    }
  }
}

struct BackupSettings: Codable, Equatable, Sendable {
  var folderBookmarkData: Data?
  var folderDisplayPath: String?
  var schedule: BackupSchedule
  var backupOnInactive: Bool
  var lastSuccessfulBackupAt: Date?
  var lastAttemptedBackupAt: Date?
  var lastBackupErrorDescription: String?
  var lastBackupArchiveName: String?
  var lastBackupBytes: Int64?

  static let `default` = BackupSettings(
    folderBookmarkData: nil,
    folderDisplayPath: nil,
    schedule: .daily,
    backupOnInactive: true,
    lastSuccessfulBackupAt: nil,
    lastAttemptedBackupAt: nil,
    lastBackupErrorDescription: nil,
    lastBackupArchiveName: nil,
    lastBackupBytes: nil
  )

  var isConfigured: Bool {
    folderBookmarkData != nil && folderDisplayPath != nil
  }
}
