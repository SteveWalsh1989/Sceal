import AppKit
import XCTest

@testable import Sceal

@MainActor
final class EditorDividerTests: EditorTestCase {
  // Prevents divider replacements from leaving the caret past the rendered glyph.
  func testReplacingDividerClampsCaret() {
    let fixture = makeRawEditorFixture(string: "<!-- section -->")
    let textView = fixture.textView
    textView.setSelectedRange(NSRange(location: 16, length: 0))

    let handled = textView.performEditorEdit(
      affectedRange: NSRange(location: 0, length: 16),
      replacementString: MarkdownEditorFormatter.sectionDividerDisplayString().string,
      actionName: "Replace With Divider"
    ) { textStorage in
      textStorage.replaceCharacters(
        in: NSRange(location: 0, length: 16),
        with: MarkdownEditorFormatter.sectionDividerDisplayString()
      )
      return NSRange(location: 16, length: 0)
    }

    XCTAssertTrue(handled)
    XCTAssertEqual(textView.string, " ")
    XCTAssertEqual(textView.selectedRange(), NSRange(location: 1, length: 0))
  }

  // Prevents divider rendering from leaking raw markdown or spacing regressions.
  func testSectionDividerDisplayString() {
    let divider = MarkdownEditorFormatter.sectionDividerDisplayString()
    let paragraphStyle =
      divider.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle

    XCTAssertEqual(divider.string, " ")
    XCTAssertEqual(divider.length, 1)
    XCTAssertEqual(
      divider.attribute(.markdownSectionDivider, at: 0, effectiveRange: nil) as? Bool,
      true
    )
    XCTAssertEqual(
      paragraphStyle?.paragraphSpacingBefore,
      MarkdownEditorFormatter.sectionDividerSpacingBefore
    )
    XCTAssertEqual(
      paragraphStyle?.paragraphSpacing,
      MarkdownEditorFormatter.sectionDividerSpacingAfter
    )
    XCTAssertEqual(
      paragraphStyle?.maximumLineHeight,
      MarkdownEditorFormatter.sectionDividerLineHeight
    )
  }

  // Keeps the active section affordance attached to the divider above the caret.
  func testCaretInsideSectionResolvesPreviousDividerForActiveIcon() throws {
    let fixture = makeEditorFixture(
      markdown: "Intro\n<!-- section -->\nFirst\n<!-- section -->\nSecond")
    let textView = fixture.textView
    let textStorage = try XCTUnwrap(textView.textStorage)
    let dividerRanges = sectionDividerRanges(in: textStorage)
    let string = textView.string as NSString
    let firstSectionLocation = string.range(of: "First").location
    let secondSectionLocation = string.range(of: "Second").location

    XCTAssertEqual(dividerRanges.count, 2)
    XCTAssertEqual(
      textView.activeSectionDividerRange(
        forSelection: NSRange(location: firstSectionLocation, length: 0)),
      dividerRanges[0]
    )
    XCTAssertEqual(
      textView.activeSectionDividerRange(
        forSelection: NSRange(location: secondSectionLocation, length: 0)),
      dividerRanges[1]
    )
  }

  // Prevents the active section affordance from appearing outside editable section content.
  func testActiveSectionIconIgnoresPreDividerContentAndSelections() {
    let fixture = makeEditorFixture(markdown: "Intro\n<!-- section -->\nFirst")
    let textView = fixture.textView
    let string = textView.string as NSString
    let introLocation = string.range(of: "Intro").location
    let sectionLocation = string.range(of: "First").location

    XCTAssertNil(
      textView.activeSectionDividerRange(forSelection: NSRange(location: introLocation, length: 0))
    )
    XCTAssertNil(
      textView.activeSectionDividerRange(
        forSelection: NSRange(location: sectionLocation, length: 2))
    )
  }

  // Prevents notes ending in a divider from losing the trailing overscroll card.
  func testEndingWithDividerKeepsTrailingSectionForOverscroll() {
    let fixture = makeEditorFixture(markdown: "Body\n<!-- section -->")

    XCTAssertTrue(fixture.textView.debugHasTrailingSectionAfterFinalDivider)
  }

