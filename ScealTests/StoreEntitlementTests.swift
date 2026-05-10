import XCTest

@testable import Sceal

final class StoreEntitlementTests: XCTestCase {
  func testPaidUnlockHasStablePlaceholderProductID() {
    XCTAssertEqual(StoreEntitlement.paidUnlock.productID, "com.stevewalsh.sceal.paidUnlock")
    XCTAssertEqual(StoreEntitlement(productID: StoreProductIdentifier.paidUnlock), .paidUnlock)
    XCTAssertEqual(StoreProductIdentifier.all, ["com.stevewalsh.sceal.paidUnlock"])
  }

  // Paid Store entitlement maps to Paid while no entitlement maps to Free.
  func testStoreEntitlementStateMapsToAppPlan() {
    XCTAssertEqual(AppPlan.resolving(storeEntitlementState: .none), .free)
    XCTAssertEqual(AppPlan.resolving(storeEntitlementState: .paid), .paid)
  }

  // Local purchase service lets tests simulate StoreKit product and entitlement refreshes.
  @MainActor
  func testLocalStorePurchaseServiceLoadsAndPurchasesProducts() async throws {
    let localService = LocalStorePurchaseService()
    let service: StorePurchaseServicing = localService
    let products = try await service.loadProducts()
    let initialState = try await service.refreshEntitlements()

    XCTAssertEqual(products.map(\.id), [StoreProductIdentifier.paidUnlock])
    XCTAssertEqual(products.first?.entitlement, .paidUnlock)
    XCTAssertEqual(service.entitlementState, .none)
    XCTAssertEqual(initialState, .none)

    let outcome = try await service.purchase(productID: StoreProductIdentifier.paidUnlock)
    let restoredState = try await service.restorePurchases()

    XCTAssertEqual(outcome, .purchased(.paid))
    XCTAssertEqual(restoredState, .paid)
    XCTAssertEqual(service.entitlementState, .paid)
  }

  @MainActor
  func testLocalStorePurchaseServiceRejectsUnknownProducts() async throws {
    let service = LocalStorePurchaseService()

    do {
      _ = try await service.purchase(productID: "unknown.product")
      XCTFail("Expected unknown products to be rejected.")
    } catch StorePurchaseServiceError.productUnavailable(let productID) {
      XCTAssertEqual(productID, "unknown.product")
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  @MainActor
  func testStoreKitPurchaseServiceUsesPlaceholderProductID() {
    let service = StoreKitPurchaseService()

    XCTAssertEqual(service.configuredProductIDs, [StoreProductIdentifier.paidUnlock])
  }
}
