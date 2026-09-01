import Foundation
import XCTest

@testable import Sceal

final class StructuredNoteDocumentTests: XCTestCase {
  // Prevents a new structured note from starting without an editable root section.
  func testEmptyDocumentCreatesOneValidRootSection() throws {
    let document = StructuredNoteDocument.empty(id: "2026-09-01", date: makeDate())

    try document.validate()
    XCTAssertEqual(document.nodes.count, 1)
    XCTAssertNotNil(rootSection(in: document, at: 0))
  }

  // Prevents section IDs from being reused across root and grouped content.
  func testValidationRejectsDuplicateNodeIDs() {
    let sectionID = UUID()
    let document = makeDocument(
      nodes: [
        .section(StructuredNoteSection(id: sectionID, markdown: "Root")),
        .group(
          StructuredSectionGroup(
            title: "Feature",
            sections: [StructuredNoteSection(id: sectionID, markdown: "Grouped")]
          )
        ),
      ]
    )

    XCTAssertThrowsError(try document.validate()) { error in
      XCTAssertEqual(error as? StructuredNoteDocumentError, .duplicateNodeID(sectionID))
    }
  }

  // Prevents persisted groups from losing either their semantic title or all child sections.
  func testValidationRejectsEmptyGroupsAndTitles() {
    let emptyGroup = StructuredSectionGroup(title: "Feature", sections: [])
    let untitledGroup = StructuredSectionGroup(
      title: "  ",
      sections: [StructuredNoteSection(markdown: "Content")]
    )

    XCTAssertThrowsError(try makeDocument(nodes: [.group(emptyGroup)]).validate()) { error in
      XCTAssertEqual(error as? StructuredNoteDocumentError, .emptyGroup(emptyGroup.id))
    }
    XCTAssertThrowsError(try makeDocument(nodes: [.group(untitledGroup)]).validate()) { error in
      XCTAssertEqual(error as? StructuredNoteDocumentError, .emptyGroupTitle(untitledGroup.id))
    }
  }

  // Keeps explicit section colors above group values while allowing theme-default opt-out.
  func testStyleResolutionUsesSectionThenGroupThenThemePrecedence() {
    let groupStyle = StructuredSectionStyle(
      backgroundColorName: "group-background",
      borderColorName: "group-border",
      headingColorName: "group-heading",
      bulletColorName: nil
    )
    let themeStyle = StructuredSectionStyle(
      backgroundColorName: "theme-background",
      borderColorName: "theme-border",
      headingColorName: "theme-heading",
      bulletColorName: "theme-bullet"
    )
    let section = StructuredNoteSection(
      styleOverrides: StructuredSectionStyleOverrides(
        backgroundColor: .colorName("section-background"),
        borderColor: .themeDefault,
        headingColor: .inherit,
        bulletColor: .inherit
      )
    )

    let resolved = section.resolvedStyle(groupStyle: groupStyle, themeStyle: themeStyle)

    XCTAssertEqual(resolved.backgroundColorName, "section-background")
    XCTAssertEqual(resolved.borderColorName, "theme-border")
    XCTAssertEqual(resolved.headingColorName, "group-heading")
    XCTAssertEqual(resolved.bulletColorName, "theme-bullet")
  }

  // Ensures `/div` can split Unicode markdown using TextKit's UTF-16 caret offsets.
  func testSplitSectionUsesUTF16OffsetAndCreatesFollowingRootSection() throws {
    let section = StructuredNoteSection(markdown: "Before 🌍 after")
    var document = makeDocument(nodes: [.section(section)])
    let splitOffset = (section.markdown as NSString).range(of: " after").location

    let newSectionID = try document.splitSection(
      id: section.id,
      atUTF16Offset: splitOffset
    )

    XCTAssertEqual(rootSection(in: document, at: 0)?.markdown, "Before 🌍")
    XCTAssertEqual(rootSection(in: document, at: 1)?.id, newSectionID)
    XCTAssertEqual(rootSection(in: document, at: 1)?.markdown, " after")
  }

