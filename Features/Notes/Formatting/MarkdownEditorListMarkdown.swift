//
//  MarkdownEditorListMarkdown.swift
//

// Pure markdown helpers for list markers and indentation.

import Foundation

struct MarkdownEditorListLine: Equatable, Sendable {
  let type: MarkdownListType
  let indentLevel: Int
  let content: String
  let displayText: String
  let orderedMarkerLength: Int?
}

enum MarkdownEditorListMarkdown {
  private static let bulletRegex = try! NSRegularExpression(
    pattern: #"^(?:-|\*|\+|•)\s+"#)
  private static let numberedRegex = try! NSRegularExpression(pattern: #"^\d+\.\s+"#)
  private static let numberedMarkerRegex = try! NSRegularExpression(pattern: #"^\d+\."#)

  // Parses supported markdown list markers without applying editor styling.
  static func parse(_ rawLine: String) -> MarkdownEditorListLine? {
    let indentedLine = splitIndent(from: rawLine)
    let trimmedLine = indentedLine.trimmedLine

    if trimmedLine.hasPrefix("- [x] ") {
      return MarkdownEditorListLine(
        type: .checkboxChecked,
        indentLevel: indentedLine.indentLevel,
        content: String(trimmedLine.dropFirst(6)),
        displayText: trimmedLine,
        orderedMarkerLength: nil
      )
    }

    if trimmedLine.hasPrefix("- [ ] ") {
      return MarkdownEditorListLine(
        type: .checkboxUnchecked,
        indentLevel: indentedLine.indentLevel,
        content: String(trimmedLine.dropFirst(6)),
        displayText: trimmedLine,
        orderedMarkerLength: nil
      )
    }

    if let markerRange = firstMatchRange(for: bulletRegex, in: trimmedLine) {
      return MarkdownEditorListLine(
        type: .bullet,
        indentLevel: indentedLine.indentLevel,
        content: String(trimmedLine[markerRange.upperBound...]),
        displayText: trimmedLine,
        orderedMarkerLength: nil
      )
    }

    if firstMatchRange(for: numberedRegex, in: trimmedLine) != nil {
      let markerLength = firstMatchRange(for: numberedMarkerRegex, in: trimmedLine)
        .map { trimmedLine.distance(from: $0.lowerBound, to: $0.upperBound) }
      return MarkdownEditorListLine(
        type: .numbered,
        indentLevel: indentedLine.indentLevel,
        content: trimmedLine,
        displayText: trimmedLine,
        orderedMarkerLength: markerLength
      )
    }

    return nil
  }

  // Removes markdown list indentation using the editor's existing indentation rules.
  static func lineWithoutIndent(_ rawLine: String) -> String {
    splitIndent(from: rawLine).trimmedLine
  }

  // Returns the persisted indentation prefix for a display list line.
  static func indentPrefix(for indentLevel: Int) -> String {
    indentLevel > 0 ? String(repeating: " ", count: indentLevel * 2) : ""
  }

  // Returns the persisted markdown marker prefix for display list content.
  static func persistedPrefix(for listType: MarkdownListType, indentLevel: Int) -> String? {
    let indentPrefix = indentPrefix(for: indentLevel)
    switch listType {
    case .bullet:
      return indentPrefix + "- "
    case .checkboxUnchecked:
      return indentPrefix + "- [ ] "
    case .checkboxChecked:
      return indentPrefix + "- [x] "
    case .numbered:
      return nil
    }
  }

  // Returns the UTF-16 start offset of list content in display text.
  static func displayContentStart(
    in lineText: String,
    listType: MarkdownListType,
    bulletMarker: String,
    uncheckedMarker: String,
    checkedMarker: String
  ) -> Int {
    switch listType {
    case .bullet:
      return lineText.hasPrefix("\(bulletMarker) ") ? 2 : 0
    case .checkboxUnchecked:
      return lineText.hasPrefix("\(uncheckedMarker) ") ? 2 : 0
    case .checkboxChecked:
      return lineText.hasPrefix("\(checkedMarker) ") ? 2 : 0
    case .numbered:
      return 0
    }
  }

  private static func splitIndent(from rawLine: String) -> (
    indentLevel: Int, trimmedLine: String
  ) {
    let leadingWhitespace = rawLine.prefix(while: { $0 == " " || $0 == "\t" })
    var tabLevel = 0
    for character in leadingWhitespace where character == "\t" {
      tabLevel += 1
    }
    let spaceCount = leadingWhitespace.filter { $0 == " " }.count
    let indentLevel = min(tabLevel + spaceCount / 2, 3)
    return (indentLevel, String(rawLine.dropFirst(leadingWhitespace.count)))
  }

  private static func firstMatchRange(
    for regex: NSRegularExpression,
    in line: String
  ) -> Range<String.Index>? {
    guard
      let match = regex.firstMatch(
        in: line,
        range: NSRange(location: 0, length: line.utf16.count)
      )
    else { return nil }

    return Range(match.range, in: line)
  }
}
