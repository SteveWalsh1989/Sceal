//
//  NewNoteDefault.swift
//

// Controls whether a new "today" note starts blank, copies the previous note, or uses a template.
enum NewNoteDefault: Codable, Equatable, Hashable, RawRepresentable, Sendable {
  case blank
  case copyPrevious
  case template(NoteTemplate.ID)

  static let builtInCases: [NewNoteDefault] = [.blank, .copyPrevious]

  init?(rawValue: String) {
    if rawValue == "blank" {
      self = .blank
    } else if rawValue == "copyPrevious" {
      self = .copyPrevious
    } else if rawValue.hasPrefix("template:") {
      let templateID = String(rawValue.dropFirst("template:".count))
      guard !templateID.isEmpty else { return nil }
      self = .template(templateID)
    } else {
      return nil
    }
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let rawValue = try container.decode(String.self)
    self = NewNoteDefault(rawValue: rawValue) ?? .blank
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  var rawValue: String {
    switch self {
    case .blank: return "blank"
    case .copyPrevious: return "copyPrevious"
    case .template(let templateID): return "template:\(templateID)"
    }
  }

  // User-facing label for the settings UI.
  var displayName: String {
    switch self {
    case .blank: return "Blank"
    case .copyPrevious: return "Copy previous"
    case .template: return "Template"
    }
  }
}
