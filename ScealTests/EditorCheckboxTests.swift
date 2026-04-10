import XCTest

@testable import Sceal

@MainActor
final class EditorCheckboxTests: EditorTestCase {
  // Prevents checkbox taps from losing the checked state or markdown output.
  func testToggleUpdatesRenderedStateAndMarkdown() {
    let fixture = makeEditorFixture(markdown: "- [ ] Task")
    let textView = fixture.textView

    guard let textStorage = textView.textStorage else {
      return XCTFail("Expected editor text storage.")
    }

    let checkboxLocation = firstCheckboxLocation(in: textStorage)
    let handled = textView.editorToggleCheckbox(
      at: checkboxLocation,
      appearanceSettings: appearance
    )

    XCTAssertTrue(handled)
    XCTAssertEqual(
      textStorage.attribute(
        .markdownListType,
        at: checkboxLocation,
        effectiveRange: nil
      ) as? String,
      MarkdownListType.checkboxChecked.rawValue
    )
    XCTAssertEqual(
      textStorage.attribute(.strikethroughStyle, at: checkboxLocation + 2, effectiveRange: nil)
        as? Int,
      NSUnderlineStyle.single.rawValue
    )
    XCTAssertEqual(MarkdownEditorFormatter.convertToMarkdown(from: textStorage), "- [x] Task")
  }

  // Prevents right-half checkbox clicks from missing the actual checkbox glyph.
  func testOffByOneHitStillTogglesCheckbox() {
    let fixture = makeEditorFixture(markdown: "- [ ] Task")
    let textView = fixture.textView

    guard let textStorage = textView.textStorage else {
      return XCTFail("Expected editor text storage.")
    }

    let checkboxLocation = firstCheckboxLocation(in: textStorage)
    let offsetIndex = checkboxLocation + 1

    let nsString = textStorage.string as NSString
    let lineRange = nsString.lineRange(for: NSRange(location: offsetIndex, length: 0))
    let resolvedIndex = lineRange.location

    XCTAssertEqual(
      resolvedIndex,
      checkboxLocation,
      "Line-start resolution should map the hit back to the checkbox glyph."
    )

    let handled = textView.editorToggleCheckbox(
      at: resolvedIndex,
      appearanceSettings: appearance
    )

    XCTAssertTrue(handled)
    XCTAssertEqual(
      textStorage.attribute(
        .markdownListType,
        at: resolvedIndex,
        effectiveRange: nil
      ) as? String,
      MarkdownListType.checkboxChecked.rawValue
    )
  }

  // Prevents a second toggle from leaving checkbox state half-updated.
  func testTogglingTwiceRestoresUncheckedState() {
    let fixture = makeEditorFixture(markdown: "- [ ] Task")
    let textView = fixture.textView

    guard let textStorage = textView.textStorage else {
      return XCTFail("Expected editor text storage.")
    }

    let checkboxLocation = firstCheckboxLocation(in: textStorage)

    XCTAssertTrue(
      textView.editorToggleCheckbox(at: checkboxLocation, appearanceSettings: appearance))
    XCTAssertTrue(
      textView.editorToggleCheckbox(at: checkboxLocation, appearanceSettings: appearance))

    XCTAssertEqual(
      textStorage.attribute(.markdownListType, at: checkboxLocation, effectiveRange: nil)
        as? String,
      MarkdownListType.checkboxUnchecked.rawValue
    )
    XCTAssertEqual(MarkdownEditorFormatter.convertToMarkdown(from: textStorage), "- [ ] Task")
  }

  // Prevents unchecked items from keeping stale strike-through styling.
  func testUncheckingRemovesStrikethrough() {
    let fixture = makeEditorFixture(markdown: "- [x] Task")
    let textView = fixture.textView

    guard let textStorage = textView.textStorage else {
      return XCTFail("Expected editor text storage.")
    }

    let checkboxLocation = firstCheckboxLocation(in: textStorage)
    let handled = textView.editorToggleCheckbox(
      at: checkboxLocation, appearanceSettings: appearance)

    XCTAssertTrue(handled)
    XCTAssertNil(
      textStorage.attribute(.strikethroughStyle, at: checkboxLocation + 2, effectiveRange: nil)
    )
    XCTAssertEqual(MarkdownEditorFormatter.convertToMarkdown(from: textStorage), "- [ ] Task")
  }

  // Prevents checkbox toggles inside colored sections from dropping the stored directive.
  func testTogglePreservesSectionColors() {
    let markdown = "<!-- section bullet:blue usesectioncolor:true -->\n- [ ] Task"
    let fixture = makeEditorFixture(markdown: markdown)
    let textView = fixture.textView

    guard let textStorage = textView.textStorage else {
      return XCTFail("Expected editor text storage.")
    }

    let checkboxLocation = firstCheckboxLocation(in: textStorage)
    let handled = textView.editorToggleCheckbox(
      at: checkboxLocation, appearanceSettings: appearance)

    XCTAssertTrue(handled)
    XCTAssertEqual(
      MarkdownEditorFormatter.convertToMarkdown(from: textStorage),
      "<!-- section bullet:blue usesectioncolor:true -->\n- [x] Task"
    )
  }
}
