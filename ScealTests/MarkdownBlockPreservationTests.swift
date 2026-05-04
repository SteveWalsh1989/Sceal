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

  // Prevents prompt blocks from gaining code fences or losing plain prompt text.
  func testPromptBlock() {
    let markdown = """
      <!-- prompt -->
      Write a concise release note.
      Include risks and validation.
      <!-- /prompt -->
      """
    XCTAssertEqual(preservedMarkdown(markdown), markdown)
  }
}
