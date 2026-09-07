//
//  ActiveNoteRouting.swift
//

// Shared routing rules for deciding whether editor actions target daily notes or list notes.

enum ActiveNoteRoute: Equatable {
  case daily
  case list
}

enum ActiveNoteRouting {
  // Resolves the editor route from the current sidebar mode.
  static func route(for sidebarMode: SidebarMode) -> ActiveNoteRoute {
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
