import AppKit
import XCTest

@testable import Sceal

@MainActor
final class EditorSlashCommandTests: EditorTestCase {
  // Confirms divider slash commands replace the raw shortcut with the rendered divider path.
  private func assertSectionDividerInserted(
    command: String,
    primesSlashPopup: Bool,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let markdown = MarkdownBox(command)
    let coordinator = makeCoordinator(markdown: markdown)
    let fixture = makeRawEditorFixture(string: command)
    let textView = fixture.textView

    XCTAssertNotNil(textView.textLayoutManager, file: file, line: line)

    textView.delegate = coordinator
    textView.setSelectedRange(NSRange(location: command.utf16.count, length: 0))

    if primesSlashPopup {
      coordinator.textDidChange(
        Notification(name: NSText.didChangeNotification, object: textView)
      )
    }

    let handled = coordinator.textView(
      textView, doCommandBy: #selector(NSResponder.insertNewline(_:)))

    XCTAssertTrue(handled, file: file, line: line)
    XCTAssertEqual(markdown.value, "<!-- section -->", file: file, line: line)
    XCTAssertEqual(textView.sectionDividerCount, 1, file: file, line: line)
    XCTAssertFalse(textView.string.contains(command), file: file, line: line)
    XCTAssertFalse(textView.string.contains("<!-- section -->"), file: file, line: line)

    guard let textStorage = textView.textStorage else {
      XCTFail("Expected editor text storage.", file: file, line: line)
      return
    }

    let dividerRange = firstSectionDividerRange(in: textStorage, file: file, line: line)
    XCTAssertEqual(dividerRange.length, 1, file: file, line: line)

    let dividerLineRange = (textView.string as NSString).lineRange(for: dividerRange)
    XCTAssertGreaterThanOrEqual(
      textView.selectedRange().location,
      NSMaxRange(dividerLineRange),
      file: file,
      line: line
    )
  }

  // Confirms heading slash commands clear the raw line and seed heading typing attributes.
  private func assertHeadingCommand(
    command: String,
    expectedLevel: Int,
    primesSlashPopup: Bool,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let markdown = MarkdownBox(command)
    let coordinator = makeCoordinator(markdown: markdown)
    let fixture = makeRawEditorFixture(string: command)
    let textView = fixture.textView

    textView.delegate = coordinator
    textView.setSelectedRange(NSRange(location: command.utf16.count, length: 0))

    if primesSlashPopup {
      coordinator.textDidChange(
        Notification(name: NSText.didChangeNotification, object: textView)
      )
    }

    let handled = coordinator.textView(
      textView, doCommandBy: #selector(NSResponder.insertNewline(_:)))

    XCTAssertTrue(handled, file: file, line: line)
    coordinator.textViewDidChangeSelection(
      Notification(name: NSTextView.didChangeSelectionNotification, object: textView)
    )
    XCTAssertEqual(markdown.value, "", file: file, line: line)
    XCTAssertEqual(
      textView.typingAttributes[.markdownHeadingLevel] as? Int,
      expectedLevel,
      file: file,
      line: line
    )

    let insertLocation = textView.selectedRange().location
    let inserted = textView.performEditorEdit(
      replacementString: "Title",
      actionName: "Insert Heading Text"
    ) { textStorage in
      let insertRange = NSRange(location: insertLocation, length: 0)
      let headingText = NSAttributedString(
        string: "Title",
        attributes: textView.typingAttributes
      )
      textStorage.replaceCharacters(in: insertRange, with: headingText)
      return NSRange(location: insertLocation + headingText.length, length: 0)
    }

    XCTAssertTrue(inserted, file: file, line: line)
    XCTAssertEqual(
      MarkdownEditorFormatter.convertToMarkdown(from: textView.textStorage!),
      "\(String(repeating: "#", count: expectedLevel)) Title",
      file: file,
      line: line
    )
  }

  // Confirms code block slash commands insert a fenced block and place typing inside it.
  private func assertCodeBlockCommand(
    command: String,
    primesSlashPopup: Bool,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let markdown = MarkdownBox(command)
    let coordinator = makeCoordinator(markdown: markdown)
    let fixture = makeRawEditorFixture(string: command)
    let textView = fixture.textView

    textView.delegate = coordinator
    textView.setSelectedRange(NSRange(location: command.utf16.count, length: 0))

    if primesSlashPopup {
      coordinator.textDidChange(
        Notification(name: NSText.didChangeNotification, object: textView)
      )
    }

    let handled = coordinator.textView(
      textView, doCommandBy: #selector(NSResponder.insertNewline(_:)))

    XCTAssertTrue(handled, file: file, line: line)
    XCTAssertEqual(markdown.value, "```\n\n\n```", file: file, line: line)
    XCTAssertEqual(
      MarkdownEditorFormatter.convertToMarkdown(from: textView.textStorage!),
      "```\n\n\n```",
      file: file,
      line: line
    )
    XCTAssertEqual(
      textView.typingAttributes[.markdownCodeBlock] as? Bool, true, file: file, line: line)
    XCTAssertEqual(
      textView.selectedRange(), NSRange(location: 4, length: 0), file: file, line: line)
  }

  // Prevents the direct divider command from drifting away from the shipped insertion path.
  func testDirectDivider() {
    assertSectionDividerInserted(command: "/div", primesSlashPopup: false)
  }

  // Prevents popup-confirmed divider selection from behaving differently than direct entry.
  func testPopupDividerSelection() {
    assertSectionDividerInserted(command: "/di", primesSlashPopup: true)
  }

  // Prevents the section alias from diverging from the main divider command.
  func testSectionAliasMatchesDivider() {
    assertSectionDividerInserted(command: "/section", primesSlashPopup: false)
  }

  // Prevents the direct heading command from losing heading level 1 typing state.
  func testDirectHeading1() {
    assertHeadingCommand(command: "/heading-1", expectedLevel: 1, primesSlashPopup: false)
  }

  // Prevents popup heading confirmation from losing heading level 2 typing state.
  func testPopupHeading2() {
    assertHeadingCommand(command: "/heading-2", expectedLevel: 2, primesSlashPopup: true)
  }

  // Prevents heading level 2 from regressing while level 1 remains green.
  func testDirectHeading2() {
    assertHeadingCommand(command: "/heading-2", expectedLevel: 2, primesSlashPopup: false)
  }

  // Prevents heading level 3 from regressing while lower levels still pass.
  func testDirectHeading3() {
    assertHeadingCommand(command: "/heading-3", expectedLevel: 3, primesSlashPopup: false)
  }

  // Prevents popup heading level 1 from drifting away from direct heading behavior.
  func testPopupHeading1() {
    assertHeadingCommand(command: "/heading-1", expectedLevel: 1, primesSlashPopup: true)
  }

  // Prevents end-of-note heading insertion from dropping the next typed heading text.
  func testDirectHeading1AtDocumentEnd() {
    let initial = "Intro\n/heading-1"
    let markdown = MarkdownBox(initial)
    let coordinator = makeCoordinator(markdown: markdown)
    let fixture = makeRawEditorFixture(string: initial)
    let textView = fixture.textView

    textView.delegate = coordinator
    textView.setSelectedRange(NSRange(location: initial.utf16.count, length: 0))

    let handled = coordinator.textView(
      textView, doCommandBy: #selector(NSResponder.insertNewline(_:)))

    XCTAssertTrue(handled)
    coordinator.textViewDidChangeSelection(
      Notification(name: NSTextView.didChangeSelectionNotification, object: textView)
    )
    XCTAssertEqual(textView.typingAttributes[.markdownHeadingLevel] as? Int, 1)

    let insertLocation = textView.selectedRange().location
    _ = textView.performEditorEdit(
      replacementString: "Title",
      actionName: "Insert Heading Text"
    ) { textStorage in
      let insertRange = NSRange(location: insertLocation, length: 0)
      let headingText = NSAttributedString(
        string: "Title",
        attributes: textView.typingAttributes
      )
      textStorage.replaceCharacters(in: insertRange, with: headingText)
      return NSRange(location: insertLocation + headingText.length, length: 0)
    }

    XCTAssertEqual(
      MarkdownEditorFormatter.convertToMarkdown(from: textView.textStorage!),
      "Intro\n# Title"
    )
  }

  // Prevents pending heading typing from disappearing after a display refresh pass.
  func testPendingHeadingTypingSurvivesDisplayRefresh() {
    let initial = "Intro\n/heading-1"
    let markdown = MarkdownBox(initial)
    let coordinator = makeCoordinator(markdown: markdown)
    let fixture = makeRawEditorFixture(string: initial)
    let textView = fixture.textView

    textView.delegate = coordinator
    textView.setSelectedRange(NSRange(location: initial.utf16.count, length: 0))

    let handled = coordinator.textView(
      textView, doCommandBy: #selector(NSResponder.insertNewline(_:)))
    XCTAssertTrue(handled)

    guard let textStorage = textView.textStorage else {
      return XCTFail("Expected editor text storage.")
    }

    let markdownAfterCommand = MarkdownEditorFormatter.convertToMarkdown(from: textStorage)
    textStorage.setAttributedString(
      MarkdownEditorFormatter.formatForDisplay(markdownAfterCommand, appearance: appearance))
    let clampedLocation = min(textView.selectedRange().location, textView.string.utf16.count)
    textView.setSelectedRange(NSRange(location: clampedLocation, length: 0))
    coordinator.textViewDidChangeSelection(
      Notification(name: NSTextView.didChangeSelectionNotification, object: textView)
    )

    let insertLocation = textView.selectedRange().location
    let inserted = textView.performEditorEdit(
      replacementString: "T",
      actionName: "Insert Heading Character"
    ) { textStorage in
      let insertRange = NSRange(location: insertLocation, length: 0)
      let character = NSAttributedString(
        string: "T",
        attributes: textView.typingAttributes
      )
      textStorage.replaceCharacters(in: insertRange, with: character)
      return NSRange(location: insertLocation + character.length, length: 0)
    }

    XCTAssertTrue(inserted)
    XCTAssertEqual(
      textStorage.attribute(.markdownHeadingLevel, at: insertLocation, effectiveRange: nil)
        as? Int,
      1
    )
  }

  // Prevents direct code block slash entry from regressing while headings still work.
  func testDirectCodeBlock() {
    assertCodeBlockCommand(command: "/code", primesSlashPopup: false)
  }

  // Prevents popup code block confirmation from diverging from direct slash entry.
  func testPopupCodeBlock() {
    assertCodeBlockCommand(command: "/co", primesSlashPopup: true)
  }
}
