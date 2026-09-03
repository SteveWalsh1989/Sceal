//
//  StructuredNoteTemplateAdapter.swift
//

// Converts a legacy Markdown template insertion into stable structured sections.

import Foundation

struct StructuredTemplateInsertionRequest: Equatable, Sendable {
  let leadingMarkdown: String
  let trailingMarkdown: String
  let template: NoteTemplate
  let preservesReplacedLineBreak: Bool
}

struct StructuredTemplateInsertionResult: Equatable, Sendable {
  let sections: [StructuredNoteSection]
  let focusSectionID: UUID
}

enum StructuredNoteTemplateAdapter {
  // Keeps existing content whole while turning only template-owned dividers into new sections.
  static func insert(
    _ request: StructuredTemplateInsertionRequest,
    replacing existingSection: StructuredNoteSection
  ) throws -> StructuredTemplateInsertionResult {
    let markedTemplate = markFocusContent(
      in: request.template.resolvedBodyForInsertion,
      placement: request.template.cursorPlacement
    )
    var templateSections = LegacyMarkdownStructuredNoteAdapter.sections(
      from: markedTemplate.markdown,
      preservesLeadingEmptySection: false
    )
    let focusTemplateIndex =
      request.template.cursorPlacement == .end
      ? templateSections.indices.last
      : templateSections.firstIndex { $0.markdown.contains(markedTemplate.focusMarker) }

    for index in templateSections.indices {
      templateSections[index].markdown = templateSections[index].markdown.replacingOccurrences(
        of: markedTemplate.focusMarker,
        with: ""
      )
      templateSections[index].isCollapsed = false
      linkImportedMainColorRoles(in: &templateSections[index])
    }

    guard !templateSections.isEmpty else {
      throw StructuredNoteDocumentError.emptySectionReplacement
    }

    var retainedSection = existingSection
    var insertedSections = templateSections
    let focusSectionID: UUID

    if request.template.startsWithDivider {
      retainedSection.markdown = request.leadingMarkdown + request.trailingMarkdown
      focusSectionID =
        focusTemplateIndex.flatMap { index in
          insertedSections.indices.contains(index) ? insertedSections[index].id : nil
        } ?? insertedSections.last?.id ?? retainedSection.id
    } else {
      let firstTemplateSection = insertedSections.removeFirst()
      retainedSection.markdown =
        request.leadingMarkdown
        + preservingReplacedLineBreak(
          in: firstTemplateSection.markdown,
          when: request.preservesReplacedLineBreak
        )
        + request.trailingMarkdown
      focusSectionID =
        focusTemplateIndex == templateSections.startIndex
        ? retainedSection.id
        : focusTemplateIndex.flatMap { index in
          let insertedIndex = index - 1
          return insertedSections.indices.contains(insertedIndex)
            ? insertedSections[insertedIndex].id
            : nil
        } ?? insertedSections.last?.id ?? retainedSection.id
    }

    return StructuredTemplateInsertionResult(
      sections: [retainedSection] + insertedSections,
      focusSectionID: focusSectionID
    )
  }

  private struct MarkedTemplate {
    let markdown: String
    let focusMarker: String
  }

  // Marks the section containing the configured cursor target without changing template whitespace.
  private static func markFocusContent(
    in markdown: String,
    placement: NoteTemplateCursorPlacement
  ) -> MarkedTemplate {
    let focusMarker = "sceal-template-focus-\(UUID().uuidString)"
    var lines = markdown.components(separatedBy: "\n")
    let contentIndices = lines.indices.filter { index in
      let line = lines[index]
      return !line.trimmingCharacters(in: .whitespaces).isEmpty
        && MarkdownEditorSectionDirectiveMarkdown.parse(line) == nil
    }

    let focusIndex: Int?
    switch placement {
    case .automatic:
      focusIndex =
        contentIndices.first(where: { isHeading(lines[$0], requiringColon: true) })
        ?? contentIndices.first(where: { isEmptyBullet(lines[$0]) })
        ?? contentIndices.last
    case .firstHeadingEnd:
      focusIndex =
        contentIndices.first(where: { isHeading(lines[$0], requiringColon: false) })
        ?? contentIndices.last
    case .firstEmptyBullet:
      focusIndex =
        contentIndices.first(where: { isEmptyBullet(lines[$0]) })
        ?? contentIndices.last
    case .end:
      focusIndex = contentIndices.last
    }

    if let focusIndex {
      lines[focusIndex] =
        placement == .end
        ? lines[focusIndex] + focusMarker
        : focusMarker + lines[focusIndex]
    } else {
      lines.append(focusMarker)
    }

    return MarkedTemplate(
      markdown: lines.joined(separator: "\n"),
      focusMarker: focusMarker
    )
  }

  private static func isHeading(_ line: String, requiringColon: Bool) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard trimmed.range(of: #"^#{1,6}\s+\S"#, options: .regularExpression) != nil else {
      return false
    }
    return !requiringColon || trimmed.hasSuffix(":")
  }

  private static func isEmptyBullet(_ line: String) -> Bool {
    line.trimmingCharacters(in: .whitespaces) == "-"
      || line.trimmingCharacters(in: .whitespaces) == "- "
  }

  private static func preservingReplacedLineBreak(in markdown: String, when enabled: Bool) -> String
  {
    guard enabled, !markdown.isEmpty, !markdown.hasSuffix("\n") else { return markdown }
    return markdown + "\n"
  }

  // Treats a template's single color as the structured section's linked visual color.
  private static func linkImportedMainColorRoles(in section: inout StructuredNoteSection) {
    let overrides = section.styleOverrides
    guard overrides.borderColor == .inherit,
      overrides.headingColor == overrides.bulletColor,
      case .colorName = overrides.headingColor
    else { return }
    section.styleOverrides.borderColor = overrides.headingColor
  }
}
