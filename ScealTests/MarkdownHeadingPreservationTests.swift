import XCTest

@testable import Sceal

@MainActor
final class MarkdownHeadingPreservationTests: MarkdownPreservationTestCase {
  // Prevents heading level 1 markers from being dropped on save.
  func testHeading1() {
    XCTAssertEqual(preservedMarkdown("# Heading 1"), "# Heading 1")
  }

  // Prevents heading level 2 markers from being dropped on save.
  func testHeading2() {
    XCTAssertEqual(preservedMarkdown("## Heading 2"), "## Heading 2")
  }

  // Prevents heading level 3 markers from being dropped on save.
  func testHeading3() {
    XCTAssertEqual(preservedMarkdown("### Heading 3"), "### Heading 3")
  }
}
