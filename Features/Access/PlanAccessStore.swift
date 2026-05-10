//
//  PlanAccessStore.swift
//

// Feature store for active plan state and capability checks.

import Combine
import Foundation

@MainActor
final class PlanAccessStore: ObservableObject {
  @Published private(set) var activePlan: AppPlan

  private let settingsRepository: SettingsRepository

  init(settingsRepository: SettingsRepository) {
    self.settingsRepository = settingsRepository
    self.activePlan = settingsRepository.loadInitialPlan()
  }

  var featureAccess: AppFeatureAccess {
    AppFeatureAccess(plan: activePlan)
  }

  // Returns whether the active plan includes the requested feature capability.
  func hasAccess(to capability: AppCapability) -> Bool {
    featureAccess.allows(capability)
  }

  #if DEBUG
    // Persists a local plan override for testing free and paid feature gates.
    func updateDeveloperPlan(_ plan: AppPlan) {
      guard activePlan != plan else { return }
      activePlan = plan
      settingsRepository.saveDeveloperPlan(plan)
    }
  #endif
}
