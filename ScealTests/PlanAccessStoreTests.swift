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
  #endif
}
