import XCTest

@testable import Sceal

@MainActor
final class MarkdownBlockPreservationTests: MarkdownPreservationTestCase {
  // Prevents blockquotes from flattening into normal paragraphs.
  func testBlockquote() {
    XCTAssertEqual(preservedMarkdown("> quote"), "> quote")
  }

  // Prevents fenced code blocks from losing their fences or body text.
  func testCodeBlock() {
    let markdown = "```\nlet x = 1\n```"
    XCTAssertEqual(preservedMarkdown(markdown), markdown)
  }

  // Prevents section divider markers from disappearing during editor conversion.
  func testSectionDivider() {
    XCTAssertEqual(preservedMarkdown("<!-- section -->"), "<!-- section -->")
  }
}
