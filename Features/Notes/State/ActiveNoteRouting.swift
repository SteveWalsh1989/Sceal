//
//  ActiveNoteRouting.swift
//

// Shared routing rules for deciding whether editor actions target daily notes or list notes.

enum ActiveNoteRoute: Equatable {
  case daily
  case list
}

enum ActiveNoteRouting {
  // Resolves the editor route from sidebar mode, with demo mode always targeting daily notes.
  static func route(for sidebarMode: SidebarMode, isDemoModeEnabled: Bool) -> ActiveNoteRoute {
    if isDemoModeEnabled {
      return .daily
    }

    return sidebarMode.usesDailyNotes ? .daily : .list
  }

  // Picks the active selected note ID for the resolved route.
  static func selectedNoteID(
    route: ActiveNoteRoute,
    dailyNoteID: DayNote.ID?,
    listNoteID: DayNote.ID?
  ) -> DayNote.ID? {
    switch route {
    case .daily: return dailyNoteID
    case .list: return listNoteID
    }
  }
}
