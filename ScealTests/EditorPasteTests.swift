import AppKit
import XCTest

@testable import Sceal

@MainActor
final class EditorPasteTests: EditorTestCase {
  // Prevents URL paste over a selection from replacing visible text instead of linking it.
  func testPastingURLOverSelectionCreatesLink() {
    let fixture = makeRawEditorFixture(string: "Read docs")
    let textView = fixture.textView

    guard let textStorage = textView.textStorage else {
      return XCTFail("Expected editor text storage.")
    }

    let selection = (textView.string as NSString).range(of: "docs")
    XCTAssertNotEqual(selection.location, NSNotFound)

    textView.setSelectedRange(selection)
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString("https://example.com/docs", forType: .string)

    textView.paste(nil)

    XCTAssertEqual(textView.string, "Read docs")
    XCTAssertEqual(textView.selectedRange(), NSRange(location: NSMaxRange(selection), length: 0))
    XCTAssertEqual(
      textStorage.attribute(.markdownLinkURL, at: selection.location, effectiveRange: nil)
        as? String,
      "https://example.com/docs"
    )
    XCTAssertEqual(
      (textStorage.attribute(.link, at: selection.location, effectiveRange: nil) as? URL)?
        .absoluteString,
      "https://example.com/docs"
    )
    XCTAssertEqual(
      MarkdownEditorFormatter.convertToMarkdown(from: textStorage),
      "Read [docs](https://example.com/docs)"
    )
  }

  // Prevents Enter from rebuilding a rendered link line from plain display text.
  func testInsertNewlinePreservesExistingLinkMarkdown() {
    let markdown = MarkdownBox("Visit [docs](https://example.com/docs)")
    let coordinator = makeCoordinator(markdown: markdown)
    let fixture = makeEditorFixture(markdown: markdown.value)
    let textView = fixture.textView
    textView.delegate = coordinator

    guard let textStorage = textView.textStorage else {
      return XCTFail("Expected editor text storage.")
    }

    let linkRange = (textView.string as NSString).range(of: "docs")
    XCTAssertNotEqual(linkRange.location, NSNotFound)

    textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))

    XCTAssertTrue(
      coordinator.textView(textView, doCommandBy: #selector(NSResponder.insertNewline(_:)))
    )
    XCTAssertEqual(
      textStorage.attribute(.markdownLinkURL, at: linkRange.location, effectiveRange: nil)
        as? String,
      "https://example.com/docs"
    )
    XCTAssertEqual(
      MarkdownEditorFormatter.convertToMarkdown(from: textStorage),
      "Visit [docs](https://example.com/docs)"
    )
  }

  // Prevents inline link copies from degrading to plain text outside the app.
  func testCopyingInlineLinkWritesMarkdownToPlainTextPasteboard() {
    let fixture = makeEditorFixture(markdown: "Visit [docs](https://example.com/docs)")
    let textView = fixture.textView
    let selection = (textView.string as NSString).range(of: "docs")
    XCTAssertNotEqual(selection.location, NSNotFound)

    textView.setSelectedRange(selection)

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()

    textView.copy(nil)

    XCTAssertEqual(
      pasteboard.string(forType: .string),
      "[docs](https://example.com/docs)"
    )
  }

  // Prevents standalone URL pastes from losing clickability in the editor.
  func testPastingStandaloneURLAutolinksPlainText() {
    let fixture = makeRawEditorFixture(string: "")
    let textView = fixture.textView

    guard let textStorage = textView.textStorage else {
      return XCTFail("Expected editor text storage.")
    }

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString("https://example.com/docs", forType: .string)

    textView.paste(nil)

    XCTAssertEqual(textView.string, "https://example.com/docs")
    XCTAssertNil(textStorage.attribute(.markdownLinkURL, at: 0, effectiveRange: nil))
    XCTAssertEqual(
      (textStorage.attribute(.link, at: 0, effectiveRange: nil) as? URL)?.absoluteString,
      "https://example.com/docs"
    )
    XCTAssertEqual(
      MarkdownEditorFormatter.convertToMarkdown(from: textStorage),
      "https://example.com/docs"
    )
  }
}
