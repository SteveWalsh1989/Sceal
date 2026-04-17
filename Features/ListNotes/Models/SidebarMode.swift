//
//  SidebarMode.swift
//

// Sidebar display mode — calendar grid, daily list, or freeform list view.

import Foundation

enum SidebarMode: String, CaseIterable {
  case calendar
  case daily
  case list

  // Daily and calendar modes both browse the same date-keyed daily-note store.
  var usesDailyNotes: Bool {
    self != .list
  }
}
