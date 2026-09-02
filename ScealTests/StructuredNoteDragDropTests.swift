import Foundation
import XCTest

@testable import Sceal

final class StructuredNoteDragDropTests: XCTestCase {
  // Keeps item-provider values scoped to structured section and group drags.
  func testPayloadEncodingRoundTripsAndRejectsForeignValues() {
    let sectionID = UUID()
    let groupID = UUID()

    XCTAssertEqual(
      StructuredNoteDragPayload(
        encodedValue: StructuredNoteDragPayload.section(sectionID).encodedValue),
      .section(sectionID)
    )
    XCTAssertEqual(
      StructuredNoteDragPayload(
        encodedValue: StructuredNoteDragPayload.group(groupID).encodedValue),
      .group(groupID)
    )
    XCTAssertNil(StructuredNoteDragPayload(encodedValue: "foreign-drag-item"))
  }

  // Prevents the in-process drag data from being advertised as insertable plain text.
  @MainActor
  func testItemProviderPublishesOnlyStructuredDragType() {
    let payload = StructuredNoteDragPayload.section(UUID())
    let provider = payload.makeItemProvider()

    XCTAssertEqual(
      provider.registeredTypeIdentifiers,
      [StructuredNoteDragPayload.contentType.identifier]
    )
    XCTAssertNotEqual(StructuredNoteDragPayload.contentType.identifier, "public.data")
    XCTAssertEqual(provider.suggestedName, payload.encodedValue)
    XCTAssertFalse(provider.hasItemConformingToTypeIdentifier("public.plain-text"))
  }

  // Interprets root insertion gaps after removing the dragged section.
  func testReordersRootSectionsInBothDirections() throws {
    let first = StructuredNoteSection(markdown: "First")
    let second = StructuredNoteSection(markdown: "Second")
    let third = StructuredNoteSection(markdown: "Third")
    var document = makeDocument(nodes: [.section(first), .section(second), .section(third)])

    let forwardResult = try StructuredNoteDragDrop.apply(
      .section(first.id),
      to: .root(insertionIndex: 3),
      in: &document
    )
    let backwardResult = try StructuredNoteDragDrop.apply(
      .section(third.id),
      to: .root(insertionIndex: 0),
      in: &document
    )

    XCTAssertTrue(forwardResult.didChange)
    XCTAssertEqual(forwardResult.focusedSectionID, first.id)
    XCTAssertTrue(backwardResult.didChange)
    XCTAssertEqual(rootNodeIDs(in: document), [third.id, second.id, first.id])
  }

  // Moves a group as one root unit without altering its style, state, or children.
  func testReordersGroupAsTopLevelUnit() throws {
    let first = StructuredNoteSection(markdown: "Root")
    let child = StructuredNoteSection(markdown: "Child", isCollapsed: true)
    let group = StructuredSectionGroup(
      title: "Feature",
      style: StructuredSectionStyle(
        backgroundColorName: "grey",
        borderColorName: "blue"
      ),
      isCollapsed: true,
      sections: [child]
    )
    let last = StructuredNoteSection(markdown: "Last")
    var document = makeDocument(nodes: [.section(first), .group(group), .section(last)])

    let result = try StructuredNoteDragDrop.apply(
      .group(group.id),
      to: .root(insertionIndex: 0),
      in: &document
    )

    XCTAssertTrue(result.didChange)
    XCTAssertEqual(result.focusedSectionID, child.id)
    XCTAssertEqual(rootNodeIDs(in: document), [group.id, first.id, last.id])
    guard case .group(let movedGroup) = document.nodes[0] else {
      return XCTFail("Expected the group at the first root position")
    }
    XCTAssertEqual(movedGroup, group)
  }

  // Reorders child sections against insertion gaps inside the same group.
  func testReordersSectionsWithinGroup() throws {
    let first = StructuredNoteSection(markdown: "First")
    let second = StructuredNoteSection(markdown: "Second")
    let third = StructuredNoteSection(markdown: "Third")
    let group = StructuredSectionGroup(title: "Group", sections: [first, second, third])
    var document = makeDocument(nodes: [.group(group)])

    try StructuredNoteDragDrop.apply(
      .section(first.id),
      to: .group(groupID: group.id, insertionIndex: 3),
      in: &document
    )

    XCTAssertEqual(groupSectionIDs(group.id, in: document), [second.id, third.id, first.id])
  }

  // Preserves complete section state while removing an emptied source group.
  func testMovesSectionBetweenGroupsAndPreservesState() throws {
    let moving = StructuredNoteSection(
      markdown: "Moving",
      styleOverrides: StructuredSectionStyleOverrides(
        backgroundColor: .colorName("orange"),
        borderColor: .themeDefault
      ),
      isCollapsed: true
    )
    let existing = StructuredNoteSection(markdown: "Existing")
    let sourceGroup = StructuredSectionGroup(title: "Source", sections: [moving])
    let destinationGroup = StructuredSectionGroup(title: "Destination", sections: [existing])
    var document = makeDocument(nodes: [.group(sourceGroup), .group(destinationGroup)])

    try StructuredNoteDragDrop.apply(
      .section(moving.id),
      to: .group(groupID: destinationGroup.id, insertionIndex: 0),
      in: &document
    )

    XCTAssertEqual(rootNodeIDs(in: document), [destinationGroup.id])
    XCTAssertEqual(groupSectionIDs(destinationGroup.id, in: document), [moving.id, existing.id])
    XCTAssertEqual(section(moving.id, in: document), moving)
  }

