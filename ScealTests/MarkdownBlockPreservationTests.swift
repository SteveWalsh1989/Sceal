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

  // Prevents fenced code blocks with language names from losing the opening fence.
  func testCodeBlockWithLanguage() {
    let markdown = "```swift\nlet x = 1\n```"
    XCTAssertEqual(preservedMarkdown(markdown), markdown)
  }

  // Prevents standard horizontal rules from being saved as visible editor placeholders.
  func testHorizontalRule() {
    XCTAssertEqual(preservedMarkdown("---"), "---")
  }

  // Prevents section divider markers from disappearing during editor conversion.
  func testSectionDivider() {
    XCTAssertEqual(preservedMarkdown("<!-- section -->"), "<!-- section -->")
  }

  // Keeps hidden heading-color metadata from creating persistent leading blank lines.
  func testFirstLineHeadingColorDoesNotGainBlankLinesAcrossReloads() {
    let markdown = "<!-- hcolor:orange -->\n# Feature: Dashboards"
    let firstDisplay = MarkdownEditorFormatter.formatForDisplay(
      markdown,
      appearance: appearance,
      interpretsSectionDirectives: false
    )
    let firstSave = MarkdownEditorFormatter.convertToMarkdown(
      from: firstDisplay,
      normalizesSectionDirectives: false
    )
    let secondDisplay = MarkdownEditorFormatter.formatForDisplay(
      firstSave,
      appearance: appearance,
      interpretsSectionDirectives: false
    )
    let secondSave = MarkdownEditorFormatter.convertToMarkdown(
      from: secondDisplay,
      normalizesSectionDirectives: false
    )

    XCTAssertEqual(firstDisplay.string, "Feature: Dashboards")
    XCTAssertEqual(firstSave, markdown)
    XCTAssertEqual(secondDisplay.string, "Feature: Dashboards")
    XCTAssertEqual(secondSave, markdown)
  }

  // Preserves the real separator before hidden heading-color metadata within a section.
  func testHeadingColorAfterBodyKeepsOneLineSeparator() {
    let markdown = "Overview\n<!-- hcolor:orange -->\n# Feature: Dashboards"
    let display = MarkdownEditorFormatter.formatForDisplay(
      markdown,
      appearance: appearance,
      interpretsSectionDirectives: false
    )

    XCTAssertEqual(display.string, "Overview\nFeature: Dashboards")
    XCTAssertEqual(
      MarkdownEditorFormatter.convertToMarkdown(
        from: display,
        normalizesSectionDirectives: false
      ),
      markdown
    )
  }

  // Treats a legacy divider marker as ordinary content inside a structured section editor.
  func testStructuredSectionPreservesLiteralDividerMarkerAndFollowingBlankLine() {
    let markdown = "Before\n<!-- section -->\n\nAfter"
    let display = MarkdownEditorFormatter.formatForDisplay(
      markdown,
      appearance: appearance,
      interpretsSectionDirectives: false
    )

    XCTAssertNil(
      display.attribute(
        .markdownSectionDivider,
        at: (display.string as NSString).range(of: "<!-- section -->").location,
        effectiveRange: nil
      )
    )
    XCTAssertEqual(
      MarkdownEditorFormatter.convertToMarkdown(
        from: display,
        normalizesSectionDirectives: false
      ),
      markdown
    )
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

  // Drops an unmatched opening prompt marker without losing the following note text.
  func testOrphanedPromptStartMarkerIsRemoved() {
    XCTAssertEqual(
      preservedMarkdown("Intro\n<!-- prompt -->\nKeep this"),
      "Intro\nKeep this"
    )
  }

  // Drops an unmatched closing prompt marker instead of exposing its raw markdown.
  func testOrphanedPromptEndMarkerIsRemoved() {
    XCTAssertEqual(
      preservedMarkdown("Intro\n<!-- /prompt -->\nOutro"),
      "Intro\nOutro"
    )
  }
}
