import XCTest

@testable import Sceal

final class MarkdownEditorBlockMarkdownTests: XCTestCase {
  // Keeps heading marker parsing limited to the levels the editor renders.
  func testParsesSupportedHeadings() throws {
    let heading = try XCTUnwrap(MarkdownEditorBlockMarkdown.parseHeading("### Title"))

    XCTAssertEqual(heading.level, 3)
    XCTAssertEqual(heading.content, "Title")
    XCTAssertNil(MarkdownEditorBlockMarkdown.parseHeading("#### Too deep"))
  }

  // Keeps blockquote parsing aligned with the editor's single-level persisted form.
  func testParsesBlockquote() throws {
    let blockquote = try XCTUnwrap(MarkdownEditorBlockMarkdown.parseBlockquote("> quote"))

    XCTAssertEqual(blockquote.content, "quote")
    XCTAssertNil(MarkdownEditorBlockMarkdown.parseBlockquote(">"))
  }

  // Keeps code fence detection using the existing prefix rule, including language suffixes.
  func testDetectsCodeFencePrefix() {
    XCTAssertTrue(MarkdownEditorBlockMarkdown.isCodeFence("```"))
    XCTAssertTrue(MarkdownEditorBlockMarkdown.isCodeFence("```swift"))
    XCTAssertFalse(MarkdownEditorBlockMarkdown.isCodeFence(" ```"))
  }

  // Keeps horizontal rules limited to the exact dash-only shape currently rendered.
  func testDetectsHorizontalRule() {
    XCTAssertTrue(MarkdownEditorBlockMarkdown.isHorizontalRule("---"))
    XCTAssertTrue(MarkdownEditorBlockMarkdown.isHorizontalRule("----"))
    XCTAssertFalse(MarkdownEditorBlockMarkdown.isHorizontalRule("--"))
    XCTAssertFalse(MarkdownEditorBlockMarkdown.isHorizontalRule("- - -"))
  }

  // Keeps conversion prefixes centralized for persisted block markdown.
  func testBuildsPersistedPrefixes() {
    XCTAssertEqual(MarkdownEditorBlockMarkdown.headingPrefix(for: 2), "## ")
    XCTAssertEqual(MarkdownEditorBlockMarkdown.blockquotePrefix, "> ")
    XCTAssertEqual(MarkdownEditorBlockMarkdown.horizontalRuleMarker, "---")
  }
}
