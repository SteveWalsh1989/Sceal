import XCTest

@testable import Sceal

final class MarkdownEditorSectionDirectiveTests: XCTestCase {
  // Keeps the plain persisted section divider marker recognized as an empty directive.
  func testParsesPlainSectionMarker() throws {
    let directive = try XCTUnwrap(
      MarkdownEditorSectionDirectiveMarkdown.parse("<!-- section -->")
    )

    XCTAssertNil(directive.headingColorName)
    XCTAssertNil(directive.bulletColorName)
    XCTAssertFalse(directive.usesSectionColor)
  }

  // Keeps per-section color metadata parsed from the current persisted marker shape.
  func testParsesColoredSectionMarker() throws {
    let directive = try XCTUnwrap(
      MarkdownEditorSectionDirectiveMarkdown.parse(
        "<!-- section heading:blue bullet:turquoise usesectioncolor:true -->"
      )
    )

    XCTAssertEqual(directive.headingColorName, "blue")
    XCTAssertEqual(directive.bulletColorName, "turquoise")
    XCTAssertTrue(directive.usesSectionColor)
  }

  // Keeps section serialization canonical by omitting false color-use flags.
  func testSerializesSectionMarkerWithoutFalseFlag() {
    XCTAssertEqual(
      MarkdownEditorSectionDirectiveMarkdown.marker(
        headingColorName: "blue",
        bulletColorName: "blue",
        usesSectionColor: false
      ),
      "<!-- section heading:blue bullet:blue -->"
    )
  }

  // Keeps parser and serializer behavior aligned for colored section dividers.
  func testSectionMarkerRoundTrip() throws {
    let original = MarkdownEditorSectionDirective(
      headingColorName: "blue",
      bulletColorName: "blue",
      usesSectionColor: true
    )
    let marker = MarkdownEditorSectionDirectiveMarkdown.marker(for: original)

    XCTAssertEqual(
      marker,
      "<!-- section heading:blue bullet:blue usesectioncolor:true -->"
    )
    XCTAssertEqual(try XCTUnwrap(MarkdownEditorSectionDirectiveMarkdown.parse(marker)), original)
  }
}
