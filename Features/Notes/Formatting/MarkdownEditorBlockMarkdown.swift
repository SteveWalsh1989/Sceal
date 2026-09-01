//
//  MarkdownEditorBlockMarkdown.swift
//

// Pure markdown helpers for standard block-level markers.

import Foundation

struct MarkdownEditorHeadingLine: Equatable, Sendable {
  let level: Int
  let content: String
}

struct MarkdownEditorBlockquoteLine: Equatable, Sendable {
  let content: String
}

enum MarkdownEditorBlockMarkdown {
  static let horizontalRuleMarker = "---"
  static let blockquotePrefix = "> "

  private static let headingRegex = try! NSRegularExpression(pattern: #"^(#{1,3})\s+"#)
  private static let horizontalRuleRegex = try! NSRegularExpression(pattern: #"^-{3,}$"#)

  // Parses heading markers supported by the editor display formatter.
  static func parseHeading(_ line: String) -> MarkdownEditorHeadingLine? {
    guard
      let match = headingRegex.firstMatch(
        in: line,
        range: NSRange(location: 0, length: line.utf16.count)
      ),
      let markerRange = Range(match.range(at: 1), in: line),
      let fullRange = Range(match.range(at: 0), in: line)
    else { return nil }

    return MarkdownEditorHeadingLine(
      level: line[markerRange].count,
      content: String(line[fullRange.upperBound...])
    )
  }

  // Parses single-level blockquote markers supported by the editor.
  static func parseBlockquote(_ line: String) -> MarkdownEditorBlockquoteLine? {
    guard line.hasPrefix(blockquotePrefix) else { return nil }
    return MarkdownEditorBlockquoteLine(content: String(line.dropFirst(blockquotePrefix.count)))
  }

  // Detects code fences using the editor's existing permissive prefix rule.
  nonisolated static func isCodeFence(_ line: String) -> Bool {
    line.hasPrefix("```")
  }

  // Detects the horizontal rule shape rendered as a visible editor divider.
  static func isHorizontalRule(_ line: String) -> Bool {
    horizontalRuleRegex.firstMatch(
      in: line,
      range: NSRange(location: 0, length: line.utf16.count)
    ) != nil
  }

  // Builds the persisted heading marker prefix for a supported heading level.
  static func headingPrefix(for level: Int) -> String {
    String(repeating: "#", count: level) + " "
  }
}
