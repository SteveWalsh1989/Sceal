import XCTest

@testable import Sceal

final class SidebarDateFormatTests: NotesStoreTestCase {
  // Prevents the ISO-style sidebar date from drifting away from its documented format.
  func testYearMonthDay() {
    let date = makeDate(year: 2026, month: 4, day: 9)

    XCTAssertEqual(SidebarDateFormat.yearMonthDay.string(from: date), "2026-04-09")
  }

  // Prevents the day-first sidebar date format from swapping month and day.
  func testDayMonthYear() {
    let date = makeDate(year: 2026, month: 4, day: 9)

    XCTAssertEqual(SidebarDateFormat.dayMonthYear.string(from: date), "09-04-2026")
  }

  // Prevents contextual short dates from showing a year for notes in the current year.
  func testCurrentYearContextualShortMonthOmitsYear() {
    let currentYear = Calendar.current.component(.year, from: .now)
    let date = makeDate(year: currentYear, month: 4, day: 9)

    XCTAssertEqual(SidebarDateFormat.dayShortMonthContextual.string(from: date), "9 Apr")
  }

  // Prevents contextual short dates from hiding the year for older notes.
  func testPastYearContextualShortMonthIncludesShortYear() {
    let currentYear = Calendar.current.component(.year, from: .now)
    let date = makeDate(year: currentYear - 1, month: 4, day: 9)

    XCTAssertEqual(
      SidebarDateFormat.dayShortMonthContextual.string(from: date),
      "9 Apr \(String(format: "%02d", (currentYear - 1) % 100))"
    )
  }
}
