//
//  DayraDateFormatters.swift
//  dayra
//
//

import Foundation

enum DayraDateFormatters {
  static let storageDate: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }()

  static let monthDivider: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar.current
    formatter.dateFormat = "MMMM yyyy"
    return formatter
  }()

  static let monthDividerMonthOnly: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar.current
    formatter.dateFormat = "MMMM"
    return formatter
  }()

  static let dayNumber: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar.current
    formatter.dateFormat = "dd"
    return formatter
  }()

  static let weekday: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar.current
    formatter.dateFormat = "EEE"
    return formatter
  }()

  static let editorDate: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar.current
    formatter.dateStyle = .full
    formatter.timeStyle = .none
    return formatter
  }()
}
