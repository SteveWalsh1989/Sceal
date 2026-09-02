import Foundation
import XCTest

@testable import Sceal

final class StructuredNoteCollapseTests: XCTestCase {
  // Prefers a real heading over earlier body text and ignores heading-shaped fenced content.
  func testPreviewPrefersFirstHeadingOutsideCodeFence() {
    let markdown = """
      Intro paragraph

      ```swift
      # Not a heading
      ```

      ## **Feature** [plan](https://example.com)
      """

    XCTAssertEqual(StructuredNoteCollapse.previewText(for: markdown), "Feature plan")
  }

  // Produces a readable fallback from common list and inline Markdown markers.
  func testPreviewUsesFirstPlainContentLineAndHandlesEmptySections() {
    XCTAssertEqual(
      StructuredNoteCollapse.previewText(
        for: "\n- [x] **Ship** the [release](https://example.com)"),
      "Ship the release"
    )
    XCTAssertEqual(
      StructuredNoteCollapse.previewText(for: "<!-- section heading:blue -->\n\n"),
      StructuredNoteCollapse.emptySectionPreview
    )
    XCTAssertEqual(
      StructuredNoteCollapse.previewText(for: "```swift\nlet value = 1\n```"),
      "let value = 1"
    )
  }

  // Excludes individually collapsed sections and every child of a collapsed group.
  func testEditableSectionOrderSkipsCollapsedContent() {
    let first = StructuredNoteSection(markdown: "First")
    let collapsedRoot = StructuredNoteSection(markdown: "Collapsed", isCollapsed: true)
    let hiddenChild = StructuredNoteSection(markdown: "Hidden child")
    let hiddenGroup = StructuredSectionGroup(
      title: "Hidden group",
      isCollapsed: true,
      sections: [hiddenChild]
    )
    let collapsedChild = StructuredNoteSection(markdown: "Collapsed child", isCollapsed: true)
    let visibleChild = StructuredNoteSection(markdown: "Visible child")
    let visibleGroup = StructuredSectionGroup(
      title: "Visible group",
      sections: [collapsedChild, visibleChild]
    )
    let document = makeDocument(
      nodes: [
        .section(first),
        .section(collapsedRoot),
        .group(hiddenGroup),
        .group(visibleGroup),
      ]
    )

    XCTAssertEqual(
      StructuredNoteCollapse.editableSectionIDs(in: document),
      [first.id, visibleChild.id]
    )
  }

  // Reveals only the first matching section and the group needed to display it.
  func testSearchRevealExpandsMatchingSectionAndParentOnly() throws {
    let root = StructuredNoteSection(markdown: "Root", isCollapsed: true)
    let firstChild = StructuredNoteSection(markdown: "Other", isCollapsed: true)
    let matchingChild = StructuredNoteSection(markdown: "Needle content", isCollapsed: true)
    let group = StructuredSectionGroup(
      title: "Feature",
      isCollapsed: true,
      sections: [firstChild, matchingChild]
    )
    var document = makeDocument(nodes: [.section(root), .group(group)])

    let match = StructuredNoteCollapse.revealFirstSearchMatch(
      for: "needle",
      in: &document
    )

    XCTAssertEqual(
      match,
      StructuredNoteSearchMatch(sectionID: matchingChild.id, groupID: group.id)
    )
    guard case .section(let updatedRoot) = document.nodes[0],
      case .group(let updatedGroup) = document.nodes[1]
    else {
      return XCTFail("Expected the original root structure")
    }
    XCTAssertTrue(updatedRoot.isCollapsed)
    XCTAssertFalse(updatedGroup.isCollapsed)
    XCTAssertTrue(updatedGroup.sections[0].isCollapsed)
    XCTAssertFalse(updatedGroup.sections[1].isCollapsed)
  }

  // Does not change collapse preferences when the query only matches non-section metadata.
  func testSearchRevealIgnoresGroupTitleOnlyMatches() {
    let child = StructuredNoteSection(markdown: "Body", isCollapsed: true)
    let group = StructuredSectionGroup(
      title: "Needle title",
      isCollapsed: true,
      sections: [child]
    )
    var document = makeDocument(nodes: [.group(group)])
    let originalDocument = document

    XCTAssertNil(
      StructuredNoteCollapse.revealFirstSearchMatch(for: "needle", in: &document)
    )
    XCTAssertEqual(document, originalDocument)
  }

  private func makeDocument(nodes: [StructuredNoteNode]) -> StructuredNoteDocument {
    StructuredNoteDocument(
      id: "2026-09-02",
      date: Date(timeIntervalSince1970: 1_788_307_200),
      title: "Collapse fixture",
      tags: ["v2"],
      nodes: nodes
    )
  }
}
