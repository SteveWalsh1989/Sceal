//
//  NoteDateFormatters.swift
//
//

// Centralized DateFormatter instances shared across the app to avoid repeated allocation.

import Foundation

enum NoteDateFormatters {
  nonisolated static let storageDate: DateFormatter = {
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

  static let sidebarYearMonthDay: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar.current
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }()

  static let sidebarDayMonthYear: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar.current
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "dd-MM-yyyy"
    return formatter
  }()

  static let sidebarMonthDayYear: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar.current
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "MM-dd-yyyy"
    return formatter
  }()

  static let sidebarDayMonthYearSlashes: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar.current
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "dd/MM/yyyy"
    return formatter
  }()

  static let sidebarMonthDayYearSlashes: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar.current
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "MM/dd/yyyy"
    return formatter
  }()

  static let sidebarDayShortMonth: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar.current
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "d MMM"
    return formatter
  }()

  static let sidebarDayShortMonthShortYear: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar.current
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "d MMM yy"
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
