import AppKit
import SwiftUI
import XCTest

@testable import Sceal

@MainActor
final class EditorSlashCommandTests: EditorTestCase {
  // Routes `/div` to a structural split and removes the command row from both section bodies.
  func testStructuredDividerCommandReturnsMarkdownAndSplitOffset() async throws {
    let rawMarkdown = "# Before\n/div\nAfter"
    let markdown = MarkdownBox(rawMarkdown)
    var splitMarkdown: String?
    var splitOffset: Int?
    let splitExpectation = expectation(description: "Structured split callback")
    let editor = MarkdownEditorView(
      noteID: "2026-09-01#section",
      text: Binding(
        get: { markdown.value },
        set: { markdown.value = $0 }
      ),
      appearanceSettings: appearance,
      allowsSlashCommands: false,
      interpretsSectionDirectives: false,
      onStructuredSectionSplit: { returnedMarkdown, returnedOffset in
        splitMarkdown = returnedMarkdown
        splitOffset = returnedOffset
        splitExpectation.fulfill()
      }
    )
    let coordinator = editor.makeCoordinator()
    let fixture = makeEditorFixture(
      displayString: MarkdownEditorFormatter.formatForDisplay(
        rawMarkdown,
        appearance: appearance,
        interpretsSectionDirectives: false
      )
    )
    let textView = fixture.textView
    textView.delegate = coordinator
    let commandRange = (textView.string as NSString).range(of: "/div")
    textView.setSelectedRange(NSRange(location: NSMaxRange(commandRange), length: 0))

    XCTAssertTrue(
      coordinator.textView(textView, doCommandBy: #selector(NSResponder.insertNewline(_:)))
    )
    await fulfillment(of: [splitExpectation], timeout: 1)

    XCTAssertEqual(splitMarkdown, "# BeforeAfter")
    XCTAssertEqual(splitOffset, "# Before".utf16.count)
    let resolvedMarkdown = try XCTUnwrap(splitMarkdown)
    let resolvedOffset = try XCTUnwrap(splitOffset)

    let originalStyle = StructuredSectionStyleOverrides(
      headingColor: .colorName("blue")
    )
    var document = StructuredNoteDocument(
      id: "2026-09-01",
      date: Date(timeIntervalSince1970: 1_788_220_800),
      title: "",
      tags: [],
      nodes: [
        .section(
          StructuredNoteSection(
            markdown: resolvedMarkdown,
            styleOverrides: originalStyle
          ))
      ]
    )
    guard case .section(let section) = document.nodes[0] else {
      return XCTFail("Expected root section")
    }
    _ = try document.insertBlankSection(id: section.id, atUTF16Offset: resolvedOffset)
    XCTAssertEqual(document.nodes.compactMap(sectionMarkdown), ["# Before", "", "After"])
    XCTAssertEqual(
      document.nodes.compactMap(sectionStyle), [originalStyle, .inherited, originalStyle])
  }

  // Keeps the legacy `/section` alias structural and hidden from persisted section content.
  func testStructuredSectionAliasReturnsStructuralSplit() async {
    let markdown = MarkdownBox("Before\n/section\nAfter")
    var splitMarkdown: String?
    let splitExpectation = expectation(description: "Structured alias split callback")
    let editor = MarkdownEditorView(
      noteID: "2026-09-02#section",
      text: Binding(
        get: { markdown.value },
        set: { markdown.value = $0 }
      ),
      appearanceSettings: appearance,
      allowsSlashCommands: false,
      interpretsSectionDirectives: false,
      onStructuredSectionSplit: { returnedMarkdown, _ in
        splitMarkdown = returnedMarkdown
        splitExpectation.fulfill()
      }
    )
    let coordinator = editor.makeCoordinator()
    let fixture = makeRawEditorFixture(string: markdown.value)
    fixture.textView.delegate = coordinator
    let commandRange = (fixture.textView.string as NSString).range(of: "/section")
    fixture.textView.setSelectedRange(NSRange(location: NSMaxRange(commandRange), length: 0))

    XCTAssertTrue(
      coordinator.textView(
        fixture.textView,
        doCommandBy: #selector(NSResponder.insertNewline(_:))
      )
    )
    await fulfillment(of: [splitExpectation], timeout: 1)

    XCTAssertEqual(splitMarkdown, "BeforeAfter")
    XCTAssertFalse(splitMarkdown?.contains("/section") == true)
    XCTAssertFalse(splitMarkdown?.contains("<!-- section") == true)
  }

  // Runs popup completion through the structured split callback instead of inserting a marker.
  func testStructuredDividerPopupSelectionCreatesStructuralRequest() async throws {
    let markdown = MarkdownBox("Before\n/di\nAfter")
    var splitMarkdown: String?
    let splitExpectation = expectation(description: "Structured popup split callback")
    let editor = MarkdownEditorView(
      noteID: "2026-09-02#section",
      text: Binding(
        get: { markdown.value },
        set: { markdown.value = $0 }
      ),
      appearanceSettings: appearance,
      allowsSlashCommands: true,
      interpretsSectionDirectives: false,
      onStructuredSectionSplit: { returnedMarkdown, _ in
        splitMarkdown = returnedMarkdown
        splitExpectation.fulfill()
      }
    )
    let coordinator = editor.makeCoordinator()
    let fixture = makeRawEditorFixture(string: markdown.value)
    fixture.textView.delegate = coordinator
    let commandRange = (fixture.textView.string as NSString).range(of: "/di")
    fixture.textView.setSelectedRange(NSRange(location: NSMaxRange(commandRange), length: 0))
    coordinator.textDidChange(
      Notification(name: NSText.didChangeNotification, object: fixture.textView)
    )

    XCTAssertTrue(
      coordinator.textView(
        fixture.textView,
        doCommandBy: #selector(NSResponder.insertNewline(_:))
      )
    )
    await fulfillment(of: [splitExpectation], timeout: 1)

    XCTAssertEqual(splitMarkdown, "BeforeAfter")
    XCTAssertFalse(splitMarkdown?.contains("<!-- section") == true)
  }

  // Sends a popup-selected custom snippet to structured conversion rather than legacy insertion.
  func testStructuredCustomTemplatePopupReturnsInsertionRequest() async throws {
    let template = NoteTemplate.starterMeeting
    let markdown = MarkdownBox("/me")
    var insertionRequest: StructuredTemplateInsertionRequest?
    let insertionExpectation = expectation(description: "Structured template callback")
    let editor = MarkdownEditorView(
      noteID: "2026-09-02#section",
      text: Binding(
        get: { markdown.value },
        set: { markdown.value = $0 }
      ),
      appearanceSettings: appearance,
      customSlashTemplates: [template],
      allowsSlashCommands: true,
      interpretsSectionDirectives: false,
      onStructuredTemplateInsert: { request in
        insertionRequest = request
        insertionExpectation.fulfill()
      }
    )
    let coordinator = editor.makeCoordinator()
    let fixture = makeRawEditorFixture(string: markdown.value)
    fixture.textView.delegate = coordinator
    fixture.textView.setSelectedRange(NSRange(location: markdown.value.utf16.count, length: 0))
    coordinator.textDidChange(
      Notification(name: NSText.didChangeNotification, object: fixture.textView)
    )

    XCTAssertTrue(
      coordinator.textView(
        fixture.textView,
        doCommandBy: #selector(NSResponder.insertNewline(_:))
      )
    )
    await fulfillment(of: [insertionExpectation], timeout: 1)

    XCTAssertEqual(insertionRequest?.template, template)
    XCTAssertEqual(insertionRequest?.leadingMarkdown, "")
    XCTAssertEqual(insertionRequest?.trailingMarkdown, "")
    XCTAssertFalse(markdown.value.contains("<!-- section"))
  }

  // Keeps the panel on-screen and routes keyboard and pointer choices through one selection path.
  func testSlashPopupPlacementAndKeyboardSelection() {
    let visibleFrame = NSRect(x: 100, y: 100, width: 320, height: 300)
    let popupFrame = EditorSlashCommandPopupPlacement.frame(
      relativeTo: NSRect(x: 400, y: 108, width: 2, height: 18),
      visibleFrame: visibleFrame,
      width: 210,
      contentHeight: 260,
      minimumHeight: 44
    )

    XCTAssertGreaterThanOrEqual(popupFrame.minX, visibleFrame.minX)
    XCTAssertLessThanOrEqual(popupFrame.maxX, visibleFrame.maxX)
    XCTAssertGreaterThanOrEqual(popupFrame.minY, visibleFrame.minY)
    XCTAssertLessThanOrEqual(popupFrame.maxY, visibleFrame.maxY)

    let popup = EditorSlashCommandPopup()
    var selectedCommand: String?
    popup.onSelect = { selectedCommand = $0.command }
    popup.updateFilter("/")
    popup.moveSelectionDown()
    popup.confirmSelection()
    XCTAssertEqual(selectedCommand, "/heading-1")

    popup.updateFilter("/pro")
    popup.selectCommand(at: 0)
    XCTAssertEqual(selectedCommand, "/prompt")
  }

  // Reads Markdown only from section nodes for the structured split assertion.
  private func sectionMarkdown(_ node: StructuredNoteNode) -> String? {
    guard case .section(let section) = node else { return nil }
    return section.markdown
  }

  // Reads appearance overrides only from section nodes for style-isolation assertions.
  private func sectionStyle(_ node: StructuredNoteNode) -> StructuredSectionStyleOverrides? {
    guard case .section(let section) = node else { return nil }
    return section.styleOverrides
  }

  // Finds a rendered prompt boundary by kind for interaction assertions.
  private func firstPromptBoundaryRange(
    in textStorage: NSTextStorage,
    kind expectedKind: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) -> NSRange {
    let fullRange = NSRange(location: 0, length: textStorage.length)
    var match: NSRange?
    textStorage.enumerateAttribute(
      .markdownPromptBoundaryKind,
      in: fullRange,
      options: []
    ) { value, range, stop in
      guard value as? String == expectedKind else { return }
      match = range
      stop.pointee = true
    }

    guard let match else {
      XCTFail("Expected a rendered prompt boundary.", file: file, line: line)
      return NSRange(location: 0, length: 0)
    }
    return match
  }

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

  // Confirms prompt slash commands insert a hidden-marker block and place typing inside it.
  private func assertPromptBlockCommand(
    command: String,
    primesSlashPopup: Bool,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let markdown = MarkdownBox(command)
    let coordinator = makeCoordinator(markdown: markdown)
    let fixture = makeRawEditorFixture(string: command)
    let textView = fixture.textView
    let expectedMarkdown =
      "\(MarkdownEditorFormatter.promptBlockStartMarker)\n\n\(MarkdownEditorFormatter.promptBlockEndMarker)"

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
    XCTAssertEqual(markdown.value, expectedMarkdown, file: file, line: line)
    XCTAssertEqual(
      MarkdownEditorFormatter.convertToMarkdown(from: textView.textStorage!),
      expectedMarkdown,
      file: file,
      line: line
    )
    XCTAssertFalse(textView.string.contains(MarkdownEditorFormatter.promptBlockStartMarker))
    XCTAssertFalse(textView.string.contains(MarkdownEditorFormatter.promptBlockEndMarker))
    XCTAssertEqual(
      textView.typingAttributes[.markdownPromptBlock] as? Bool, true, file: file, line: line)
    XCTAssertEqual(
      textView.selectedRange(), NSRange(location: 2, length: 0), file: file, line: line)
  }

  // Prevents the direct divider command from drifting away from the shipped insertion path.
  func testDirectDivider() {
    assertSectionDividerInserted(command: "/div", primesSlashPopup: false)
  }

  // Prevents popup-confirmed divider selection from behaving differently than direct entry.
  func testPopupDividerSelection() {
    assertSectionDividerInserted(command: "/di", primesSlashPopup: true)
  }

  // Keeps the hidden section alias compatible with direct slash entry.
  func testHiddenSectionAliasMatchesDivider() {
    assertSectionDividerInserted(command: "/section", primesSlashPopup: false)
  }

  // Prevents the deprecated section alias from appearing in the visible popup list.
  func testSectionAliasIsHiddenFromPopup() {
    let commands = EditorSlashCommandHandler.filteredCommands(for: "/").map(\.command)
    XCTAssertTrue(commands.contains("/div"))
    XCTAssertFalse(commands.contains("/section"))
  }

  // Prevents custom templates from being omitted from the shared slash popup.
  func testCustomTemplateAppearsInSlashPopup() {
    let template = NoteTemplate(
      title: "Meeting",
      command: "meeting",
      menuDescription: "Insert meeting note structure",
      body: "# Meeting:"
    )

    let entries = EditorSlashCommandHandler.filteredCommands(
      for: "/me",
      customTemplates: [template]
    )

    XCTAssertEqual(entries.map(\.command), ["/meeting"])
    XCTAssertEqual(entries.first?.description, "Insert meeting note structure")
  }

  // Prevents disabled templates from being offered as executable slash commands.
  func testDisabledCustomTemplateIsHiddenFromSlashPopup() {
    let template = NoteTemplate(
      title: "Meeting",
      command: "meeting",
      body: "# Meeting:",
      isEnabled: false
    )

    let entries = EditorSlashCommandHandler.filteredCommands(
      for: "/me",
      customTemplates: [template]
    )

    XCTAssertTrue(entries.isEmpty)
  }

  // Confirms custom template commands insert formatted markdown and place the caret intelligently.
  func testDirectCustomTemplateCommand() {
    let template = NoteTemplate.starterMeeting
    let markdown = MarkdownBox("/meeting")
    let coordinator = makeCoordinator(markdown: markdown, customSlashTemplates: [template])
    let fixture = makeRawEditorFixture(string: "/meeting")
    let textView = fixture.textView

    textView.delegate = coordinator
    textView.setSelectedRange(NSRange(location: "/meeting".utf16.count, length: 0))

    let handled = coordinator.textView(
      textView,
      doCommandBy: #selector(NSResponder.insertNewline(_:))
    )

    XCTAssertTrue(handled)
    XCTAssertEqual(markdown.value, template.resolvedBodyForInsertion)
    XCTAssertFalse(textView.string.contains("/meeting"))
    let meetingRange = (textView.string as NSString).range(of: "Meeting:")
    XCTAssertEqual(textView.selectedRange().location, NSMaxRange(meetingRange))
    XCTAssertEqual(textView.typingAttributes[.markdownHeadingLevel] as? Int, 1)
  }

  // Prevents a second divider after template content from corrupting the compact editor document.
  func testDividerCommandAfterSectionContent() {
    let initial = "<!-- section -->\nBody\n/div"
    let markdown = MarkdownBox(initial)
    let coordinator = makeCoordinator(markdown: markdown)
    let fixture = makeEditorFixture(markdown: initial)
    let textView = fixture.textView

    textView.delegate = coordinator
    textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))

