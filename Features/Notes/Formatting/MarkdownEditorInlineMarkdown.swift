//
//  MarkdownEditorInlineMarkdown.swift
//

// Pure markdown helpers for inline delimiters and span serialization.

import Foundation

enum MarkdownEditorInlineMarkdown {
  static let boldRegex = try! NSRegularExpression(pattern: #"\*\*(.+?)\*\*"#)
  static let italicRegex = try! NSRegularExpression(
    pattern: #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#)
  static let strikethroughRegex = try! NSRegularExpression(pattern: #"~~(.+?)~~"#)
  static let inlineCodeRegex = try! NSRegularExpression(pattern: #"`([^`]+)`"#)
  static let linkRegex = try! NSRegularExpression(
    pattern: #"\[([^\]]+)\]\(([^\)]+)\)"#)
  static let urlDetector = try? NSDataDetector(
    types: NSTextCheckingResult.CheckingType.link.rawValue)

  // Serializes one attributed inline span back to the markdown shape the editor supports.
  static func serializedSpan(
    text: String,
    isBold: Bool,
    isItalic: Bool,
    isStrikethrough: Bool,
    isCode: Bool,
    linkURL: String?
  ) -> String {
    let inner: String
    if isCode {
      inner = "`\(text)`"
    } else if isBold && isItalic, let url = linkURL {
      inner = "***[\(text)](\(url))***"
    } else if isBold && isItalic {
      inner = "***\(text)***"
    } else if isBold, let url = linkURL {
      inner = "**[\(text)](\(url))**"
    } else if isBold {
      inner = "**\(text)**"
    } else if isItalic, let url = linkURL {
      inner = "*[\(text)](\(url))*"
    } else if isItalic {
      inner = "*\(text)*"
    } else if let url = linkURL {
      inner = "[\(text)](\(url))"
    } else {
      inner = text
    }

    if isStrikethrough {
      return "~~\(inner)~~"
    }
    return inner
  }
}
