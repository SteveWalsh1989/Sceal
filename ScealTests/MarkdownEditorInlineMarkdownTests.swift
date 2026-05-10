import XCTest

@testable import Sceal

final class MarkdownEditorInlineMarkdownTests: XCTestCase {
  // Keeps plain inline spans untouched during conversion.
  func testSerializesPlainSpan() {
    XCTAssertEqual(
      MarkdownEditorInlineMarkdown.serializedSpan(
        text: "plain",
        isBold: false,
        isItalic: false,
        isStrikethrough: false,
        isCode: false,
        linkURL: nil
      ),
      "plain"
    )
  }

  // Keeps combined bold and italic spans in the current compact delimiter form.
  func testSerializesBoldItalicSpan() {
    XCTAssertEqual(
      MarkdownEditorInlineMarkdown.serializedSpan(
        text: "strong emphasis",
        isBold: true,
        isItalic: true,
        isStrikethrough: false,
        isCode: false,
        linkURL: nil
      ),
      "***strong emphasis***"
    )
  }

  // Keeps links nested inside emphasis delimiters when both attributes are present.
  func testSerializesBoldLinkSpan() {
    XCTAssertEqual(
      MarkdownEditorInlineMarkdown.serializedSpan(
        text: "docs",
        isBold: true,
        isItalic: false,
        isStrikethrough: false,
        isCode: false,
        linkURL: "https://example.com"
      ),
      "**[docs](https://example.com)**"
    )
  }

  // Keeps strikethrough wrapping the already serialized inner inline markdown.
  func testSerializesStrikethroughAroundInlineCode() {
    XCTAssertEqual(
      MarkdownEditorInlineMarkdown.serializedSpan(
        text: "code",
        isBold: true,
        isItalic: false,
        isStrikethrough: true,
        isCode: true,
        linkURL: "https://example.com"
      ),
      "~~`code`~~"
    )
  }
}
