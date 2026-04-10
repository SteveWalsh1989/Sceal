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
}
