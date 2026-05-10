//
//  MarkdownEditorPromptBlockMarkdown.swift
//

// Pure markdown helpers for Sceal prompt block directives.

enum MarkdownEditorPromptBlockMarkdown {
  static let startMarker = "<!-- prompt -->"
  static let endMarker = "<!-- /prompt -->"
  static let startBoundaryKind = "start"
  static let endBoundaryKind = "end"

  static var emptyBlock: String {
    "\(startMarker)\n\n\(endMarker)"
  }

  // Parses a persisted prompt boundary marker into the editor boundary kind.
  static func boundaryKind(for line: String) -> String? {
    if line == startMarker {
      return startBoundaryKind
    }
    if line == endMarker {
      return endBoundaryKind
    }
    return nil
  }

  // Builds the persisted prompt boundary marker for an editor boundary kind.
  static func marker(forBoundaryKind kind: String) -> String {
    kind == startBoundaryKind ? startMarker : endMarker
  }

  static func isStartBoundaryKind(_ kind: String) -> Bool {
    kind == startBoundaryKind
  }

  static func isEndBoundaryKind(_ kind: String) -> Bool {
    kind == endBoundaryKind
  }
}
