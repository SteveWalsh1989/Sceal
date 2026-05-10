import Foundation
import XCTest

@testable import Sceal

@MainActor
final class PlanAccessStoreTests: NotesStoreTestCase {
  // Existing builds default to paid so current feature access is preserved.
  func testDefaultsToPaidPlan() {
    let store = PlanAccessStore(
      settingsRepository: SettingsRepository(userDefaults: makeUserDefaults())
    )

    XCTAssertEqual(store.activePlan, .paid)
    XCTAssertTrue(store.hasAccess(to: .additionalTemplates))
    XCTAssertTrue(store.hasAccess(to: .customThemeColors))
    XCTAssertTrue(store.hasAccess(to: .automaticBackupSchedules))
  }

  // Store entitlements can move capability access without exposing StoreKit to feature views.
  func testStoreEntitlementsResolveActivePlan() {
    let store = PlanAccessStore(
      settingsRepository: SettingsRepository(userDefaults: makeUserDefaults())
    )

    store.updateStoreEntitlements(.none)

    XCTAssertEqual(store.activePlan, .free)
    XCTAssertFalse(store.hasAccess(to: .customThemeColors))

    store.updateStoreEntitlements(.paid)

    XCTAssertEqual(store.activePlan, .paid)
    XCTAssertTrue(store.hasAccess(to: .customThemeColors))
  }

  #if DEBUG
    // Developer overrides persist with the existing debug defaults key.
    func testDeveloperPlanOverridePersists() {
      let userDefaults = makeUserDefaults()
      let store = PlanAccessStore(
        settingsRepository: SettingsRepository(userDefaults: userDefaults)
      )

      store.updateDeveloperPlan(.free)

      XCTAssertEqual(store.activePlan, .free)
      XCTAssertFalse(store.hasAccess(to: .additionalTemplates))
      XCTAssertEqual(userDefaults.string(forKey: "sceal.developer.plan"), "free")
    }

    // Developer plan selection wins over Store entitlement refreshes in DEBUG.
    func testDeveloperPlanOverrideWinsOverStoreEntitlements() {
      let store = PlanAccessStore(
        settingsRepository: SettingsRepository(userDefaults: makeUserDefaults())
      )

      store.updateDeveloperPlan(.free)
      store.updateStoreEntitlements(.paid)

      XCTAssertEqual(store.activePlan, .free)
    }

    // Selecting the already-active plan still records an explicit developer override.
    func testDeveloperPlanOverridePersistsWhenPlanAlreadyActive() {
      let userDefaults = makeUserDefaults()
      let store = PlanAccessStore(
        settingsRepository: SettingsRepository(userDefaults: userDefaults)
      )

      store.updateDeveloperPlan(.paid)

      XCTAssertEqual(store.activePlan, .paid)
      XCTAssertEqual(userDefaults.string(forKey: "sceal.developer.plan"), "paid")
    }
  #endif
}
