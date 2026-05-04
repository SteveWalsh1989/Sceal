import XCTest

@testable import Sceal

@MainActor
final class MarkdownImagePreservationTests: MarkdownPreservationTestCase {
  func testImageMarkdownPreserved() {
    let markdown = "![Desk photo](../Attachments/2026-05-04/desk-photo.png)"

    XCTAssertEqual(preservedMarkdown(markdown), markdown)
  }

  func testResizedImageMarkdownPreserved() {
    let markdown = """
      <!-- sceal-image-width:520 -->
      ![Desk photo](../Attachments/2026-05-04/desk-photo.png)
      """

    XCTAssertEqual(preservedMarkdown(markdown), markdown)
  }
}
