import XCTest

@testable import Sceal

final class AppFeatureAccessTests: XCTestCase {
  // Free keeps core notes available while locking paid-only customization and automation.
  func testFreePlanLocksPaidCapabilities() {
    let access = AppFeatureAccess(plan: .free)

    XCTAssertFalse(access.allows(.additionalTemplates))
    XCTAssertFalse(access.allows(.customThemeColors))
    XCTAssertFalse(access.allows(.automaticBackupSchedules))
    XCTAssertEqual(access.templateLimit, 1)
    XCTAssertTrue(access.canCreateTemplate(currentTemplateCount: 0))
    XCTAssertFalse(access.canCreateTemplate(currentTemplateCount: 1))
  }

  // Paid keeps current app behavior unrestricted during the migration.
  func testPaidPlanAllowsPaidCapabilities() {
    let access = AppFeatureAccess(plan: .paid)

    XCTAssertTrue(access.allows(.additionalTemplates))
    XCTAssertTrue(access.allows(.customThemeColors))
    XCTAssertTrue(access.allows(.automaticBackupSchedules))
    XCTAssertNil(access.templateLimit)
    XCTAssertTrue(access.canCreateTemplate(currentTemplateCount: 100))
  }

  // Free should never run stored automatic backup schedules.
  func testFreePlanTreatsAutomaticBackupSchedulesAsManualOnly() {
    let access = AppFeatureAccess(plan: .free)

    XCTAssertTrue(access.canUseBackupSchedule(.manualOnly))
    XCTAssertFalse(access.canUseBackupSchedule(.hourly))
    XCTAssertEqual(access.effectiveBackupSchedule(.daily), .manualOnly)
  }
}
