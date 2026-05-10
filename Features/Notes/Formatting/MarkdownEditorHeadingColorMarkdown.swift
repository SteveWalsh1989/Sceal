//
//  MarkdownEditorHeadingColorMarkdown.swift
//

// Pure markdown helpers for Sceal heading color directives.

import Foundation

enum MarkdownEditorHeadingColorMarkdown {
  private static let headingColorRegex = try! NSRegularExpression(
    pattern: #"^<!-- hcolor:(\w+) -->$"#)

  // Parses a persisted heading color marker into its color name.
  static func parseColorName(_ line: String) -> String? {
    guard
      let match = headingColorRegex.firstMatch(
        in: line,
        range: NSRange(location: 0, length: line.utf16.count)
      ),
      let colorRange = Range(match.range(at: 1), in: line)
    else { return nil }

    return String(line[colorRange])
  }

  // Builds the canonical persisted heading color marker.
  static func marker(colorName: String) -> String {
    "<!-- hcolor:\(colorName) -->"
  }
}
