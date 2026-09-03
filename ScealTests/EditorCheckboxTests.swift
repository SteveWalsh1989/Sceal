import SwiftUI
import XCTest

@testable import Sceal

@MainActor
final class EditorCheckboxTests: EditorTestCase {
  // Converts a multi-line bullet selection through the real formatting-toolbar action.
  func testFormattingToolbarConvertsSelectedBulletsToCheckboxes() {
    let fixture = makeEditorFixture(markdown: "- First\n- Second")
    let textView = fixture.textView
    let toolbar = EditorFormattingToolbar()
    toolbar.textView = textView
    toolbar.appearanceSettings = appearance
    textView.setSelectedRange(NSRange(location: 0, length: textView.textStorage?.length ?? 0))

    toolbar.perform(NSSelectorFromString("toggleCheckbox"))

    XCTAssertEqual(
      MarkdownEditorFormatter.convertToMarkdown(from: textView.textStorage ?? NSTextStorage()),
      "- [ ] First\n- [ ] Second"
    )
  }

  // Converts mixed list selections uniformly through every supported list style.
  func testFormattingToolbarConvertsMixedListTypesWithoutRetainingCheckedStyling() {
    let fixture = makeEditorFixture(markdown: "- First\n2. Second\n- [x] Third")
    let textView = fixture.textView
    let toolbar = EditorFormattingToolbar()
    toolbar.textView = textView
    toolbar.appearanceSettings = appearance
    textView.setSelectedRange(NSRange(location: 0, length: textView.textStorage?.length ?? 0))

    toolbar.perform(NSSelectorFromString("toggleCheckbox"))
    XCTAssertEqual(
      MarkdownEditorFormatter.convertToMarkdown(from: textView.textStorage ?? NSTextStorage()),
      "- [ ] First\n- [ ] Second\n- [ ] Third"
    )

    toolbar.perform(NSSelectorFromString("toggleNumbered"))
    XCTAssertEqual(
      MarkdownEditorFormatter.convertToMarkdown(from: textView.textStorage ?? NSTextStorage()),
      "1. First\n2. Second\n3. Third"
    )

    toolbar.perform(NSSelectorFromString("toggleBullet"))
    XCTAssertEqual(
      MarkdownEditorFormatter.convertToMarkdown(from: textView.textStorage ?? NSTextStorage()),
      "- First\n- Second\n- Third"
    )
  }

  // Applies a structured section's bullet color to the empty checkbox continued by Enter.
  func testChecklistContinuationUsesInitialSectionBulletColor() throws {
    let color = try XCTUnwrap(ThemePalette.color(named: "blue"))
    let markdown = MarkdownBox("- [ ] Task")
    let editor = MarkdownEditorView(
      noteID: "2026-09-03#section",
      text: Binding(
        get: { markdown.value },
        set: { markdown.value = $0 }
      ),
      appearanceSettings: appearance,
      debouncesMarkdownUpdates: false,
      initialSectionBulletColorName: "blue"
    )
    let coordinator = editor.makeCoordinator()
    let fixture = makeEditorFixture(
      displayString: MarkdownEditorFormatter.formatForDisplay(
        markdown.value,
        appearance: appearance,
        initialSectionBulletColorName: "blue"
      ))
    let textView = fixture.textView
    textView.delegate = coordinator
    textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))

    XCTAssertTrue(
      coordinator.textView(textView, doCommandBy: #selector(NSResponder.insertNewline(_:)))
    )
    let secondLineRange = (textView.string as NSString).lineRange(
      for: NSRange(location: textView.string.utf16.count, length: 0)
    )
    let attachment = try XCTUnwrap(
      textView.textStorage?.attribute(
        .attachment,
        at: secondLineRange.location,
        effectiveRange: nil
      ) as? NSTextAttachment
    )
    let expectedAttachment = MarkdownEditorFormatter.checkboxAttachment(
      checked: false,
      color: color
    )

    XCTAssertEqual(
      attachment.image?.tiffRepresentation, expectedAttachment.image?.tiffRepresentation)
    XCTAssertEqual(markdown.value, "- [ ] Task\n- [ ] ")
  }

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
