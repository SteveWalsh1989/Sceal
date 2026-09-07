import XCTest

@testable import Sceal

@MainActor
final class StructuredNoteTemplateAdapterTests: XCTestCase {
  // Converts template dividers to stable sections without consuming literal markers around them.
  func testTemplateInsertionCreatesSectionsAndPreservesExistingLiteralDirectives() throws {
    let existingSection = StructuredNoteSection(
      markdown: "Before",
      styleOverrides: StructuredSectionStyleOverrides(headingColor: .colorName("blue"))
    )
    let template = NoteTemplate(
      title: "Feature",
      command: "feature",
      body: "# Feature\n\n- Item",
      cursorPlacement: .firstHeadingEnd,
      sectionColorName: "purple",
      createsNewSection: true
    )

    let result = try StructuredNoteTemplateAdapter.insert(
      StructuredTemplateInsertionRequest(
        leadingMarkdown: "Before\n<!-- section -->\nLiteral\n",
        trailingMarkdown: "After",
        template: template,
        preservesReplacedLineBreak: true
      ),
      replacing: existingSection
    )

    XCTAssertEqual(result.sections.count, 2)
    XCTAssertEqual(result.sections[0].id, existingSection.id)
    XCTAssertEqual(result.sections[0].markdown, "Before\n<!-- section -->\nLiteral\nAfter")
    XCTAssertEqual(result.sections[0].styleOverrides, existingSection.styleOverrides)
    XCTAssertEqual(result.sections[1].markdown, "# Feature\n\n- Item")
    XCTAssertEqual(result.sections[1].styleOverrides.headingColor, .colorName("purple"))
    XCTAssertEqual(result.sections[1].styleOverrides.borderColor, .colorName("purple"))
    XCTAssertEqual(result.sections[1].styleOverrides.bulletColor, .colorName("purple"))
    XCTAssertEqual(result.focusSectionID, result.sections[1].id)
    XCTAssertFalse(
      result.sections.contains(where: { $0.markdown.contains("sceal-template-focus") }))
  }

  // Keeps text after a new-section template command in the current section instead of splitting it.
  func testNewSectionTemplateAppendsOnlyItsRequestedSections() throws {
    let existingSection = StructuredNoteSection(markdown: "Before\n/feature\nAfter")
    let template = NoteTemplate(
      title: "Feature",
      command: "feature",
      body: "# Feature",
      createsNewSection: true
    )

    let result = try StructuredNoteTemplateAdapter.insert(
      StructuredTemplateInsertionRequest(
        leadingMarkdown: "Before\n",
        trailingMarkdown: "After",
        template: template,
        preservesReplacedLineBreak: true
      ),
      replacing: existingSection
    )

    XCTAssertEqual(result.sections.map(\.markdown), ["Before\nAfter", "# Feature"])
    XCTAssertEqual(result.sections.first?.id, existingSection.id)
    XCTAssertEqual(result.focusSectionID, result.sections.last?.id)
  }

  // A template color styles the retained section when insertion does not create a sibling.
  func testInlineTemplateAppliesItsConfiguredSectionColor() throws {
    let existingSection = StructuredNoteSection(markdown: "/plan")
    let template = NoteTemplate(
      title: "Plan",
      command: "plan",
      body: "# Plan\n\n- ",
      sectionColorName: "blue"
    )

    let result = try StructuredNoteTemplateAdapter.insert(
      StructuredTemplateInsertionRequest(
        leadingMarkdown: "",
        trailingMarkdown: "",
        template: template,
        preservesReplacedLineBreak: false
      ),
      replacing: existingSection
    )

    let section = try XCTUnwrap(result.sections.first)
    XCTAssertEqual(section.id, existingSection.id)
    XCTAssertEqual(section.markdown, "# Plan\n\n- ")
    XCTAssertEqual(section.styleOverrides.effectiveColorOverride(for: .heading), .colorName("blue"))
    XCTAssertEqual(section.styleOverrides.effectiveColorOverride(for: .border), .colorName("blue"))
    XCTAssertEqual(section.styleOverrides.effectiveColorOverride(for: .bullet), .colorName("blue"))
  }

  // Replaces a grouped section with multiple children without promoting them to the document root.
  func testDocumentReplacementKeepsTemplateSectionsInsideCurrentGroup() throws {
    let existingSection = StructuredNoteSection(markdown: "Command")
    let group = StructuredSectionGroup(title: "Feature", sections: [existingSection])
    var document = StructuredNoteDocument(
      id: "2026-09-02",
      date: Date(timeIntervalSince1970: 1_788_307_200),
      title: "",
      tags: [],
      nodes: [.group(group)]
    )
    let replacements = [
      StructuredNoteSection(id: existingSection.id, markdown: "First"),
      StructuredNoteSection(markdown: "Second"),
    ]

    try document.replaceSection(id: existingSection.id, with: replacements)

    guard case .group(let updatedGroup) = document.nodes.first else {
      return XCTFail("Expected the template sections to remain grouped.")
    }
    XCTAssertEqual(updatedGroup.id, group.id)
    XCTAssertEqual(updatedGroup.sections, replacements)
  }

  // Targets cursor placement inside the correct generated section across template dividers.
  func testCursorPlacementSelectsTheMatchingTemplateSection() throws {
    let existingSection = StructuredNoteSection()
    let bulletTemplate = NoteTemplate(
      title: "Split cursor",
      command: "split-cursor",
      body: "# Heading\n<!-- section -->\n- ",
      cursorPlacement: .firstEmptyBullet
    )
    let bulletResult = try StructuredNoteTemplateAdapter.insert(
      StructuredTemplateInsertionRequest(
        leadingMarkdown: "",
        trailingMarkdown: "",
        template: bulletTemplate,
        preservesReplacedLineBreak: false
      ),
      replacing: existingSection
    )

    XCTAssertEqual(bulletResult.sections.count, 2)
    XCTAssertEqual(bulletResult.focusSectionID, bulletResult.sections[1].id)

    var newSectionTemplate = bulletTemplate
    newSectionTemplate.cursorPlacement = .end
    newSectionTemplate.createsNewSection = true
    let newSectionResult = try StructuredNoteTemplateAdapter.insert(
      StructuredTemplateInsertionRequest(
        leadingMarkdown: "",
        trailingMarkdown: "",
        template: newSectionTemplate,
        preservesReplacedLineBreak: false
      ),
      replacing: existingSection
    )

    XCTAssertEqual(newSectionResult.sections.count, 2)
    XCTAssertEqual(newSectionResult.focusSectionID, newSectionResult.sections.last?.id)
    XCTAssertEqual(newSectionResult.sections.last?.markdown, "- ")
  }
}
