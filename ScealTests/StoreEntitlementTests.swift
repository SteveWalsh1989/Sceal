import XCTest

@testable import Sceal

final class StoreEntitlementTests: XCTestCase {
  // Paid Store entitlement maps to Paid while no entitlement maps to Free.
  func testStoreEntitlementStateMapsToAppPlan() {
    XCTAssertEqual(AppPlan.resolving(storeEntitlementState: .none), .free)
    XCTAssertEqual(AppPlan.resolving(storeEntitlementState: .paid), .paid)
  }

  // Local purchase service lets tests simulate StoreKit entitlement refreshes.
  @MainActor
  func testLocalStorePurchaseServiceRefreshesCurrentState() async throws {
    let localService = LocalStorePurchaseService()
    let service: StorePurchaseServicing = localService
    let initialState = try await service.refreshEntitlements()

    XCTAssertEqual(service.entitlementState, .none)
    XCTAssertEqual(initialState, .none)

    localService.updateEntitlementState(.paid)

    let paidState = try await service.refreshEntitlements()

    XCTAssertEqual(service.entitlementState, .paid)
    XCTAssertEqual(paidState, .paid)
  }
}
