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
  // Recreates legacy insertion text, then turns only template-owned dividers into section boundaries.
  static func insert(
    _ request: StructuredTemplateInsertionRequest,
    replacing existingSection: StructuredNoteSection
  ) throws -> StructuredTemplateInsertionResult {
    let protectedLeading = protectLiteralDirectives(in: request.leadingMarkdown, namespace: "lead")
    let protectedTrailing = protectLiteralDirectives(
      in: request.trailingMarkdown, namespace: "tail")
    let markedTemplate = markFocusContent(
      in: request.template.resolvedBodyForInsertion,
      placement: request.template.cursorPlacement
    )
    let provenanceMarkers = provenanceMarkers(for: request)
    let templateMarkdown = preservingReplacedLineBreak(
      in: markedTemplate.markdown,
      when: request.preservesReplacedLineBreak
    )
    let combinedMarkdown =
      (provenanceMarkers.leading ?? "") + protectedLeading.markdown + templateMarkdown
      + protectedTrailing.markdown + (provenanceMarkers.trailing ?? "")
    var sections = LegacyMarkdownStructuredNoteAdapter.sections(
      from: combinedMarkdown,
      preservesLeadingEmptySection: request.template.startsWithDivider
    )
    let focusSectionIndex =
      request.template.cursorPlacement == .end
      ? sections.indices.last
      : sections.firstIndex { $0.markdown.contains(markedTemplate.focusMarker) }

    var existingFragmentIndices = Set<Int>()
    for index in sections.indices {
      sections[index].markdown = restoreProtectedDirectives(
        in: sections[index].markdown,
        replacements: protectedLeading.replacements + protectedTrailing.replacements
      )
      sections[index].markdown = sections[index].markdown.replacingOccurrences(
        of: markedTemplate.focusMarker,
        with: ""
      )
      sections[index].isCollapsed = false
      linkImportedMainColorRoles(in: &sections[index])
      if remove(provenanceMarkers.leading, from: &sections[index].markdown) {
        existingFragmentIndices.insert(index)
      }
      if remove(provenanceMarkers.trailing, from: &sections[index].markdown) {
        existingFragmentIndices.insert(index)
      }
    }

    guard !sections.isEmpty else {
      throw StructuredNoteDocumentError.emptySectionReplacement
    }

    let retainedIdentityIndex = existingFragmentIndices.min() ?? sections.startIndex
    sections[retainedIdentityIndex].id = existingSection.id
    for index in existingFragmentIndices {
      sections[index].styleOverrides = existingSection.styleOverrides
    }
    if existingFragmentIndices.isEmpty,
      sections[retainedIdentityIndex].styleOverrides == .inherited
    {
      sections[retainedIdentityIndex].styleOverrides = existingSection.styleOverrides
    }

    let focusSectionID =
      focusSectionIndex.flatMap { index in
        sections.indices.contains(index) ? sections[index].id : nil
      } ?? sections.last?.id ?? existingSection.id

    return StructuredTemplateInsertionResult(
      sections: sections,
      focusSectionID: focusSectionID
    )
  }

  private struct ProtectedMarkdown {
    let markdown: String
    let replacements: [(placeholder: String, directive: String)]
  }

  private struct MarkedTemplate {
    let markdown: String
    let focusMarker: String
  }

  private struct ProvenanceMarkers {
    let leading: String?
    let trailing: String?
  }

  // Marks existing content fragments so template colors cannot leak into them during parsing.
  private static func provenanceMarkers(
    for request: StructuredTemplateInsertionRequest
  ) -> ProvenanceMarkers {
    ProvenanceMarkers(
      leading: request.leadingMarkdown.isEmpty
        ? nil : "sceal-existing-leading-\(UUID().uuidString)",
      trailing: request.trailingMarkdown.isEmpty
        ? nil : "sceal-existing-trailing-\(UUID().uuidString)"
    )
  }

  // Removes an optional provenance marker and reports whether this section contained it.
  private static func remove(_ marker: String?, from markdown: inout String) -> Bool {
    guard let marker, markdown.contains(marker) else { return false }
    markdown = markdown.replacingOccurrences(of: marker, with: "")
    return true
  }

  // Hides section-looking rows already owned by the edited section from the template parser.
  private static func protectLiteralDirectives(
    in markdown: String,
    namespace: String
  ) -> ProtectedMarkdown {
    var replacements: [(placeholder: String, directive: String)] = []
    let lines = markdown.components(separatedBy: "\n").enumerated().map { index, line in
      guard MarkdownEditorSectionDirectiveMarkdown.parse(line) != nil else { return line }
      let placeholder = "<!-- sceal-preserved-\(namespace)-\(index) -->"
      replacements.append((placeholder, line))
      return placeholder
    }
    return ProtectedMarkdown(markdown: lines.joined(separator: "\n"), replacements: replacements)
  }

  private static func restoreProtectedDirectives(
    in markdown: String,
    replacements: [(placeholder: String, directive: String)]
  ) -> String {
    replacements.reduce(markdown) { result, replacement in
      result.replacingOccurrences(of: replacement.placeholder, with: replacement.directive)
    }
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
