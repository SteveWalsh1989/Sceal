import XCTest

@testable import Sceal

@MainActor
final class EditorLayoutTests: EditorTestCase {
  // Prevents tiny windows from losing the minimum scroll room below the note.
  func testBottomOverscrollUsesMinimumForSmallViewport() {
    XCTAssertEqual(MarkdownEditorView.bottomOverscrollHeight(for: 240), 300)
  }

  // Prevents large windows from getting a cramped end-of-document scroll area.
  func testBottomOverscrollScalesForLargeViewport() {
    XCTAssertEqual(MarkdownEditorView.bottomOverscrollHeight(for: 1200), 900)
  }

  // Prevents long documents from clipping the intended scroll-past-end padding.
  func testTargetEditorHeightAddsBottomOverscroll() {
    XCTAssertEqual(
      MarkdownEditorView.targetEditorHeight(documentHeight: 1600, viewportHeight: 1200),
      2500
    )
  }
}
