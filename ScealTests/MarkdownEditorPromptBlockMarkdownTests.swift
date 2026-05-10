import XCTest

@testable import Sceal

final class MarkdownEditorPromptBlockMarkdownTests: XCTestCase {
  // Keeps persisted prompt block markers mapped to the hidden editor boundary kinds.
  func testParsesPromptBoundaryKinds() {
    XCTAssertEqual(
      MarkdownEditorPromptBlockMarkdown.boundaryKind(for: "<!-- prompt -->"),
      MarkdownEditorPromptBlockMarkdown.startBoundaryKind
    )
    XCTAssertEqual(
      MarkdownEditorPromptBlockMarkdown.boundaryKind(for: "<!-- /prompt -->"),
      MarkdownEditorPromptBlockMarkdown.endBoundaryKind
    )
    XCTAssertNil(MarkdownEditorPromptBlockMarkdown.boundaryKind(for: "<!-- prompt --> "))
  }

  // Keeps the empty slash-command prompt snippet in the current persisted markdown shape.
  func testEmptyPromptBlockMarkdown() {
    XCTAssertEqual(
      MarkdownEditorPromptBlockMarkdown.emptyBlock,
      """
      <!-- prompt -->

      <!-- /prompt -->
      """
    )
  }

  // Keeps editor boundary kind serialization aligned with persisted markers.
  func testMarkerForBoundaryKind() {
    XCTAssertEqual(
      MarkdownEditorPromptBlockMarkdown.marker(
        forBoundaryKind: MarkdownEditorPromptBlockMarkdown.startBoundaryKind
      ),
      "<!-- prompt -->"
    )
    XCTAssertEqual(
      MarkdownEditorPromptBlockMarkdown.marker(
        forBoundaryKind: MarkdownEditorPromptBlockMarkdown.endBoundaryKind
      ),
      "<!-- /prompt -->"
    )
  }
}
