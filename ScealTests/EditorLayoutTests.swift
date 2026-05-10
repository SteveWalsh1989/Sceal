import AppKit
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

  // Prevents prompt block text from crossing the drawn box edge in narrow editor widths.
  func testPromptBlockTextWrapsInsideBox() throws {
    let markdown = """
      <!-- prompt -->
      word word word word word word word word word word word word
      <!-- /prompt -->
      """
    let fixture = makeEditorFixture(markdown: markdown)
    let textView = fixture.textView
    let narrowWidth: CGFloat = 160

    fixture.scrollView.setFrameSize(NSSize(width: narrowWidth, height: 240))
    textView.setFrameSize(NSSize(width: narrowWidth, height: textView.frame.height))
    textView.refreshSectionLayout()
    fixture.scrollView.layoutSubtreeIfNeeded()
    textView.layoutSubtreeIfNeeded()

    guard let textStorage = textView.textStorage else {
      return XCTFail("Expected editor text storage.")
    }

    let promptContentRanges = promptBlockContentRanges(in: textStorage)
    XCTAssertFalse(promptContentRanges.isEmpty)

    let promptBoxRightEdge = narrowWidth - 48
    for range in promptContentRanges {
      let rect = try XCTUnwrap(textView.editorRectInViewCoordinates(forCharacterRange: range))
      XCTAssertLessThanOrEqual(rect.maxX.rounded(.up), promptBoxRightEdge.rounded(.up))
    }
  }

  private func promptBlockContentRanges(in textStorage: NSTextStorage) -> [NSRange] {
    var ranges: [NSRange] = []
    textStorage.enumerateAttribute(
      .markdownPromptBlock,
      in: NSRange(location: 0, length: textStorage.length),
      options: []
    ) { value, range, _ in
      if value as? Bool == true {
        ranges.append(range)
      }
    }
    return ranges
  }
}
