import XCTest

@MainActor
final class MarkdownCompositePreservationTests: MarkdownPreservationTestCase {
  // Prevents headings from dropping nested bold styling on save.
  func testHeadingWithBold() {
    XCTAssertEqual(preservedMarkdown("## **bold heading**"), "## **bold heading**")
  }

  // Prevents blockquotes from losing nested bold styling on save.
  func testBlockquoteWithBold() {
    XCTAssertEqual(preservedMarkdown("> **bold quote**"), "> **bold quote**")
  }

  // Prevents bullets from losing nested italic styling on save.
  func testBulletWithItalic() {
    XCTAssertEqual(preservedMarkdown("- *italic bullet*"), "- *italic bullet*")
  }

  // Prevents bullets from losing nested links on save.
  func testBulletWithLink() {
    XCTAssertEqual(
      preservedMarkdown("- [link](https://example.com)"),
      "- [link](https://example.com)"
    )
  }

  // Prevents mixed markdown documents from changing structure during editing.
  func testMultilineDocument() {
    let markdown = "# Title\n\nSome **bold** and *italic* text.\n\n- item one\n- item two"
    XCTAssertEqual(preservedMarkdown(markdown), markdown)
  }
}
