//
//  AppPlan.swift
//

// Defines app-plan feature access independently of StoreKit or UI state.

import Foundation

enum AppPlan: String, CaseIterable, Codable, Identifiable, Sendable {
  case free
  case paid

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .free:
      return "Free"
    case .paid:
      return "Paid"
    }
  }
}

extension AppPlan {
  // Converts durable StoreKit entitlements into the app's capability plan.
  static func resolving(storeEntitlementState: StoreEntitlementState) -> AppPlan {
    storeEntitlementState.includes(.paidUnlock) ? .paid : .free
  }
}

enum AppCapability: String, CaseIterable, Identifiable, Sendable {
  case additionalTemplates
  case customThemeColors
  case automaticBackupSchedules

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .additionalTemplates:
      return "Additional templates"
    case .customThemeColors:
      return "Custom theme colors"
    case .automaticBackupSchedules:
      return "Automatic backup schedules"
    }
  }
}

struct AppFeatureAccess: Equatable, Sendable {
  static let freeTemplateLimit = 1

  let plan: AppPlan

  // Returns whether the active plan includes a feature-level capability.
  func allows(_ capability: AppCapability) -> Bool {
    switch plan {
    case .paid:
      return true
    case .free:
      switch capability {
      case .additionalTemplates, .customThemeColors, .automaticBackupSchedules:
        return false
      }
    }
  }

  var templateLimit: Int? {
    plan == .free ? Self.freeTemplateLimit : nil
  }

  // Returns whether a new user-created template can be added without upgrading.
  func canCreateTemplate(currentTemplateCount: Int) -> Bool {
    guard let templateLimit else { return true }
    return currentTemplateCount < templateLimit
  }

  // Returns the schedules the active plan can actually run.
  func canUseBackupSchedule(_ schedule: BackupSchedule) -> Bool {
    guard plan == .free else { return true }
    return schedule == .manualOnly
  }

  // Returns the schedule that should drive runtime backup behavior for the active plan.
  func effectiveBackupSchedule(_ storedSchedule: BackupSchedule) -> BackupSchedule {
    canUseBackupSchedule(storedSchedule) ? storedSchedule : .manualOnly
  }
}
