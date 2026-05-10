import XCTest

@testable import Sceal

final class ActiveNoteRoutingTests: XCTestCase {
  // Keeps calendar and daily sidebar modes pointed at the daily-note route.
  func testDailySidebarModesUseDailyRoute() {
    XCTAssertEqual(
      ActiveNoteRouting.route(for: .daily, isDemoModeEnabled: false),
      .daily
    )
    XCTAssertEqual(
      ActiveNoteRouting.route(for: .calendar, isDemoModeEnabled: false),
      .daily
    )
  }

  // Keeps list sidebar mode pointed at list notes outside demo mode.
  func testListSidebarModeUsesListRoute() {
    XCTAssertEqual(
      ActiveNoteRouting.route(for: .list, isDemoModeEnabled: false),
      .list
    )
  }

  // Prevents demo mode from routing editor state into real list notes.
  func testDemoModeUsesDailyRoute() {
    XCTAssertEqual(
      ActiveNoteRouting.route(for: .list, isDemoModeEnabled: true),
      .daily
    )
  }

  // Keeps active selection resolution independent from NotesStore.
  func testSelectedNoteIDUsesResolvedRoute() {
    XCTAssertEqual(
      ActiveNoteRouting.selectedNoteID(
        route: .daily,
        dailyNoteID: "2026-05-10",
        listNoteID: "2026-05-10-aaaaaa"
      ),
      "2026-05-10"
    )
    XCTAssertEqual(
      ActiveNoteRouting.selectedNoteID(
        route: .list,
        dailyNoteID: "2026-05-10",
        listNoteID: "2026-05-10-aaaaaa"
      ),
      "2026-05-10-aaaaaa"
    )
  }
}
