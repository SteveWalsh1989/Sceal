import XCTest

@testable import Sceal

final class MarkdownEditorHeadingColorMarkdownTests: XCTestCase {
  // Keeps persisted heading color markers parsed using the current marker shape.
  func testParsesHeadingColorMarker() {
    XCTAssertEqual(
      MarkdownEditorHeadingColorMarkdown.parseColorName("<!-- hcolor:turquoise -->"),
      "turquoise"
    )
    XCTAssertNil(MarkdownEditorHeadingColorMarkdown.parseColorName("<!-- hcolor:turquoise --> "))
    XCTAssertNil(MarkdownEditorHeadingColorMarkdown.parseColorName("<!-- color:turquoise -->"))
  }

  // Keeps heading color serialization aligned with existing saved markdown.
  func testBuildsHeadingColorMarker() {
    XCTAssertEqual(
      MarkdownEditorHeadingColorMarkdown.marker(colorName: "turquoise"),
      "<!-- hcolor:turquoise -->"
    )
  }
}
