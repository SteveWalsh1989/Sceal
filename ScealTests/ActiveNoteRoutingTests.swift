import XCTest

@testable import Sceal

final class ActiveNoteRoutingTests: XCTestCase {
  // Keeps calendar and daily sidebar modes pointed at the daily-note route.
  func testDailySidebarModesUseDailyRoute() {
    XCTAssertEqual(
      ActiveNoteRouting.route(for: .daily),
      .daily
    )
    XCTAssertEqual(
      ActiveNoteRouting.route(for: .calendar),
      .daily
    )
  }

  // Keeps list sidebar mode pointed at list notes.
  func testListSidebarModeUsesListRoute() {
    XCTAssertEqual(
      ActiveNoteRouting.route(for: .list),
      .list
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
