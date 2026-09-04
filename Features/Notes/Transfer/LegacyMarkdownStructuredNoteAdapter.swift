//
//  LegacyMarkdownStructuredNoteAdapter.swift
//

// Converts existing Scéal markdown notes into isolated structured documents.

import Foundation

nonisolated enum LegacyMarkdownStructuredNoteAdapter {
  // Converts an already decoded compatibility note into the structured domain.
  static func importDocument(_ note: DayNote) throws -> StructuredNoteDocument {
    do {
      let document = StructuredNoteDocument(
        id: note.id,
        date: note.date,
        title: note.title,
        tags: note.tags,
        nodes: sections(from: note.body).map(StructuredNoteNode.section)
      )
      try document.validate()
      return document
    } catch {
      throw LegacyMarkdownStructuredNoteAdapterError.invalidNote(
        note.id,
        reason: error.localizedDescription
      )
    }
  }

  // Decodes one legacy note and adds source-specific context to any import failure.
  static func importDocument(
    contents: String,
    sourceURL: URL,
    idOverride: String? = nil
  ) throws -> StructuredNoteDocument {
    do {
      let note = try MarkdownNoteCodec.decode(
        contents: contents,
        sourceURL: sourceURL,
        idOverride: idOverride
      )
      return try importDocument(note)
    } catch {
      throw LegacyMarkdownStructuredNoteAdapterError.invalidSource(
        sourceURL,
        reason: error.localizedDescription
      )
    }
  }

  // Splits only active section directives while preserving protected Markdown blocks verbatim.
  static func sections(
    from body: String,
    preservesLeadingEmptySection: Bool = false
  ) -> [StructuredNoteSection] {
    let lines = body.components(separatedBy: "\n")
    var sections: [StructuredNoteSection] = []
    var sectionLines: [String] = []
    var currentStyleOverrides = StructuredSectionStyleOverrides.inherited
    var insideCodeBlock = false
    var insidePromptBlock = false
    var protectedTableEndIndex: Int?
    var hasSeenSectionDirective = false

    for (lineIndex, line) in lines.enumerated() {
      if let tableEndIndex = protectedTableEndIndex {
        sectionLines.append(line)
        if lineIndex == tableEndIndex {
          protectedTableEndIndex = nil
        }
        continue
      }

      if insidePromptBlock {
        sectionLines.append(line)
        if MarkdownEditorPromptBlockMarkdown.boundaryKind(for: line)
          == MarkdownEditorPromptBlockMarkdown.endBoundaryKind
        {
          insidePromptBlock = false
        }
        continue
      }

      if !insideCodeBlock,
        MarkdownEditorPromptBlockMarkdown.boundaryKind(for: line)
          == MarkdownEditorPromptBlockMarkdown.startBoundaryKind
      {
        insidePromptBlock = true
        sectionLines.append(line)
        continue
      }

      if MarkdownEditorBlockMarkdown.isCodeFence(line) {
        insideCodeBlock.toggle()
        sectionLines.append(line)
        continue
      }

      if insideCodeBlock {
        sectionLines.append(line)
        continue
      }

      if let tableEndIndex = validTableEndIndex(startingAt: lineIndex, in: lines) {
        protectedTableEndIndex = tableEndIndex
        sectionLines.append(line)
        continue
      }

      if let directive = MarkdownEditorSectionDirectiveMarkdown.parse(line) {
        let hasContentBeforeFirstDirective = sectionLines.contains {
          !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if preservesLeadingEmptySection || hasSeenSectionDirective || hasContentBeforeFirstDirective
        {
          sections.append(
            StructuredNoteSection(
              markdown: sectionLines.joined(separator: "\n"),
              styleOverrides: currentStyleOverrides
            )
          )
        }
        sectionLines.removeAll(keepingCapacity: true)
        currentStyleOverrides = styleOverrides(for: directive)
        hasSeenSectionDirective = true
        continue
      }

      sectionLines.append(line)
    }

    sections.append(
      StructuredNoteSection(
        markdown: sectionLines.joined(separator: "\n"),
        styleOverrides: currentStyleOverrides
      )
    )
    return sections
  }

  // Protects complete table marker blocks from section-boundary detection.
  private static func validTableEndIndex(startingAt startIndex: Int, in lines: [String]) -> Int? {
    guard lines.indices.contains(startIndex),
      MarkdownEditorTableMarkdown.isStartLine(lines[startIndex])
    else { return nil }

    for endIndex in lines.indices where endIndex > startIndex {
      guard MarkdownEditorTableMarkdown.isEndLine(lines[endIndex]) else { continue }
      return endIndex
    }

    return nil
  }

  // Converts the legacy same-color flag into independent effective heading and bullet overrides.
  private static func styleOverrides(
    for directive: MarkdownEditorSectionDirective
  ) -> StructuredSectionStyleOverrides {
    guard directive.headingColorName != nil || directive.bulletColorName != nil else {
      return .inherited
    }

    let bulletColorName =
      directive.usesSectionColor
      ? directive.headingColorName ?? directive.bulletColorName
      : directive.bulletColorName

    return StructuredSectionStyleOverrides(
      headingColor: colorOverride(named: directive.headingColorName),
      bulletColor: colorOverride(named: bulletColorName)
    )
  }

  // Maps a missing legacy color to inheritance and a stored token to an explicit override.
  private static func colorOverride(named colorName: String?) -> StructuredColorOverride {
    colorName.map(StructuredColorOverride.colorName) ?? .inherit
  }
}

nonisolated enum LegacyMarkdownStructuredNoteAdapterError: LocalizedError, Equatable, Sendable {
  case invalidSource(URL, reason: String)
  case invalidNote(String, reason: String)

  var errorDescription: String? {
    switch self {
    case .invalidSource(let sourceURL, let reason):
      return "Scéal could not import \(sourceURL.lastPathComponent). \(reason)"
    case .invalidNote(let noteID, let reason):
      return "Scéal could not convert note \(noteID). \(reason)"
    }
  }
}
