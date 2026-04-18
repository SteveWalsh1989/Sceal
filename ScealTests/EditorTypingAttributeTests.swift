import AppKit
import XCTest

@testable import Sceal

@MainActor
final class EditorTypingAttributeTests: EditorTestCase {
  // Prevents checkbox attachment glyphs from seeding tiny default typing attributes.
  func testCheckboxLineStartSkipsAttachmentTypingSource() {
    let fixture = makeEditorFixture(markdown: "- [ ] Task")
    let textView = fixture.textView

    guard let textStorage = textView.textStorage else {
      return XCTFail("Expected editor text storage.")
    }

    let checkboxLocation = firstCheckboxLocation(in: textStorage)

    XCTAssertEqual(
      textView.typingAttributeSourceLocation(forInsertionLocation: checkboxLocation),
      checkboxLocation + 1
    )
  }

  // Prevents bullet marker glyphs from leaking the bullet font into typed list content.
  func testBulletLineStartSkipsBulletGlyphTypingSource() {
    let fixture = makeEditorFixture(markdown: "- Bullet")
    let textView = fixture.textView
    let bulletLocation = (textView.string as NSString).range(
      of: MarkdownEditorFormatter.bulletMarker
    ).location

    XCTAssertNotEqual(bulletLocation, NSNotFound)
    XCTAssertEqual(
      textView.typingAttributeSourceLocation(forInsertionLocation: bulletLocation),
      bulletLocation + 1
    )
  }

  // Prevents divider-adjacent checkbox lines from falling back to AppKit's tiny black defaults.
  func testCheckboxLineStartAfterDividerKeepsBodyTypingAttributes() {
    let markdown = MarkdownBox("<!-- section -->\n- [ ] Task")
    let coordinator = makeCoordinator(markdown: markdown)
    let fixture = makeEditorFixture(markdown: markdown.value)
    let textView = fixture.textView

    guard let textStorage = textView.textStorage else {
      return XCTFail("Expected editor text storage.")
    }

    textView.delegate = coordinator
    let checkboxLocation = firstCheckboxLocation(in: textStorage)
    textView.setSelectedRange(NSRange(location: checkboxLocation, length: 0))

    coordinator.textViewDidChangeSelection(
      Notification(name: NSTextView.didChangeSelectionNotification, object: textView)
    )

    let font = textView.typingAttributes[.font] as? NSFont
    let paragraphStyle = textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle
    let expectedListStyle = MarkdownEditorFormatter.listParagraphStyle(for: appearance)

    XCTAssertEqual(font?.fontName, appearance.bodyFont.fontName)
    XCTAssertEqual(font?.pointSize, appearance.bodyFont.pointSize)
    XCTAssertEqual(
      textView.typingAttributes[.markdownListType] as? String,
      MarkdownListType.checkboxUnchecked.rawValue
    )
    XCTAssertEqual(paragraphStyle?.headIndent, expectedListStyle.headIndent)
    XCTAssertEqual(paragraphStyle?.firstLineHeadIndent, expectedListStyle.firstLineHeadIndent)
  }
}
