//
//  StructuredNoteMarkdownExporter.swift
//

// Flattens structured documents into portable Markdown in visible content order.

import Foundation

nonisolated enum StructuredNoteMarkdownExporter {
  // Encodes a validated structured document as a complete Markdown note file.
  static func export(_ document: StructuredNoteDocument) throws -> String {
    try MarkdownNoteCodec.encode(dayNote(for: document))
  }

  // Produces the legacy transfer value used by the existing portable zip exporter.
  static func dayNote(for document: StructuredNoteDocument) throws -> DayNote {
    try document.validate()
    return DayNote(
      date: document.date,
      id: document.id,
      title: document.title,
      tags: document.tags,
      body: try body(for: document)
    )
  }

  // Flattens sections and groups while omitting structured-only appearance and collapse state.
  static func body(for document: StructuredNoteDocument) throws -> String {
    try document.validate()
    var blocks: [String] = []

    for node in document.nodes {
      switch node {
      case .section(let section):
        blocks.append(section.markdown)

      case .group(let group):
        blocks.append(groupHeading(for: group.title))
        blocks.append(contentsOf: group.sections.map(\.markdown))
      }
    }

    return joinMarkdownBlocks(blocks)
  }

  // Emits the agreed portable representation of a semantic group title.
  private static func groupHeading(for title: String) -> String {
    let singleLineTitle =
      title
      .split(whereSeparator: \.isNewline)
      .joined(separator: " ")
    return "## \(singleLineTitle)"
  }

  // Preserves existing boundary whitespace while ensuring adjacent content remains readable.
  private static func joinMarkdownBlocks(_ blocks: [String]) -> String {
    var result = ""

    for block in blocks where !block.isEmpty {
      guard !result.isEmpty else {
        result = block
        continue
      }

      let existingBoundary = trailingNewlineCount(in: result) + leadingNewlineCount(in: block)
      if existingBoundary < 2 {
        result += String(repeating: "\n", count: 2 - existingBoundary)
      }
      result += block
    }

    return result
  }

  // Counts leading line breaks without changing section-owned whitespace.
  private static func leadingNewlineCount(in value: String) -> Int {
    value.prefix(while: { $0 == "\n" }).count
  }

  // Counts trailing line breaks without changing section-owned whitespace.
  private static func trailingNewlineCount(in value: String) -> Int {
    value.reversed().prefix(while: { $0 == "\n" }).count
  }
}
