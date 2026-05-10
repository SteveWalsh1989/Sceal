//
//  MarkdownEditorImageMarkdown.swift
//

// Pure markdown helpers for Scéal image blocks and image width markers.

import Foundation

enum MarkdownEditorImageMarkdown {
  static let defaultWidth: CGFloat = 420
  static let minimumWidth: CGFloat = 160
  static let maximumWidth: CGFloat = 760
  static let resizeStep: CGFloat = 80

  private static let widthRegex = try! NSRegularExpression(
    pattern: #"^<!-- sceal-image-width:([0-9]+(?:\.[0-9]+)?) -->$"#)
  private static let imageRegex = try! NSRegularExpression(
    pattern: #"^!\[([^\]]*)\]\(([^)\s]+)(?:\s+"([^"]*)")?\)$"#)

  // Keeps persisted image width markers inside the supported editor range.
  static func clampedWidth(_ width: CGFloat) -> CGFloat {
    min(max(width, minimumWidth), maximumWidth)
  }

  // Parses a Scéal image width marker and clamps it to the supported editor range.
  static func parseWidthMarker(_ line: String) -> CGFloat? {
    guard
      let match = widthRegex.firstMatch(
        in: line,
        range: NSRange(location: 0, length: line.utf16.count)
      ),
      let widthRange = Range(match.range(at: 1), in: line),
      let width = Double(line[widthRange])
    else { return nil }

    return clampedWidth(CGFloat(width))
  }

  // Parses markdown image syntax into the stored image title and relative path.
  static func parseImage(_ line: String) -> (title: String, path: String)? {
    guard
      let match = imageRegex.firstMatch(
        in: line,
        range: NSRange(location: 0, length: line.utf16.count)
      ),
      let titleRange = Range(match.range(at: 1), in: line),
      let pathRange = Range(match.range(at: 2), in: line)
    else { return nil }

    return (
      title: unescapedText(String(line[titleRange])),
      path: String(line[pathRange])
    )
  }

  // Builds the canonical width marker persisted before resized image blocks.
  static func widthMarker(for width: CGFloat) -> String {
    "<!-- sceal-image-width:\(Int(clampedWidth(width).rounded())) -->"
  }

  // Builds the canonical markdown image line used for persistence.
  static func imageLine(title: String, path: String) -> String {
    "![\(escapedText(title))](\(path))"
  }

  // Coerces width attributes emitted by AppKit/Swift into CGFloat for persistence.
  static func widthValue(from value: Any?) -> CGFloat? {
    if let width = value as? CGFloat {
      return width
    }
    if let number = value as? NSNumber {
      return CGFloat(truncating: number)
    }
    return nil
  }

  private static func escapedText(_ text: String) -> String {
    text
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "]", with: "\\]")
  }

  private static func unescapedText(_ text: String) -> String {
    text
      .replacingOccurrences(of: "\\]", with: "]")
      .replacingOccurrences(of: "\\\\", with: "\\")
  }
}
