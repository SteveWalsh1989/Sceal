//
//  SidebarDateFormat.swift
//  dayra
//

import Foundation

enum SidebarDateFormat: String, CaseIterable, Codable {
  case yearMonthDay
  case dayMonthYear
  case dayMonthYearSlashes
  case monthDayYear
  case monthDayYearSlashes
  case dayShortMonthContextual

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
      return DayraDateFormatters.sidebarYearMonthDay.string(from: date)
    case .dayMonthYear:
      return DayraDateFormatters.sidebarDayMonthYear.string(from: date)
    case .dayMonthYearSlashes:
      return DayraDateFormatters.sidebarDayMonthYearSlashes.string(from: date)
    case .monthDayYear:
      return DayraDateFormatters.sidebarMonthDayYear.string(from: date)
    case .monthDayYearSlashes:
      return DayraDateFormatters.sidebarMonthDayYearSlashes.string(from: date)
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
      ? DayraDateFormatters.sidebarDayShortMonth
      : DayraDateFormatters.sidebarDayShortMonthShortYear

    return formatter.string(from: date)
  }
}
