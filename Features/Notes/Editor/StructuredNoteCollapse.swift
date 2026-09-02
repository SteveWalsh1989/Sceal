//
//  StructuredNoteCollapse.swift
//

// Pure preview, visibility, and search-reveal rules for collapsed structured content.

import Foundation

nonisolated struct StructuredNoteSearchMatch: Equatable, Sendable {
  let sectionID: UUID
  let groupID: UUID?
}

nonisolated enum StructuredNoteCollapse {
  static let emptySectionPreview = "Empty section"

  // Uses the first Markdown heading when available, then the first visible content line.
  static func previewText(for markdown: String) -> String {
    let lines = markdown.components(separatedBy: .newlines)
    var firstContentLine: String?
    var activeFenceMarker: String?

    for line in lines {
      let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmedLine.isEmpty else { continue }

      if let fenceMarker = fenceMarker(for: trimmedLine) {
        if activeFenceMarker == fenceMarker {
          activeFenceMarker = nil
        } else if activeFenceMarker == nil {
          activeFenceMarker = fenceMarker
        }
        continue
      }
      let isInsideCodeFence = activeFenceMarker != nil
      guard isInsideCodeFence || !isMarkdownComment(trimmedLine) else { continue }

      if !isInsideCodeFence,
        let heading = headingText(in: trimmedLine),
        !heading.isEmpty
      {
        return heading
      }
      if firstContentLine == nil {
        let content = plainText(from: trimmedLine)
        if !content.isEmpty {
          firstContentLine = content
        }
      }
    }

    return firstContentLine ?? emptySectionPreview
  }

  // Returns only sections whose AppKit editors should participate in boundary navigation.
  static func editableSectionIDs(in document: StructuredNoteDocument) -> [UUID] {
    document.nodes.flatMap { node -> [UUID] in
      switch node {
      case .section(let section):
        return section.isCollapsed ? [] : [section.id]
      case .group(let group):
        guard !group.isCollapsed else { return [] }
        return group.sections.compactMap { section in
          section.isCollapsed ? nil : section.id
        }
      }
    }
  }

  // Expands the first section-content match and its containing group without altering siblings.
  @discardableResult
  static func revealFirstSearchMatch(
    for searchText: String,
    in document: inout StructuredNoteDocument
  ) -> StructuredNoteSearchMatch? {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return nil }

    for nodeIndex in document.nodes.indices {
      switch document.nodes[nodeIndex] {
      case .section(var section):
        guard section.markdown.localizedCaseInsensitiveContains(query) else { continue }
        section.isCollapsed = false
        document.nodes[nodeIndex] = .section(section)
        return StructuredNoteSearchMatch(sectionID: section.id, groupID: nil)

      case .group(var group):
        guard
          let sectionIndex = group.sections.firstIndex(where: {
            $0.markdown.localizedCaseInsensitiveContains(query)
          })
        else { continue }
        group.isCollapsed = false
        group.sections[sectionIndex].isCollapsed = false
        document.nodes[nodeIndex] = .group(group)
        return StructuredNoteSearchMatch(
          sectionID: group.sections[sectionIndex].id,
          groupID: group.id
        )
      }
    }

    return nil
  }

  // Recognizes fenced blocks so their contents do not become collapsed-card previews.
  private static func fenceMarker(for line: String) -> String? {
    if line.hasPrefix("```") {
      return "```"
    }
    if line.hasPrefix("~~~") {
      return "~~~"
    }
    return nil
  }

  private static func isMarkdownComment(_ line: String) -> Bool {
    line.hasPrefix("<!--") || line.hasSuffix("-->")
  }

  // Extracts ATX heading text without treating ordinary leading hashes as headings.
  private static func headingText(in line: String) -> String? {
    let hashCount = line.prefix(while: { $0 == "#" }).count
    guard (1...6).contains(hashCount) else { return nil }
    let markerEnd = line.index(line.startIndex, offsetBy: hashCount)
    guard markerEnd < line.endIndex, line[markerEnd].isWhitespace else { return nil }
    return plainText(from: String(line[markerEnd...]))
  }

  // Removes common block and inline Markdown markers while preserving readable words.
  private static func plainText(from line: String) -> String {
    var text = line.trimmingCharacters(in: .whitespacesAndNewlines)
    text = removingBlockPrefix(from: text)
    text = removingLinkDestinations(from: text)

    for marker in ["**", "__", "~~", "`", "*", "_", "[", "]"] {
      text = text.replacingOccurrences(of: marker, with: "")
    }
    return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }

  private static func removingBlockPrefix(from line: String) -> String {
    var text = line.trimmingCharacters(in: .whitespaces)
    while text.hasPrefix(">") {
      text.removeFirst()
      text = text.trimmingCharacters(in: .whitespaces)
    }

    if ["- ", "* ", "+ "].contains(where: text.hasPrefix) {
      text.removeFirst(2)
    } else if let markerEnd = orderedListMarkerEnd(in: text) {
      text = String(text[markerEnd...])
    }

    let lowercaseText = text.lowercased()
    if lowercaseText.hasPrefix("[ ] ") || lowercaseText.hasPrefix("[x] ") {
      text.removeFirst(4)
    }
    return text.trimmingCharacters(in: .whitespaces)
  }

  private static func orderedListMarkerEnd(in text: String) -> String.Index? {
    let digitsEnd = text.prefix(while: \.isNumber).endIndex
    guard digitsEnd > text.startIndex, digitsEnd < text.endIndex else { return nil }
    let marker = text[digitsEnd]
    guard marker == "." || marker == ")" else { return nil }
    let spaceIndex = text.index(after: digitsEnd)
    guard spaceIndex < text.endIndex, text[spaceIndex].isWhitespace else { return nil }
    return text.index(after: spaceIndex)
  }

  // Keeps link labels and image alt text but removes their destination URLs.
  private static func removingLinkDestinations(from line: String) -> String {
    var text = line
    while let labelEnd = text.range(of: "]("),
      let destinationEnd = text[labelEnd.upperBound...].firstIndex(of: ")")
    {
      text.removeSubrange(labelEnd.lowerBound...destinationEnd)
    }
    return text.replacingOccurrences(of: "![", with: "[")
  }
}
