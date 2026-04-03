//
//  NewNoteDefault.swift
//

// Controls whether new daily notes start blank or copy the previous note.

// Controls whether a new "today" note starts blank or copies the most recent previous note.
enum NewNoteDefault: String, Codable, CaseIterable, Sendable {
  case blank
  case copyPrevious

  // User-facing label for the settings UI.
  var displayName: String {
    switch self {
    case .blank: return "Blank"
    case .copyPrevious: return "Copy previous"
    }
  }
}
