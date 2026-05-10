import XCTest

@testable import Sceal

final class MarkdownEditorListMarkdownTests: XCTestCase {
  // Keeps bullet markers parsed while preserving the editor's canonical content.
  func testParsesBulletMarkers() throws {
    let dash = try XCTUnwrap(MarkdownEditorListMarkdown.parse("- item"))
    let star = try XCTUnwrap(MarkdownEditorListMarkdown.parse("* item"))
    let plus = try XCTUnwrap(MarkdownEditorListMarkdown.parse("+ item"))
    let bullet = try XCTUnwrap(MarkdownEditorListMarkdown.parse("• item"))

    XCTAssertEqual(dash.type, .bullet)
    XCTAssertEqual(star.type, .bullet)
    XCTAssertEqual(plus.type, .bullet)
    XCTAssertEqual(bullet.type, .bullet)
    XCTAssertEqual(dash.content, "item")
    XCTAssertEqual(star.content, "item")
    XCTAssertEqual(plus.content, "item")
    XCTAssertEqual(bullet.content, "item")
  }

  // Keeps checkbox markers classified so toggle behavior and markdown output stay aligned.
  func testParsesCheckboxMarkers() throws {
    let unchecked = try XCTUnwrap(MarkdownEditorListMarkdown.parse("- [ ] task"))
    let checked = try XCTUnwrap(MarkdownEditorListMarkdown.parse("- [x] task"))

    XCTAssertEqual(unchecked.type, .checkboxUnchecked)
    XCTAssertEqual(unchecked.content, "task")
    XCTAssertEqual(checked.type, .checkboxChecked)
    XCTAssertEqual(checked.content, "task")
  }

  // Keeps numbered list display text and marker length available for formatter styling.
  func testParsesNumberedMarker() throws {
    let line = try XCTUnwrap(MarkdownEditorListMarkdown.parse("12. item"))

    XCTAssertEqual(line.type, .numbered)
    XCTAssertEqual(line.content, "12. item")
    XCTAssertEqual(line.displayText, "12. item")
    XCTAssertEqual(line.orderedMarkerLength, 3)
  }

  // Keeps the existing indentation rules: two spaces or one tab per level, capped at three.
  func testParsesIndentationLevel() throws {
    let spaces = try XCTUnwrap(MarkdownEditorListMarkdown.parse("    - nested"))
    let tab = try XCTUnwrap(MarkdownEditorListMarkdown.parse("\t- nested"))
    let capped = try XCTUnwrap(MarkdownEditorListMarkdown.parse("        - nested"))

    XCTAssertEqual(spaces.indentLevel, 2)
    XCTAssertEqual(tab.indentLevel, 1)
    XCTAssertEqual(capped.indentLevel, 3)
  }

  // Keeps persisted prefixes canonical during display-to-markdown conversion.
  func testBuildsPersistedPrefixes() {
    XCTAssertEqual(
      MarkdownEditorListMarkdown.persistedPrefix(for: .bullet, indentLevel: 1),
      "  - "
    )
    XCTAssertEqual(
      MarkdownEditorListMarkdown.persistedPrefix(for: .checkboxUnchecked, indentLevel: 0),
      "- [ ] "
    )
    XCTAssertEqual(
      MarkdownEditorListMarkdown.persistedPrefix(for: .checkboxChecked, indentLevel: 2),
      "    - [x] "
    )
    XCTAssertNil(MarkdownEditorListMarkdown.persistedPrefix(for: .numbered, indentLevel: 0))
  }
}
