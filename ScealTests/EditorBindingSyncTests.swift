import AppKit
import SwiftUI
import XCTest

@testable import Sceal

@MainActor
final class EditorBindingSyncTests: EditorTestCase {
  func testProgrammaticUpdateDoesNotPushDisplayedMarkdownToBinding() throws {
    let markdown = MarkdownBox("Original body")
    let coordinator = makeCoordinator(markdown: markdown)
    let fixture = makeEditorFixture(markdown: markdown.value)
    let textView = fixture.textView
    textView.delegate = coordinator

    let replacement = MarkdownEditorFormatter.formatForDisplay(
      "Replacement\n\n<!-- section -->\n\nStill visible",
      appearance: appearance
    )

    coordinator.performProgrammaticUpdate {
      _ = coordinator.textView(
        textView,
        shouldChangeTextIn: NSRange(location: 0, length: textView.string.utf16.count),
        replacementString: replacement.string
      )
      textView.textStorage?.setAttributedString(replacement)
      coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
    }

    XCTAssertEqual(markdown.value, "Original body")
  }

  func testProgrammaticPromptBlockReplacementKeepsPromptContentRenderable() throws {
    let markdown = MarkdownBox("Original body")
    let coordinator = makeCoordinator(markdown: markdown)
    let fixture = makeEditorFixture(markdown: markdown.value)
    let textView = fixture.textView
    textView.delegate = coordinator

    let replacement = MarkdownEditorFormatter.formatForDisplay(
      """
      <!-- prompt -->
      Saved prompt text that should be visible before focus
      <!-- /prompt -->
      """,
      appearance: appearance
    )

    coordinator.performProgrammaticUpdate {
      textView.textStorage?.setAttributedString(replacement)
      textView.ensureEditorLayoutForEntireDocument()
    }

    guard let textStorage = textView.textStorage else {
      return XCTFail("Expected editor text storage.")
    }

    let promptRanges = promptBlockContentRanges(in: textStorage)
    XCTAssertFalse(promptRanges.isEmpty)
    for range in promptRanges {
      XCTAssertTrue(textView.editorHasVisibleGlyphs(forCharacterRange: range))
    }
    XCTAssertEqual(markdown.value, "Original body")
  }

  func testLayoutOnlyTextDidChangeDoesNotPushMarkdownWithoutEditorEdit() throws {
    let markdown = MarkdownBox("Body\n\n<!-- section -->\n\nMore body")
    let coordinator = makeCoordinator(markdown: markdown)
    let fixture = makeEditorFixture(markdown: markdown.value)
    let textView = fixture.textView
    textView.delegate = coordinator

    textView.textStorage?.addAttribute(
      .kern,
      value: 0,
      range: NSRange(location: 0, length: textView.string.utf16.count)
    )
    coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

    XCTAssertEqual(markdown.value, "Body\n\n<!-- section -->\n\nMore body")
  }

  func testEditorEditStillPushesMarkdownBinding() throws {
    let markdown = MarkdownBox("Body")
    let coordinator = makeCoordinator(markdown: markdown)
    let fixture = makeEditorFixture(markdown: markdown.value)
    let textView = fixture.textView
    textView.delegate = coordinator

    let inserted = textView.performEditorEdit(
      affectedRange: NSRange(location: textView.string.utf16.count, length: 0),
      replacementString: " added",
      actionName: "Insert Text"
    ) { textStorage in
      let location = textStorage.length
      textStorage.replaceCharacters(
        in: NSRange(location: location, length: 0),
        with: NSAttributedString(
          string: " added",
          attributes: MarkdownEditorFormatter.baseTypingAttributes(for: appearance)
        )
      )
      return NSRange(location: location + " added".utf16.count, length: 0)
    }

    XCTAssertTrue(inserted)
    coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
    guard let textStorage = textView.textStorage else {
      XCTFail("Expected editor text storage.")
      return
    }
    coordinator.flushPendingMarkdownPushIfNeeded(from: textStorage)

    XCTAssertEqual(markdown.value, "Body added")
  }

  func testProgrammaticUpdateDoesNotCancelPendingEditorEdit() throws {
    let markdown = MarkdownBox("Body")
    let coordinator = makeCoordinator(markdown: markdown)
    let fixture = makeEditorFixture(markdown: markdown.value)
    let textView = fixture.textView
    textView.delegate = coordinator

    _ = textView.performEditorEdit(
      affectedRange: NSRange(location: textView.string.utf16.count, length: 0),
      replacementString: " pending",
      actionName: "Insert Text"
    ) { textStorage in
      let location = textStorage.length
      textStorage.replaceCharacters(
        in: NSRange(location: location, length: 0),
        with: NSAttributedString(
          string: " pending",
          attributes: MarkdownEditorFormatter.baseTypingAttributes(for: appearance)
        )
      )
      return NSRange(location: location + " pending".utf16.count, length: 0)
    }
    coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

    coordinator.performProgrammaticUpdate {}

    guard let textStorage = textView.textStorage else {
      XCTFail("Expected editor text storage.")
      return
    }

    XCTAssertEqual(coordinator.flushPendingMarkdownPushIfNeeded(from: textStorage), "Body pending")
    XCTAssertEqual(markdown.value, "Body pending")
  }

  func testTableBlockEditStillPushesMarkdownBinding() throws {
    let table = MarkdownEditorTable(
      runtimeID: "test-table",
      hasHeader: true,
      columnWidths: [
        MarkdownEditorTable.defaultColumnWidth,
        MarkdownEditorTable.defaultColumnWidth,
      ],
      rows: [["Task", "Owner"], ["Ship fix", "Steve"]]
    )
    let markdown = MarkdownBox(MarkdownEditorTableMarkdown.serialize(table))
    let coordinator = makeCoordinator(markdown: markdown)
    let fixture = makeEditorFixture(markdown: markdown.value)
    let textView = fixture.textView
    textView.delegate = coordinator

    textView.isApplyingTableBlockEdit = true
    coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
    textView.isApplyingTableBlockEdit = false
    guard let textStorage = textView.textStorage else {
      XCTFail("Expected editor text storage.")
      return
    }
    coordinator.flushPendingMarkdownPushIfNeeded(from: textStorage)

    XCTAssertTrue(markdown.value.contains("Ship fix"))
  }

  private func promptBlockContentRanges(in textStorage: NSTextStorage) -> [NSRange] {
    var ranges: [NSRange] = []
    textStorage.enumerateAttribute(
      .markdownPromptBlock,
      in: NSRange(location: 0, length: textStorage.length),
      options: []
    ) { value, range, _ in
      if value as? Bool == true {
        ranges.append(range)
      }
    }
    return ranges
  }
}
