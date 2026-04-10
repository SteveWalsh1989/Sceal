import AppKit
import XCTest

@testable import Sceal

@MainActor
final class EditorDividerTests: EditorTestCase {
  // Prevents divider replacements from leaving the caret past the rendered glyph.
  func testReplacingDividerClampsCaret() {
    let fixture = makeRawEditorFixture(string: "<!-- section -->")
    let textView = fixture.textView
    textView.setSelectedRange(NSRange(location: 16, length: 0))

    let handled = textView.performEditorEdit(
      affectedRange: NSRange(location: 0, length: 16),
      replacementString: MarkdownEditorFormatter.sectionDividerDisplayString().string,
      actionName: "Replace With Divider"
    ) { textStorage in
      textStorage.replaceCharacters(
        in: NSRange(location: 0, length: 16),
        with: MarkdownEditorFormatter.sectionDividerDisplayString()
      )
      return NSRange(location: 16, length: 0)
    }

    XCTAssertTrue(handled)
    XCTAssertEqual(textView.string, " ")
    XCTAssertEqual(textView.selectedRange(), NSRange(location: 1, length: 0))
  }

  // Prevents divider rendering from leaking raw markdown or spacing regressions.
  func testSectionDividerDisplayString() {
    let divider = MarkdownEditorFormatter.sectionDividerDisplayString()
    let paragraphStyle =
      divider.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle

    XCTAssertEqual(divider.string, " ")
    XCTAssertEqual(divider.length, 1)
    XCTAssertEqual(
      divider.attribute(.markdownSectionDivider, at: 0, effectiveRange: nil) as? Bool,
      true
    )
    XCTAssertEqual(
      paragraphStyle?.paragraphSpacingBefore,
      MarkdownEditorFormatter.sectionDividerSpacingBefore
    )
    XCTAssertEqual(
      paragraphStyle?.paragraphSpacing,
      MarkdownEditorFormatter.sectionDividerSpacingAfter
    )
    XCTAssertEqual(
      paragraphStyle?.maximumLineHeight,
      MarkdownEditorFormatter.sectionDividerLineHeight
    )
  }

  // Prevents backspace from leaving a hidden section marker above the caret.
  func testBackspaceBelowDividerRemovesIt() {
    let markdown = MarkdownBox("<!-- section -->\nBody")
    let coordinator = makeCoordinator(markdown: markdown)
    let fixture = makeEditorFixture(markdown: markdown.value)
    let textView = fixture.textView
    let bodyLocation = (textView.string as NSString).range(of: "Body").location

    XCTAssertNotEqual(bodyLocation, NSNotFound)

    textView.delegate = coordinator
    textView.setSelectedRange(NSRange(location: bodyLocation, length: 0))

    let handled = coordinator.textView(
      textView,
      doCommandBy: #selector(NSResponder.deleteBackward(_:))
    )

    XCTAssertTrue(handled)
    XCTAssertEqual(markdown.value, "Body")
    XCTAssertEqual(textView.sectionDividerCount, 0)
    XCTAssertEqual(textView.selectedRange(), NSRange(location: 0, length: 0))
  }

  // Prevents divider selection from trapping the caret on non-editable content.
  func testSelectingDividerMovesCaretForward() {
    let fixture = makeEditorFixture(markdown: "Before\n<!-- section -->\nAfter")
    let textView = fixture.textView

    guard let textStorage = textView.textStorage else {
      return XCTFail("Expected editor text storage.")
    }

    let dividerRange = firstSectionDividerRange(in: textStorage)
    let dividerLineRange = (textView.string as NSString).lineRange(for: dividerRange)

    textView.setSelectedRange(NSRange(location: dividerRange.location, length: 0))
    let normalized = textView.editorNormalizeSelectionIfNeeded(prefer: .next)

    XCTAssertTrue(normalized)
    XCTAssertEqual(
      textView.selectedRange(),
      NSRange(location: NSMaxRange(dividerLineRange), length: 0)
    )
  }

  // Prevents upper-half divider clicks from skipping the previous editable line.
  func testSelectingDividerMovesCaretBackward() {
    let fixture = makeEditorFixture(markdown: "Before\n<!-- section -->\nAfter")
    let textView = fixture.textView

    guard let textStorage = textView.textStorage else {
      return XCTFail("Expected editor text storage.")
    }

    let dividerRange = firstSectionDividerRange(in: textStorage)

    textView.setSelectedRange(NSRange(location: dividerRange.location, length: 0))
    let normalized = textView.editorNormalizeSelectionIfNeeded(prefer: .previous)

    XCTAssertTrue(normalized)
    XCTAssertEqual(textView.selectedRange(), NSRange(location: "Before".utf16.count, length: 0))
  }
}
