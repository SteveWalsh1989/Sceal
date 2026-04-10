import XCTest

@testable import Sceal

@MainActor
final class MarkdownInlinePreservationTests: MarkdownPreservationTestCase {
  // Prevents bold markdown from being stripped during display conversion.
  func testBold() {
    XCTAssertEqual(preservedMarkdown("**bold**"), "**bold**")
  }

  // Prevents italic markdown from being stripped during display conversion.
  func testItalic() {
    XCTAssertEqual(preservedMarkdown("*italic*"), "*italic*")
  }

  // Prevents strike-through markdown from being dropped on save.
  func testStrikethrough() {
    XCTAssertEqual(preservedMarkdown("~~strikethrough~~"), "~~strikethrough~~")
  }

  // Prevents inline code markdown from losing its backticks.
  func testInlineCode() {
    XCTAssertEqual(preservedMarkdown("`code`"), "`code`")
  }

  // Prevents inline links from losing either label text or URL.
  func testLink() {
    XCTAssertEqual(
      preservedMarkdown("[text](https://example.com)"),
      "[text](https://example.com)"
    )
  }

  // Prevents combined bold and italic styling from collapsing into one style.
  func testBoldItalic() {
    XCTAssertEqual(preservedMarkdown("***bold italic***"), "***bold italic***")
  }

  // Prevents mixed inline spans on one line from interfering with each other.
  func testMixedInlineSpans() {
    XCTAssertEqual(
      preservedMarkdown("**bold** and *italic*"),
      "**bold** and *italic*"
    )
  }
}
