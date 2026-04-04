//
//  SidebarDateFormat.swift
//

// User-configurable date display formats for sidebar note cards.

import Foundation

enum SidebarDateFormat: String, CaseIterable, Codable, Sendable {
  case yearMonthDay
  case dayMonthYear
  case dayMonthYearSlashes
  case monthDayYear
  case monthDayYearSlashes
  case dayShortMonthContextual

  // Example format string shown in the settings picker.
  var displayName: String {
    switch self {
    case .yearMonthDay:
      return "YYYY-MM-DD"
    case .dayMonthYear:
      return "DD-MM-YYYY"
    case .dayMonthYearSlashes:
      return "DD/MM/YYYY"
    case .monthDayYear:
      return "MM-DD-YYYY"
    case .monthDayYearSlashes:
      return "MM/DD/YYYY"
    case .dayShortMonthContextual:
      return "1 Apr / 1 Apr 25"
    }
  }

  // Keeps sidebar date display options centralized and reusable.
  func string(from date: Date) -> String {
    switch self {
    case .yearMonthDay:
      return NoteDateFormatters.sidebarYearMonthDay.string(from: date)
    case .dayMonthYear:
      return NoteDateFormatters.sidebarDayMonthYear.string(from: date)
    case .dayMonthYearSlashes:
      return NoteDateFormatters.sidebarDayMonthYearSlashes.string(from: date)
    case .monthDayYear:
      return NoteDateFormatters.sidebarMonthDayYear.string(from: date)
    case .monthDayYearSlashes:
      return NoteDateFormatters.sidebarMonthDayYearSlashes.string(from: date)
    case .dayShortMonthContextual:
      return contextualShortMonthString(from: date)
    }
  }

  // Omits the year for notes in the current year and uses a short year for older notes.
  private func contextualShortMonthString(from date: Date) -> String {
    let currentYear = Calendar.current.component(.year, from: .now)
    let noteYear = Calendar.current.component(.year, from: date)
    let formatter =
      noteYear == currentYear
      ? NoteDateFormatters.sidebarDayShortMonth
      : NoteDateFormatters.sidebarDayShortMonthShortYear

    return formatter.string(from: date)
  }
}
