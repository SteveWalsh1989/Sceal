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
  #if DEBUG
    private var developerPlanOverride: AppPlan?
  #endif

  init(settingsRepository: SettingsRepository) {
    self.settingsRepository = settingsRepository
    #if DEBUG
      self.developerPlanOverride = settingsRepository.loadDeveloperPlanOverride()
    #endif
    self.activePlan = settingsRepository.loadInitialPlan()
  }

  var featureAccess: AppFeatureAccess {
    AppFeatureAccess(plan: activePlan)
  }

  // Returns whether the active plan includes the requested feature capability.
  func hasAccess(to capability: AppCapability) -> Bool {
    featureAccess.allows(capability)
  }

  // Applies StoreKit entitlement state while keeping capability policy local to this store.
  func updateStoreEntitlements(_ entitlementState: StoreEntitlementState) {
    #if DEBUG
      guard developerPlanOverride == nil else { return }
    #endif

    let resolvedPlan = AppPlan.resolving(storeEntitlementState: entitlementState)
    guard activePlan != resolvedPlan else { return }
    activePlan = resolvedPlan
  }

  // Refreshes entitlement state through the purchase boundary without exposing StoreKit to views.
  @discardableResult
  func refreshStoreEntitlements(
    using purchaseService: StorePurchaseServicing
  ) async throws -> StoreEntitlementState {
    let entitlementState = try await purchaseService.refreshEntitlements()
    updateStoreEntitlements(entitlementState)
    return entitlementState
  }

  #if DEBUG
    // Persists a local plan override for testing free and paid feature gates.
    func updateDeveloperPlan(_ plan: AppPlan) {
      developerPlanOverride = plan
      settingsRepository.saveDeveloperPlan(plan)
      guard activePlan != plan else { return }
      activePlan = plan
    }
  #endif
}
