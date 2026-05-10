//
//  StorePurchaseService.swift
//

// Purchase-service boundary for StoreKit-backed entitlement refreshes.

import Combine
import Foundation
import StoreKit

@MainActor
protocol StorePurchaseServicing: AnyObject {
  var entitlementState: StoreEntitlementState { get }

  func loadProducts() async throws -> [StoreProduct]
  func purchase(productID: String) async throws -> StorePurchaseOutcome
  func refreshEntitlements() async throws -> StoreEntitlementState
  func restorePurchases() async throws -> StoreEntitlementState
}

struct StoreProduct: Equatable, Identifiable, Sendable {
  let id: String
  let displayName: String
  let description: String
  let displayPrice: String
  let entitlement: StoreEntitlement
}

enum StorePurchaseOutcome: Equatable, Sendable {
  case purchased(StoreEntitlementState)
  case pending
  case cancelled
}

enum StorePurchaseServiceError: LocalizedError, Equatable {
  case productUnavailable(String)
  case unverifiedTransaction(String)
  case unknownPurchaseResult

  var errorDescription: String? {
    switch self {
    case .productUnavailable(let productID):
      return "Store product is unavailable: \(productID)"
    case .unverifiedTransaction(let detail):
      return "Store transaction could not be verified. \(detail)"
    case .unknownPurchaseResult:
      return "StoreKit returned an unknown purchase result."
    }
  }
}

@MainActor
final class LocalStorePurchaseService: ObservableObject, StorePurchaseServicing {
  @Published private(set) var entitlementState: StoreEntitlementState

  private let products: [StoreProduct]

  init(
    entitlementState: StoreEntitlementState = .none,
    products: [StoreProduct] = [
      StoreProduct(
        id: StoreProductIdentifier.paidUnlock,
        displayName: "Scéal Paid Unlock",
        description: "Unlock paid customization and automation features.",
        displayPrice: "$14.99",
        entitlement: .paidUnlock
      )
    ]
  ) {
    self.entitlementState = entitlementState
    self.products = products
  }

  // Allows DEBUG and tests to simulate StoreKit state without transaction code.
  func updateEntitlementState(_ entitlementState: StoreEntitlementState) {
    self.entitlementState = entitlementState
  }

  func loadProducts() async throws -> [StoreProduct] {
    products
  }

  func purchase(productID: String) async throws -> StorePurchaseOutcome {
    guard let product = products.first(where: { $0.id == productID }) else {
      throw StorePurchaseServiceError.productUnavailable(productID)
    }

    var activeEntitlements = entitlementState.activeEntitlements
    activeEntitlements.insert(product.entitlement)
    let updatedState = StoreEntitlementState(activeEntitlements: activeEntitlements)
    updateEntitlementState(updatedState)
    return .purchased(updatedState)
  }

  func refreshEntitlements() async throws -> StoreEntitlementState {
    entitlementState
  }

  func restorePurchases() async throws -> StoreEntitlementState {
    try await refreshEntitlements()
  }
}

@MainActor
final class StoreKitPurchaseService: ObservableObject, StorePurchaseServicing {
  @Published private(set) var entitlementState: StoreEntitlementState

  let configuredProductIDs: [String]

  private var cachedProductsByID: [String: Product] = [:]

  init(
    entitlementState: StoreEntitlementState = .none,
    productIDs: [String] = StoreProductIdentifier.all
  ) {
    self.entitlementState = entitlementState
    self.configuredProductIDs = productIDs
  }

  func loadProducts() async throws -> [StoreProduct] {
    let storeKitProducts = try await Product.products(for: configuredProductIDs)
    cachedProductsByID = Dictionary(
      uniqueKeysWithValues: storeKitProducts.map { ($0.id, $0) }
    )

    let order = Dictionary(
      uniqueKeysWithValues: configuredProductIDs.enumerated().map { ($0.element, $0.offset) }
    )
    return storeKitProducts.compactMap(storeProduct(from:)).sorted {
      (order[$0.id] ?? Int.max) < (order[$1.id] ?? Int.max)
    }
  }

  func purchase(productID: String) async throws -> StorePurchaseOutcome {
    let product = try await storeKitProduct(for: productID)
    let result = try await product.purchase()

    switch result {
    case .success(let verificationResult):
      let transaction = try Self.verified(verificationResult)
      await transaction.finish()
      let updatedState = try await refreshEntitlements()
      return .purchased(updatedState)
    case .pending:
      return .pending
    case .userCancelled:
      return .cancelled
    @unknown default:
      throw StorePurchaseServiceError.unknownPurchaseResult
    }
  }

  func refreshEntitlements() async throws -> StoreEntitlementState {
    var activeEntitlements = Set<StoreEntitlement>()

    for await verificationResult in Transaction.currentEntitlements {
      let transaction = try Self.verified(verificationResult)
      guard transaction.revocationDate == nil else { continue }

      if let entitlement = StoreEntitlement(productID: transaction.productID) {
        activeEntitlements.insert(entitlement)
      }
    }

    let updatedState = StoreEntitlementState(activeEntitlements: activeEntitlements)
    entitlementState = updatedState
    return updatedState
  }

  func restorePurchases() async throws -> StoreEntitlementState {
    try await AppStore.sync()
    return try await refreshEntitlements()
  }

  private func storeKitProduct(for productID: String) async throws -> Product {
    if let cachedProduct = cachedProductsByID[productID] {
      return cachedProduct
    }

    _ = try await loadProducts()

    guard let product = cachedProductsByID[productID] else {
      throw StorePurchaseServiceError.productUnavailable(productID)
    }

    return product
  }

  private func storeProduct(from product: Product) -> StoreProduct? {
    guard let entitlement = StoreEntitlement(productID: product.id) else {
      return nil
    }

    return StoreProduct(
      id: product.id,
      displayName: product.displayName,
      description: product.description,
      displayPrice: product.displayPrice,
      entitlement: entitlement
    )
  }

  private nonisolated static func verified<Value>(
    _ verificationResult: VerificationResult<Value>
  ) throws -> Value {
    switch verificationResult {
    case .verified(let value):
      return value
    case .unverified(_, let error):
      throw StorePurchaseServiceError.unverifiedTransaction(error.localizedDescription)
    }
  }
}
