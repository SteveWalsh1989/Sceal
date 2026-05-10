//
//  StoreEntitlement.swift
//

// Store entitlement state that can be mapped into app-plan access policy.

import Foundation

nonisolated enum StoreEntitlement: String, CaseIterable, Codable, Identifiable, Sendable {
  case paidUnlock

  var id: String { rawValue }

  var productID: String {
    switch self {
    case .paidUnlock:
      return "com.stevewalsh.sceal.paidUnlock"
    }
  }

  var displayName: String {
    switch self {
    case .paidUnlock:
      return "Paid unlock"
    }
  }

  init?(productID: String) {
    guard let entitlement = Self.allCases.first(where: { $0.productID == productID }) else {
      return nil
    }

    self = entitlement
  }
}

nonisolated enum StoreProductIdentifier {
  static let paidUnlock = StoreEntitlement.paidUnlock.productID
  static let all = StoreEntitlement.allCases.map(\.productID)
}

nonisolated struct StoreEntitlementState: Codable, Equatable, Sendable {
  static let none = StoreEntitlementState()
  static let paid = StoreEntitlementState(activeEntitlements: [.paidUnlock])

  var activeEntitlements: Set<StoreEntitlement>

  init(activeEntitlements: Set<StoreEntitlement> = []) {
    self.activeEntitlements = activeEntitlements
  }

  // Returns whether StoreKit has granted the requested durable entitlement.
  func includes(_ entitlement: StoreEntitlement) -> Bool {
    activeEntitlements.contains(entitlement)
  }
}
