import XCTest

@testable import Sceal

@MainActor
final class StructuredEditorParityTests: EditorTestCase {
  // Uses the shared formatter to retain every content feature when divider rows are literal content.
  func testStructuredSectionContentRoundTripsDailyEditorMarkdownFeatures() {
    let markdown = """
      # Heading
      **bold** *italic* ~~strike~~ `inline`
      - bullet
        1. nested
      - [ ] unchecked
      - [x] checked
      > quote
      [Scéal](https://example.com)
      ```swift
      let value = 1
      ```
      <!-- prompt -->
      Copy this
      <!-- /prompt -->
      <!-- table -->
      {"columns":["A"],"rows":[["B"]]}
      <!-- /table -->
      ![Image](../Attachments/2026-09-02/image.png)
      <!-- section -->
      """
    let display = MarkdownEditorFormatter.formatForDisplay(
      markdown,
      appearance: appearance,
      interpretsSectionDirectives: false
    )

    XCTAssertEqual(
      MarkdownEditorFormatter.convertToMarkdown(
        from: display,
        normalizesSectionDirectives: false
      ),
      markdown
    )
    XCTAssertTrue(display.string.contains("<!-- section -->"))
  }
}