  // Prevents template color previews from ignoring the selected divider color.
  func testTemplateSectionColorPreviewColorsHeadingAndBullet() throws {
    let display = MarkdownEditorFormatter.formatForDisplay(
      "# Meeting:\n- Item",
      appearance: appearance,
      initialSectionHeadingColorName: "turquoise",
      initialSectionBulletColorName: "turquoise",
      initialSectionUseSectionColor: true
    )
    let expectedColor = try XCTUnwrap(ThemePalette.color(named: "turquoise"))
    let string = display.string as NSString
    let headingRange = string.range(of: "Meeting:")
    let bulletRange = string.range(of: MarkdownEditorFormatter.bulletMarker)

    XCTAssertNotEqual(headingRange.location, NSNotFound)
    XCTAssertNotEqual(bulletRange.location, NSNotFound)
    assertColor(
      display.attribute(.foregroundColor, at: headingRange.location, effectiveRange: nil)
        as? NSColor,
      matches: expectedColor
    )
    assertColor(
      display.attribute(.foregroundColor, at: bulletRange.location, effectiveRange: nil)
        as? NSColor,
      matches: expectedColor
    )
  }

  // Ensures template insertion can color plain bodies that do not store a leading divider.
  func testTemplateColorInsertionAddsLeadingSectionForPlainBody() {
    let markdown = NoteTemplateMarkdown.applyingTemplateOptions(
      to: "# Meeting:\n- Item",
      sectionColorName: "turquoise"
    )

    XCTAssertTrue(
      markdown.hasPrefix(
        "<!-- section heading:turquoise bullet:turquoise usesectioncolor:true -->\n# Meeting:"
      )
    )
  }

  // Keeps colored section markers using the heading color for list markers by default.
  func testSectionColorDefaultsToHeadingColorForBulletMarkers() throws {
    let display = MarkdownEditorFormatter.formatForDisplay(
      "<!-- section heading:turquoise -->\n# Meeting:\n- Item",
      appearance: appearance
    )
    let expectedColor = try XCTUnwrap(ThemePalette.color(named: "turquoise"))
    let string = display.string as NSString
    let headingRange = string.range(of: "Meeting:")
    let bulletRange = string.range(of: MarkdownEditorFormatter.bulletMarker)

    XCTAssertNotEqual(headingRange.location, NSNotFound)
    XCTAssertNotEqual(bulletRange.location, NSNotFound)
    assertColor(
      display.attribute(.foregroundColor, at: headingRange.location, effectiveRange: nil)
        as? NSColor,
      matches: expectedColor
    )
    assertColor(
      display.attribute(.foregroundColor, at: bulletRange.location, effectiveRange: nil)
        as? NSColor,
      matches: expectedColor
    )
  }

  // Keeps different-color mode applying the bullet color when same-color mode is off.
  func testSectionBulletColorAppliesWhenSameColorModeIsOff() throws {
    let display = MarkdownEditorFormatter.formatForDisplay(
      "<!-- section heading:turquoise bullet:pink usesectioncolor:false -->\n# Meeting:\n- Item",
      appearance: appearance
    )
    let headingColor = try XCTUnwrap(ThemePalette.color(named: "turquoise"))
    let bulletColor = try XCTUnwrap(ThemePalette.color(named: "pink"))
    let string = display.string as NSString
    let headingRange = string.range(of: "Meeting:")
    let bulletRange = string.range(of: MarkdownEditorFormatter.bulletMarker)

    XCTAssertNotEqual(headingRange.location, NSNotFound)
    XCTAssertNotEqual(bulletRange.location, NSNotFound)
    assertColor(
      display.attribute(.foregroundColor, at: headingRange.location, effectiveRange: nil)
        as? NSColor,
      matches: headingColor
    )
    assertColor(
      display.attribute(.foregroundColor, at: bulletRange.location, effectiveRange: nil)
        as? NSColor,
      matches: bulletColor
    )
  }

