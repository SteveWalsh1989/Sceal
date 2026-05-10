//
//  MarkdownEditorSectionDirective.swift
//

// Pure markdown helpers for Sceal section divider directives.

import Foundation

struct MarkdownEditorSectionDirective: Equatable, Sendable {
  let headingColorName: String?
  let bulletColorName: String?
  let usesSectionColor: Bool

  init(
    headingColorName: String? = nil,
    bulletColorName: String? = nil,
    usesSectionColor: Bool = false
  ) {
    self.headingColorName = headingColorName
    self.bulletColorName = bulletColorName
    self.usesSectionColor = usesSectionColor
  }

  var useSectionColorAttributeValue: Bool? {
    headingColorName != nil || bulletColorName != nil ? usesSectionColor : nil
  }
}

enum MarkdownEditorSectionDirectiveMarkdown {
  private static let sectionRegex = try! NSRegularExpression(
    pattern:
      #"^<!-- section(?:\s+heading:(\w+))?(?:\s+bullet:(\w+))?(?:\s+usesectioncolor:(true|false))? -->$"#
  )

  // Parses a persisted section divider directive into its optional color settings.
  static func parse(_ line: String) -> MarkdownEditorSectionDirective? {
    guard
      let match = sectionRegex.firstMatch(
        in: line,
        range: NSRange(location: 0, length: line.utf16.count)
      )
    else { return nil }

    let headingColorName = capturedGroup(match, index: 1, in: line)
    let bulletColorName = capturedGroup(match, index: 2, in: line)
    let explicitUseSectionColor = capturedGroup(match, index: 3, in: line)
    let hasColor = headingColorName != nil || bulletColorName != nil

    return MarkdownEditorSectionDirective(
      headingColorName: headingColorName,
      bulletColorName: bulletColorName,
      usesSectionColor: explicitUseSectionColor.map { $0 == "true" } ?? hasColor
    )
  }

  // Builds the canonical persisted section divider directive.
  static func marker(for directive: MarkdownEditorSectionDirective) -> String {
    marker(
      headingColorName: directive.headingColorName,
      bulletColorName: directive.bulletColorName,
      usesSectionColor: directive.usesSectionColor
    )
  }

  // Builds a section divider directive from individual optional color settings.
  static func marker(
    headingColorName: String?,
    bulletColorName: String?,
    usesSectionColor: Bool
  ) -> String {
    var parts = ["section"]
    if let headingColorName {
      parts.append("heading:\(headingColorName)")
    }
    if let bulletColorName {
      parts.append("bullet:\(bulletColorName)")
    }
    let hasColor = headingColorName != nil || bulletColorName != nil
    if usesSectionColor, hasColor {
      parts.append("usesectioncolor:true")
    } else if !usesSectionColor, hasColor {
      parts.append("usesectioncolor:false")
    }
    return "<!-- \(parts.joined(separator: " ")) -->"
  }

  private static func capturedGroup(
    _ match: NSTextCheckingResult,
    index: Int,
    in line: String
  ) -> String? {
    guard
      match.range(at: index).location != NSNotFound,
      let range = Range(match.range(at: index), in: line)
    else { return nil }

    return String(line[range])
  }
}
