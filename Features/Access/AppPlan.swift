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
  case premiumThemes
  case additionalTemplates
  case customThemeColors
  case automaticBackupSchedules

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .premiumThemes:
      return "Premium themes"
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
  static let freeThemeLimitPerMode = 2

  let plan: AppPlan

  // Returns whether the active plan includes a feature-level capability.
  func allows(_ capability: AppCapability) -> Bool {
    switch plan {
    case .paid:
      return true
    case .free:
      switch capability {
      case .premiumThemes, .additionalTemplates, .customThemeColors,
        .automaticBackupSchedules:
        return false
      }
    }
  }

  var templateLimit: Int? {
    plan == .free ? Self.freeTemplateLimit : nil
  }

  var themeLimitPerMode: Int? {
    plan == .free ? Self.freeThemeLimitPerMode : nil
  }

  // Returns whether a theme at the given display index is available to the active plan.
  func canUseTheme(atModeIndex index: Int) -> Bool {
    guard let themeLimitPerMode else { return true }
    return index < themeLimitPerMode
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
