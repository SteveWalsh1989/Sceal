//
//  NewNoteDefault.swift
//

// Controls whether a new "today" note starts blank or copies the most recent previous note.
enum NewNoteDefault: String, Codable, CaseIterable, Sendable {
  case blank
  case copyPrevious

  var displayName: String {
    switch self {
    case .blank: return "Blank"
    case .copyPrevious: return "Copy previous"
    }
  }
}