    let handled = coordinator.textView(
      textView,
      doCommandBy: #selector(NSResponder.insertNewline(_:))
    )

    XCTAssertTrue(handled)
    XCTAssertEqual(markdown.value, "<!-- section -->\nBody\n<!-- section -->")
    XCTAssertEqual(textView.sectionDividerCount, 2)
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

  // Prevents direct prompt block slash entry from exposing hidden storage markers.
  func testDirectPromptBlock() {
    assertPromptBlockCommand(command: "/prompt", primesSlashPopup: false)
  }

  // Prevents popup prompt block confirmation from diverging from direct slash entry.
  func testPopupPromptBlock() {
    assertPromptBlockCommand(command: "/pro", primesSlashPopup: true)
  }

  // Confirms prompt blocks grow as users add lines inside the box.
  func testPromptBlockContinuesPlainTextOnNewline() {
    let command = "/prompt"
    let markdown = MarkdownBox(command)
    let coordinator = makeCoordinator(markdown: markdown)
    let fixture = makeRawEditorFixture(string: command)
    let textView = fixture.textView

    textView.delegate = coordinator
    textView.setSelectedRange(NSRange(location: command.utf16.count, length: 0))

    XCTAssertTrue(
      coordinator.textView(textView, doCommandBy: #selector(NSResponder.insertNewline(_:))))

    let firstInsertLocation = textView.selectedRange().location
    XCTAssertTrue(
      textView.performEditorEdit(
        replacementString: "First line",
        actionName: "Insert Prompt Text"
      ) { textStorage in
        let text = NSAttributedString(
          string: "First line",
          attributes: textView.typingAttributes
        )
        textStorage.replaceCharacters(
          in: NSRange(location: firstInsertLocation, length: 0),
          with: text
        )
        return NSRange(location: firstInsertLocation + text.length, length: 0)
      }
    )

    XCTAssertTrue(
      coordinator.textView(textView, doCommandBy: #selector(NSResponder.insertNewline(_:))))
    XCTAssertEqual(textView.typingAttributes[.markdownPromptBlock] as? Bool, true)

    let secondInsertLocation = textView.selectedRange().location
    XCTAssertTrue(
      textView.performEditorEdit(
        replacementString: "Second line",
        actionName: "Insert Prompt Text"
      ) { textStorage in
        let text = NSAttributedString(
          string: "Second line",
          attributes: textView.typingAttributes
        )
        textStorage.replaceCharacters(
          in: NSRange(location: secondInsertLocation, length: 0),
          with: text
        )
        return NSRange(location: secondInsertLocation + text.length, length: 0)
      }
    )

    XCTAssertEqual(
      MarkdownEditorFormatter.convertToMarkdown(from: textView.textStorage!),
      """
      <!-- prompt -->
      First line
      Second line
      <!-- /prompt -->
      """
    )
  }

  // Prevents pasted prompt text from being interpreted as markdown formatting.
  func testPromptBlockPastePreservesMarkdownCharacters() {
    let command = "/prompt"
    let markdown = MarkdownBox(command)
    let coordinator = makeCoordinator(markdown: markdown)
    let fixture = makeRawEditorFixture(string: command)
    let textView = fixture.textView

    textView.delegate = coordinator
    textView.setSelectedRange(NSRange(location: command.utf16.count, length: 0))

    XCTAssertTrue(
      coordinator.textView(textView, doCommandBy: #selector(NSResponder.insertNewline(_:))))

    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString("**literal**", forType: .string)
    textView.paste(nil)

    XCTAssertEqual(
      MarkdownEditorFormatter.convertToMarkdown(from: textView.textStorage!),
      """
      <!-- prompt -->
      **literal**
      <!-- /prompt -->
      """
    )
  }

  // Preserves text attached to the hidden header glyph when copying an older affected prompt.
  func testPromptBlockCopyIncludesTextBesideStartBoundary() {
    let markdown = """
      <!-- prompt -->
      Second line
      <!-- /prompt -->
      """
    let fixture = makeEditorFixture(markdown: markdown)
    let textView = fixture.textView

    guard let textStorage = textView.textStorage else {
      return XCTFail("Expected editor text storage.")
    }

    let startBoundaryRange = firstPromptBoundaryRange(
      in: textStorage,
      kind: MarkdownEditorPromptBlockMarkdown.startBoundaryKind
    )
    let attachedText = NSAttributedString(
      string: "Top line",
      attributes: [
        .font: appearance.bodyFont,
        .foregroundColor: NSColor.labelColor,
        .paragraphStyle: MarkdownEditorFormatter.promptBlockParagraphStyle(for: appearance),
        .markdownPromptBlock: true,
      ]
    )
    textStorage.insert(attachedText, at: NSMaxRange(startBoundaryRange))

    NSPasteboard.general.clearContents()
    XCTAssertTrue(textView.copyPromptBlock(containing: startBoundaryRange.location))
    XCTAssertEqual(
      NSPasteboard.general.string(forType: .string),
      "Top line\nSecond line"
    )
    XCTAssertEqual(
      MarkdownEditorFormatter.convertToMarkdown(from: textStorage),
      """
      <!-- prompt -->
      Top line
      Second line
      <!-- /prompt -->
      """
    )
  }

  // Keeps the caret out of the prompt action row so new text starts in editable content.
  func testPromptBoundarySelectionRedirectsToContent() {
    let fixture = makeEditorFixture(markdown: MarkdownEditorPromptBlockMarkdown.emptyBlock)
    let textView = fixture.textView

    guard let textStorage = textView.textStorage else {
      return XCTFail("Expected editor text storage.")
    }

    let startBoundaryRange = firstPromptBoundaryRange(
      in: textStorage,
      kind: MarkdownEditorPromptBlockMarkdown.startBoundaryKind
    )
    let startLineRange = (textStorage.string as NSString).lineRange(for: startBoundaryRange)
    textView.setSelectedRange(NSRange(location: NSMaxRange(startBoundaryRange), length: 0))

    XCTAssertTrue(textView.editorNormalizeSelectionIfNeeded())
    XCTAssertEqual(
      textView.selectedRange(),
      NSRange(location: NSMaxRange(startLineRange), length: 0)
    )
    XCTAssertFalse(textView.allowsTextChangeNearPromptBoundaries(in: startLineRange))
  }

  // Prevents the prompt close button path from leaving hidden markers or block text behind.
  func testPromptBlockDeleteRemovesWholeBlock() {
    let initialMarkdown = """
      Intro
      <!-- prompt -->
      Delete this
      <!-- /prompt -->
      Outro
      """
    let markdown = MarkdownBox(initialMarkdown)
    let coordinator = makeCoordinator(markdown: markdown)
    let fixture = makeEditorFixture(markdown: initialMarkdown)
    let textView = fixture.textView
    textView.delegate = coordinator

    guard let textStorage = textView.textStorage else {
      return XCTFail("Expected editor text storage.")
    }

    let fullRange = NSRange(location: 0, length: textStorage.length)
    var promptLocation: Int?
    textStorage.enumerateAttribute(.markdownPromptBoundary, in: fullRange, options: []) {
      value, range, stop in
      guard value as? Bool == true else { return }
      promptLocation = range.location
      stop.pointee = true
    }

    guard let promptLocation else {
      return XCTFail("Expected rendered prompt block.")
    }

    XCTAssertTrue(textView.deletePromptBlock(containing: promptLocation))
    XCTAssertEqual(
      MarkdownEditorFormatter.convertToMarkdown(from: textView.textStorage!),
      """
      Intro
      Outro
      """
    )
    XCTAssertEqual(markdown.value, "Intro\nOutro")
  }

  // Deletes selected text and a prompt as one safe edit with no orphan boundary markers.
  func testBackspaceDeletesSelectionContainingPromptBlock() {
    let initialMarkdown = """
      Intro
      <!-- prompt -->
      Delete this
      <!-- /prompt -->
      Outro
      """
    let markdown = MarkdownBox(initialMarkdown)
    let coordinator = makeCoordinator(markdown: markdown)
    let fixture = makeEditorFixture(markdown: initialMarkdown)
    let textView = fixture.textView
    textView.delegate = coordinator

    guard let textStorage = textView.textStorage else {
      return XCTFail("Expected editor text storage.")
    }
    let endBoundaryRange = firstPromptBoundaryRange(
      in: textStorage,
      kind: MarkdownEditorPromptBlockMarkdown.endBoundaryKind
    )
    let endBoundaryLineRange = (textStorage.string as NSString).lineRange(for: endBoundaryRange)
    textView.setSelectedRange(
      NSRange(location: 0, length: NSMaxRange(endBoundaryLineRange))
    )

    XCTAssertTrue(
      coordinator.textView(textView, doCommandBy: #selector(NSResponder.deleteBackward(_:)))
    )
    XCTAssertEqual(
      MarkdownEditorFormatter.convertToMarkdown(from: textStorage),
      "Outro"
    )
    XCTAssertEqual(markdown.value, "Outro")
    XCTAssertTrue(textView.allowsTextChangeNearPromptBoundaries(in: textView.selectedRange()))
  }

  // Gives forward deletion the same protected selection behavior as Backspace.
  func testForwardDeleteRemovesSelectionContainingPromptBlock() {
    let initialMarkdown = """
      Intro
      <!-- prompt -->
      Delete this
      <!-- /prompt -->
      Outro
      """
    let markdown = MarkdownBox(initialMarkdown)
    let coordinator = makeCoordinator(markdown: markdown)
    let fixture = makeEditorFixture(markdown: initialMarkdown)
    let textView = fixture.textView
    textView.delegate = coordinator
    textView.setSelectedRange(NSRange(location: 0, length: textView.string.utf16.count))

    XCTAssertTrue(
      coordinator.textView(textView, doCommandBy: #selector(NSResponder.deleteForward(_:)))
    )
    XCTAssertEqual(markdown.value, "")
    XCTAssertEqual(textView.string, "")
  }

  // Prevents clearing a prompt from removing its reusable block boundaries.
  func testPromptBlockClearRetainsEmptyBlock() {
    let initialMarkdown = """
      Intro
      <!-- prompt -->
      First line
      Second line
      <!-- /prompt -->
      Outro
      """
    let markdown = MarkdownBox(initialMarkdown)
    let coordinator = makeCoordinator(markdown: markdown)
    let fixture = makeEditorFixture(markdown: initialMarkdown)
    let textView = fixture.textView
    textView.delegate = coordinator

    guard let textStorage = textView.textStorage else {
      return XCTFail("Expected editor text storage.")
    }

    let fullRange = NSRange(location: 0, length: textStorage.length)
    var promptLocation: Int?
    textStorage.enumerateAttribute(.markdownPromptBoundary, in: fullRange, options: []) {
      value, range, stop in
      guard value as? Bool == true else { return }
      promptLocation = range.location
      stop.pointee = true
    }

    guard let promptLocation else {
      return XCTFail("Expected rendered prompt block.")
    }

    XCTAssertTrue(textView.clearPromptBlock(containing: promptLocation))
    XCTAssertEqual(
      MarkdownEditorFormatter.convertToMarkdown(from: textView.textStorage!),
      """
      Intro
      <!-- prompt -->

      <!-- /prompt -->
      Outro
      """
    )
    XCTAssertEqual(
      markdown.value,
      """
      Intro
      <!-- prompt -->

      <!-- /prompt -->
      Outro
      """
    )
  }
}