  // Keeps a section created by `/div` inside its current group with inherited styling.
  func testSplitGroupedSectionKeepsNewSectionInGroup() throws {
    let section = StructuredNoteSection(markdown: "FirstSecond")
    let group = StructuredSectionGroup(
      title: "Feature",
      style: StructuredSectionStyle(headingColorName: "blue"),
      sections: [section]
    )
    var document = makeDocument(nodes: [.group(group)])

    let newSectionID = try document.splitSection(id: section.id, atUTF16Offset: 5)
    let updatedGroup = try XCTUnwrap(self.group(in: document, id: group.id))

    XCTAssertEqual(updatedGroup.sections.map(\.markdown), ["First", "Second"])
    XCTAssertEqual(updatedGroup.sections.last?.id, newSectionID)
    XCTAssertEqual(updatedGroup.sections.last?.styleOverrides, .inherited)
  }

  // Keeps the previous section's identity when explicitly removing the gap before a section.
  func testMergeWithPreviousKeepsPreviousSectionIDAndContentOrder() throws {
    let first = StructuredNoteSection(markdown: "First")
    let second = StructuredNoteSection(markdown: "Second")
    var document = makeDocument(nodes: [.section(first), .section(second)])

    let retainedID = try document.mergeSection(id: second.id, direction: .previous)

    XCTAssertEqual(retainedID, first.id)
    XCTAssertEqual(document.nodes.count, 1)
    XCTAssertEqual(rootSection(in: document, at: 0)?.markdown, "First\n\nSecond")
  }

  // Prevents merge actions from silently crossing a group boundary.
  func testMergeRejectsGroupBoundaryWithoutMutatingDocument() {
    let rootSection = StructuredNoteSection(markdown: "Root")
    let groupedSection = StructuredNoteSection(markdown: "Grouped")
    let group = StructuredSectionGroup(title: "Feature", sections: [groupedSection])
    var document = makeDocument(nodes: [.section(rootSection), .group(group)])
    let originalDocument = document

    XCTAssertThrowsError(
      try document.mergeSection(id: rootSection.id, direction: .next)
    ) { error in
      XCTAssertEqual(
        error as? StructuredNoteDocumentError,
        .noAdjacentSection(rootSection.id, .next)
      )
    }
    XCTAssertEqual(document, originalDocument)
  }

  // Removes an empty source group when its final section is detached to the root.
  func testDetachFinalGroupedSectionRemovesEmptyGroup() throws {
    let rootSection = StructuredNoteSection(markdown: "Root")
    let groupedSection = StructuredNoteSection(markdown: "Grouped")
    let group = StructuredSectionGroup(title: "Feature", sections: [groupedSection])
    var document = makeDocument(nodes: [.section(rootSection), .group(group)])

    try document.detachSection(id: groupedSection.id, toRootIndex: 1)

    XCTAssertEqual(document.nodes.count, 2)
    XCTAssertEqual(self.rootSection(in: document, at: 1)?.id, groupedSection.id)
    XCTAssertNil(self.group(in: document, id: group.id))
  }

  // Supports creating a new root section and a new section inside an existing group.
  func testInsertSectionTargetsRootAndGroupDestinations() throws {
    let rootSection = StructuredNoteSection(markdown: "Root")
    let groupedSection = StructuredNoteSection(markdown: "Grouped")
    let group = StructuredSectionGroup(title: "Feature", sections: [groupedSection])
    var document = makeDocument(nodes: [.section(rootSection), .group(group)])
    let insertedRootSection = StructuredNoteSection(markdown: "Inserted root")
    let insertedGroupedSection = StructuredNoteSection(markdown: "Inserted grouped")

    try document.insertSection(
      insertedRootSection,
      at: StructuredNoteSectionDestination(parent: .root, index: 1)
    )
    try document.insertSection(
      insertedGroupedSection,
      at: StructuredNoteSectionDestination(parent: .group(group.id), index: 0)
    )

    XCTAssertEqual(self.rootSection(in: document, at: 1)?.id, insertedRootSection.id)
    XCTAssertEqual(
      self.group(in: document, id: group.id)?.sections.map(\.id),
      [insertedGroupedSection.id, groupedSection.id]
    )
  }