  // Prevents backspace from leaving a hidden section marker above the caret.
  func testBackspaceBelowDividerRemovesIt() {
    let markdown = MarkdownBox("<!-- section -->\nBody")
    let coordinator = makeCoordinator(markdown: markdown)
    let fixture = makeEditorFixture(markdown: markdown.value)
    let textView = fixture.textView
    let bodyLocation = (textView.string as NSString).range(of: "Body").location

    XCTAssertNotEqual(bodyLocation, NSNotFound)

    textView.delegate = coordinator
    textView.setSelectedRange(NSRange(location: bodyLocation, length: 0))

    let handled = coordinator.textView(
      textView,
      doCommandBy: #selector(NSResponder.deleteBackward(_:))
    )

    XCTAssertTrue(handled)
    XCTAssertEqual(markdown.value, "Body")
    XCTAssertEqual(textView.sectionDividerCount, 0)
    XCTAssertEqual(textView.selectedRange(), NSRange(location: 0, length: 0))
  }

  // Prevents divider selection from trapping the caret on non-editable content.
  func testSelectingDividerMovesCaretForward() {
    let fixture = makeEditorFixture(markdown: "Before\n<!-- section -->\nAfter")
    let textView = fixture.textView

    guard let textStorage = textView.textStorage else {
      return XCTFail("Expected editor text storage.")
    }

    let dividerRange = firstSectionDividerRange(in: textStorage)
    let dividerLineRange = (textView.string as NSString).lineRange(for: dividerRange)

    textView.setSelectedRange(NSRange(location: dividerRange.location, length: 0))
    let normalized = textView.editorNormalizeSelectionIfNeeded(prefer: .next)

    XCTAssertTrue(normalized)
    XCTAssertEqual(
      textView.selectedRange(),
      NSRange(location: NSMaxRange(dividerLineRange), length: 0)
    )
  }

  // Prevents upper-half divider clicks from skipping the previous editable line.
  func testSelectingDividerMovesCaretBackward() {
    let fixture = makeEditorFixture(markdown: "Before\n<!-- section -->\nAfter")
    let textView = fixture.textView

    guard let textStorage = textView.textStorage else {
      return XCTFail("Expected editor text storage.")
    }

    let dividerRange = firstSectionDividerRange(in: textStorage)

    textView.setSelectedRange(NSRange(location: dividerRange.location, length: 0))
    let normalized = textView.editorNormalizeSelectionIfNeeded(prefer: .previous)

    XCTAssertTrue(normalized)
    XCTAssertEqual(textView.selectedRange(), NSRange(location: "Before".utf16.count, length: 0))
  }

  private func assertColor(
    _ actualColor: NSColor?,
    matches expectedColor: NSColor,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    guard
      let actual = actualColor?.usingColorSpace(.deviceRGB),
      let expected = expectedColor.usingColorSpace(.deviceRGB)
    else {
      return XCTFail("Expected colors to be convertible to device RGB.", file: file, line: line)
    }

    XCTAssertEqual(
      actual.redComponent, expected.redComponent, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(
      actual.greenComponent,
      expected.greenComponent,
      accuracy: 0.001,
      file: file,
      line: line
    )
    XCTAssertEqual(
      actual.blueComponent, expected.blueComponent, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(
      actual.alphaComponent, expected.alphaComponent, accuracy: 0.001, file: file, line: line)
  }

  // Collects rendered section dividers in document order.
  private func sectionDividerRanges(
    in textStorage: NSTextStorage,
    file: StaticString = #filePath,
    line: UInt = #line
  ) -> [NSRange] {
    let fullRange = NSRange(location: 0, length: textStorage.length)
    var ranges: [NSRange] = []

    textStorage.enumerateAttribute(.markdownSectionDivider, in: fullRange, options: []) {
      value,
      range,
      _ in
      guard value as? Bool == true else { return }
      ranges.append((textStorage.string as NSString).lineRange(for: range))
    }

    if ranges.isEmpty {
      XCTFail("Expected rendered section dividers.", file: file, line: line)
    }
    return ranges
  }
}
