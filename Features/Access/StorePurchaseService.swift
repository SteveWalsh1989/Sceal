//
//  StorePurchaseService.swift
//

// Purchase-service boundary for StoreKit-backed entitlement refreshes.

import Combine
import Foundation

@MainActor
protocol StorePurchaseServicing: AnyObject {
  var entitlementState: StoreEntitlementState { get }

  func refreshEntitlements() async throws -> StoreEntitlementState
}

@MainActor
final class LocalStorePurchaseService: ObservableObject, StorePurchaseServicing {
  @Published private(set) var entitlementState: StoreEntitlementState

  init(entitlementState: StoreEntitlementState = .none) {
    self.entitlementState = entitlementState
  }

  // Allows DEBUG and tests to simulate StoreKit state without transaction code.
  func updateEntitlementState(_ entitlementState: StoreEntitlementState) {
    self.entitlementState = entitlementState
  }

  func refreshEntitlements() async throws -> StoreEntitlementState {
    entitlementState
  }
}