  // Updates root and grouped section content without changing either section's identity.
  func testSetSectionMarkdownTargetsRootAndGroupedSections() throws {
    let rootSection = StructuredNoteSection(markdown: "Original root")
    let groupedSection = StructuredNoteSection(markdown: "Original grouped")
    let group = StructuredSectionGroup(title: "Feature", sections: [groupedSection])
    var document = makeDocument(nodes: [.section(rootSection), .group(group)])

    try document.setSectionMarkdown("Updated root", sectionID: rootSection.id)
    try document.setSectionMarkdown("Updated grouped", sectionID: groupedSection.id)

    XCTAssertEqual(self.rootSection(in: document, at: 0)?.markdown, "Updated root")
    XCTAssertEqual(
      self.group(in: document, id: group.id)?.sections.first?.markdown,
      "Updated grouped"
    )
    XCTAssertEqual(self.rootSection(in: document, at: 0)?.id, rootSection.id)
    XCTAssertEqual(
      self.group(in: document, id: group.id)?.sections.first?.id,
      groupedSection.id
    )
  }

  // Preserves explicit section overrides when moving a section between groups.
  func testMoveSectionBetweenGroupsPreservesOverrides() throws {
    let overrides = StructuredSectionStyleOverrides(headingColor: .colorName("pink"))
    let movingSection = StructuredNoteSection(
      markdown: "Move me",
      styleOverrides: overrides
    )
    let sourceGroup = StructuredSectionGroup(title: "Source", sections: [movingSection])
    let destinationSection = StructuredNoteSection(markdown: "Existing")
    let destinationGroup = StructuredSectionGroup(
      title: "Destination",
      sections: [destinationSection]
    )
    var document = makeDocument(nodes: [.group(sourceGroup), .group(destinationGroup)])

    try document.moveSection(
      id: movingSection.id,
      to: StructuredNoteSectionDestination(parent: .group(destinationGroup.id), index: 1)
    )

    XCTAssertNil(group(in: document, id: sourceGroup.id))
    XCTAssertEqual(
      group(in: document, id: destinationGroup.id)?.sections.last?.styleOverrides,
      overrides
    )
  }

  // Keeps content and order intact when creating and then removing a one-level group.
  func testCreateAndUngroupPreservesSection() throws {
    let first = StructuredNoteSection(markdown: "First")
    let second = StructuredNoteSection(markdown: "Second")
    var document = makeDocument(nodes: [.section(first), .section(second)])

    let groupID = try document.createGroup(title: "Feature", aroundSectionID: second.id)
    XCTAssertEqual(group(in: document, id: groupID)?.sections.map(\.id), [second.id])

    try document.ungroup(id: groupID)

    XCTAssertEqual(document.nodes.compactMap(rootSectionID), [first.id, second.id])
  }

  // Supports top-level group movement without changing the group's child order.
  func testMoveRootNodeReordersGroupAsOneItem() throws {
    let first = StructuredNoteSection(markdown: "First")
    let grouped = StructuredNoteSection(markdown: "Grouped")
    let group = StructuredSectionGroup(title: "Feature", sections: [grouped])
    var document = makeDocument(nodes: [.section(first), .group(group)])

    try document.moveRootNode(id: group.id, to: 0)

    XCTAssertEqual(document.nodes.map(\.id), [group.id, first.id])
    XCTAssertEqual(self.group(in: document, id: group.id)?.sections.map(\.id), [grouped.id])
  }

  // Supports drag-style reordering inside a group without changing section identity.
  func testMoveSectionReordersWithinGroup() throws {
    let first = StructuredNoteSection(markdown: "First")
    let second = StructuredNoteSection(markdown: "Second")
    let third = StructuredNoteSection(markdown: "Third")
    let group = StructuredSectionGroup(title: "Feature", sections: [first, second, third])
    var document = makeDocument(nodes: [.group(group)])

    try document.moveSection(
      id: first.id,
      to: StructuredNoteSectionDestination(parent: .group(group.id), index: 2)
    )

    XCTAssertEqual(
      self.group(in: document, id: group.id)?.sections.map(\.id),
      [second.id, third.id, first.id]
    )
  }