  // Detaches to a root gap while retaining a non-empty source group.
  func testDetachesSectionAtRootDropTarget() throws {
    let root = StructuredNoteSection(markdown: "Root")
    let moving = StructuredNoteSection(markdown: "Moving")
    let remaining = StructuredNoteSection(markdown: "Remaining")
    let group = StructuredSectionGroup(title: "Group", sections: [moving, remaining])
    let trailing = StructuredNoteSection(markdown: "Trailing")
    var document = makeDocument(
      nodes: [.section(root), .group(group), .section(trailing)]
    )

    try StructuredNoteDragDrop.apply(
      .section(moving.id),
      to: .root(insertionIndex: 3),
      in: &document
    )

    XCTAssertEqual(rootNodeIDs(in: document), [root.id, group.id, trailing.id, moving.id])
    XCTAssertEqual(groupSectionIDs(group.id, in: document), [remaining.id])
  }

  // Normalizes the root gap when detaching removes the section's former group.
  func testDetachingOnlyChildRemovesGroupWithoutShiftingDropPosition() throws {
    let root = StructuredNoteSection(markdown: "Root")
    let moving = StructuredNoteSection(markdown: "Moving")
    let group = StructuredSectionGroup(title: "Group", sections: [moving])
    let trailing = StructuredNoteSection(markdown: "Trailing")
    var document = makeDocument(
      nodes: [.section(root), .group(group), .section(trailing)]
    )

    try StructuredNoteDragDrop.apply(
      .section(moving.id),
      to: .root(insertionIndex: 3),
      in: &document
    )

    XCTAssertEqual(rootNodeIDs(in: document), [root.id, trailing.id, moving.id])
  }

  // Rejects group nesting transactionally and leaves the source document unchanged.
  func testRejectsGroupDropInsideAnotherGroupWithoutMutation() {
    let firstGroup = StructuredSectionGroup(
      title: "First",
      sections: [StructuredNoteSection(markdown: "One")]
    )
    let secondGroup = StructuredSectionGroup(
      title: "Second",
      sections: [StructuredNoteSection(markdown: "Two")]
    )
    var document = makeDocument(nodes: [.group(firstGroup), .group(secondGroup)])
    let originalDocument = document
    let target = StructuredNoteDropTarget.group(
      groupID: secondGroup.id,
      insertionIndex: 0
    )

    XCTAssertThrowsError(
      try StructuredNoteDragDrop.apply(.group(firstGroup.id), to: target, in: &document)
    ) { error in
      XCTAssertEqual(error as? StructuredNoteDragDropError, .groupsCannotBeNested)
    }
    XCTAssertFalse(StructuredNoteDragDrop.canApply(.group(firstGroup.id), to: target, in: document))
    XCTAssertEqual(document, originalDocument)
  }

  // Treats adjacent gap hovers as no-ops so cancellation cannot create an undo or reorder.
  func testNoOpAndHoverValidationDoNotMutateDocument() throws {
    let first = StructuredNoteSection(markdown: "First")
    let second = StructuredNoteSection(markdown: "Second")
    var document = makeDocument(nodes: [.section(first), .section(second)])
    let originalDocument = document
    let adjacentTarget = StructuredNoteDropTarget.root(insertionIndex: 1)

    XCTAssertFalse(
      StructuredNoteDragDrop.canApply(.section(first.id), to: adjacentTarget, in: document)
    )
    let result = try StructuredNoteDragDrop.apply(
      .section(first.id),
      to: adjacentTarget,
      in: &document
    )

    XCTAssertFalse(result.didChange)
    XCTAssertEqual(document, originalDocument)
  }

  // Builds a small valid fixture for pure drag/drop mutation tests.
  private func makeDocument(nodes: [StructuredNoteNode]) -> StructuredNoteDocument {
    StructuredNoteDocument(
      id: "2026-06-13",
      date: Date(timeIntervalSince1970: 1_781_308_800),
      title: "Drag fixture",
      tags: ["v2"],
      nodes: nodes
    )
  }

  // Returns root IDs without flattening group children into the root order.
  private func rootNodeIDs(in document: StructuredNoteDocument) -> [UUID] {
    document.nodes.map(\.id)
  }

  // Finds one group's child order for focused assertions.
  private func groupSectionIDs(
    _ groupID: UUID,
    in document: StructuredNoteDocument
  ) -> [UUID] {
    for node in document.nodes {
      guard case .group(let group) = node, group.id == groupID else { continue }
      return group.sections.map(\.id)
    }
    return []
  }

  // Finds a section after moves without assuming its current parent.
  private func section(
    _ sectionID: UUID,
    in document: StructuredNoteDocument
  ) -> StructuredNoteSection? {
    for node in document.nodes {
      switch node {
      case .section(let section) where section.id == sectionID:
        return section
      case .group(let group):
        if let section = group.sections.first(where: { $0.id == sectionID }) {
          return section
        }
      default:
        continue
      }
    }
    return nil
  }
}