  // Ensures a failed destination does not leave a partially moved document in memory.
  func testInvalidMoveIsTransactional() {
    let first = StructuredNoteSection(markdown: "First")
    let second = StructuredNoteSection(markdown: "Second")
    var document = makeDocument(nodes: [.section(first), .section(second)])
    let originalDocument = document

    XCTAssertThrowsError(
      try document.moveSection(
        id: first.id,
        to: StructuredNoteSectionDestination(parent: .root, index: 99)
      )
    ) { error in
      XCTAssertEqual(
        error as? StructuredNoteDocumentError,
        .invalidDestinationIndex(99)
      )
    }
    XCTAssertEqual(document, originalDocument)
  }

  // Persists section and group collapse independently.
  func testCollapseMutationsTargetRequestedItems() throws {
    let rootSection = StructuredNoteSection(markdown: "Root")
    let groupedSection = StructuredNoteSection(markdown: "Grouped")
    let group = StructuredSectionGroup(title: "Feature", sections: [groupedSection])
    var document = makeDocument(nodes: [.section(rootSection), .group(group)])

    try document.setSectionCollapsed(true, sectionID: groupedSection.id)
    try document.setGroupCollapsed(true, groupID: group.id)

    let updatedGroup = try XCTUnwrap(self.group(in: document, id: group.id))
    XCTAssertTrue(updatedGroup.isCollapsed)
    XCTAssertTrue(try XCTUnwrap(updatedGroup.sections.first).isCollapsed)
    XCTAssertFalse(try XCTUnwrap(self.rootSection(in: document, at: 0)).isCollapsed)
  }

  // Replaces only the requested section and group appearance values.
  func testAppearanceMutationsTargetRequestedItems() throws {
    let rootSection = StructuredNoteSection(markdown: "Root")
    let groupedSection = StructuredNoteSection(markdown: "Grouped")
    let group = StructuredSectionGroup(title: "Feature", sections: [groupedSection])
    var document = makeDocument(nodes: [.section(rootSection), .group(group)])
    let sectionOverrides = StructuredSectionStyleOverrides(
      backgroundColor: .colorName("section-background")
    )
    let groupStyle = StructuredSectionStyle(borderColorName: "group-border")

    try document.setStyleOverrides(sectionOverrides, sectionID: groupedSection.id)
    try document.setGroupStyle(groupStyle, groupID: group.id)

    let updatedGroup = try XCTUnwrap(self.group(in: document, id: group.id))
    XCTAssertEqual(updatedGroup.style, groupStyle)
    XCTAssertEqual(updatedGroup.sections.first?.styleOverrides, sectionOverrides)
    XCTAssertEqual(self.rootSection(in: document, at: 0)?.styleOverrides, .inherited)
  }

  // Creates a valid document fixture with stable metadata.
  private func makeDocument(nodes: [StructuredNoteNode]) -> StructuredNoteDocument {
    StructuredNoteDocument(
      id: "2026-09-01",
      date: makeDate(),
      title: "Structured",
      tags: ["v2"],
      nodes: nodes
    )
  }

  // Uses whole seconds so ISO-8601 round trips remain exact.
  private func makeDate() -> Date {
    Date(timeIntervalSince1970: 1_788_220_800)
  }

  // Reads a section only when the requested root node is a section.
  private func rootSection(
    in document: StructuredNoteDocument,
    at index: Int
  ) -> StructuredNoteSection? {
    guard document.nodes.indices.contains(index),
      case .section(let section) = document.nodes[index]
    else { return nil }
    return section
  }

  // Extracts root section IDs while excluding group nodes.
  private func rootSectionID(_ node: StructuredNoteNode) -> UUID? {
    guard case .section(let section) = node else { return nil }
    return section.id
  }

  // Locates a group fixture by its stable ID.
  private func group(
    in document: StructuredNoteDocument,
    id: UUID
  ) -> StructuredSectionGroup? {
    for node in document.nodes {
      guard case .group(let group) = node, group.id == id else { continue }
      return group
    }
    return nil
  }
}
