import SwiftUI
import XCTest

@testable import Sceal

@MainActor
final class EditorLayoutTests: EditorTestCase {
  // Keeps the toolbar visually above a selection in flipped and non-flipped containers.
  func testFormattingToolbarPlacementAccountsForCoordinateDirection() {
    let parentBounds = NSRect(x: 0, y: 0, width: 500, height: 300)
    let selectionRect = NSRect(x: 200, y: 120, width: 40, height: 20)
    let toolbarSize = NSSize(width: 100, height: 34)

    let flippedOrigin = EditorFormattingToolbarLayout.origin(
      selectionRect: selectionRect,
      toolbarSize: toolbarSize,
      parentBounds: parentBounds,
      parentIsFlipped: true
    )
    let nonFlippedOrigin = EditorFormattingToolbarLayout.origin(
      selectionRect: selectionRect,
      toolbarSize: toolbarSize,
      parentBounds: parentBounds,
      parentIsFlipped: false
    )

    XCTAssertLessThan(flippedOrigin.y + toolbarSize.height, selectionRect.minY)
    XCTAssertGreaterThan(nonFlippedOrigin.y, selectionRect.maxY)
  }

  // Moves the toolbar below the selection when the visual area above it is unavailable.
  func testFormattingToolbarPlacementFallsBackBelowSelection() {
    let parentBounds = NSRect(x: 0, y: 0, width: 500, height: 300)
    let toolbarSize = NSSize(width: 100, height: 34)
    let flippedSelection = NSRect(x: 200, y: 2, width: 40, height: 20)
    let nonFlippedSelection = NSRect(x: 200, y: 278, width: 40, height: 20)

    let flippedOrigin = EditorFormattingToolbarLayout.origin(
      selectionRect: flippedSelection,
      toolbarSize: toolbarSize,
      parentBounds: parentBounds,
      parentIsFlipped: true
    )
    let nonFlippedOrigin = EditorFormattingToolbarLayout.origin(
      selectionRect: nonFlippedSelection,
      toolbarSize: toolbarSize,
      parentBounds: parentBounds,
      parentIsFlipped: false
    )

    XCTAssertGreaterThan(flippedOrigin.y, flippedSelection.maxY)
    XCTAssertLessThan(nonFlippedOrigin.y + toolbarSize.height, nonFlippedSelection.minY)
  }

  // Prevents separate structured section editors from showing competing toolbars.
  func testShowingFormattingToolbarHidesPreviouslyVisibleToolbar() {
    let parentView = NSView(frame: NSRect(x: 0, y: 0, width: 1_000, height: 400))
    let selectionRect = NSRect(x: 400, y: 180, width: 80, height: 20)
    let firstToolbar = EditorFormattingToolbar()
    let secondToolbar = EditorFormattingToolbar()

    firstToolbar.show(relativeTo: selectionRect, in: parentView)
    XCTAssertFalse(firstToolbar.isHidden)

    secondToolbar.show(relativeTo: selectionRect, in: parentView)
    XCTAssertTrue(firstToolbar.isHidden)
    XCTAssertFalse(secondToolbar.isHidden)

    secondToolbar.hide()
  }

  // Prevents tiny windows from losing the minimum scroll room below the note.
  func testBottomOverscrollUsesMinimumForSmallViewport() {
    XCTAssertEqual(MarkdownEditorView.bottomOverscrollHeight(for: 240), 300)
  }

  // Prevents large windows from getting a cramped end-of-document scroll area.
  func testBottomOverscrollScalesForLargeViewport() {
    XCTAssertEqual(MarkdownEditorView.bottomOverscrollHeight(for: 1200), 900)
  }

  // Prevents long documents from clipping the intended scroll-past-end padding.
  func testTargetEditorHeightAddsBottomOverscroll() {
    XCTAssertEqual(
      MarkdownEditorView.targetEditorHeight(documentHeight: 1600, viewportHeight: 1200),
      2500
    )
  }

  // Keeps empty section editors usable while allowing longer content to grow to exact points.
  func testContentSizedEditorHeightUsesMinimumAndRoundsContentUp() {
    XCTAssertEqual(
      MarkdownEditorView.targetContentSizedEditorHeight(
        documentHeight: 42,
        minimumHeight: 132
      ),
      132
    )
    XCTAssertEqual(
      MarkdownEditorView.targetContentSizedEditorHeight(
        documentHeight: 188.2,
        minimumHeight: 132
      ),
      189
    )
  }

  // Transfers left, right, up, and down only when the caret reaches a section edge.
  func testStructuredBoundaryCommandsNavigateAdjacentSections() {
    let markdown = MarkdownBox("First\nSecond")
    var navigations: [StructuredEditorBoundaryNavigation] = []
    let editor = MarkdownEditorView(
      noteID: "2026-09-01#section",
      text: Binding(
        get: { markdown.value },
        set: { markdown.value = $0 }
      ),
      appearanceSettings: appearance,
      onBoundaryNavigation: { direction in
        navigations.append(direction)
        return true
      }
    )
    let coordinator = editor.makeCoordinator()
    let fixture = makeRawEditorFixture(string: markdown.value)
    let textView = fixture.textView
    textView.delegate = coordinator

    textView.setSelectedRange(NSRange(location: 0, length: 0))
    XCTAssertTrue(coordinator.textView(textView, doCommandBy: #selector(NSResponder.moveLeft(_:))))
    XCTAssertTrue(coordinator.textView(textView, doCommandBy: #selector(NSResponder.moveUp(_:))))

    textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
    XCTAssertTrue(
      coordinator.textView(textView, doCommandBy: #selector(NSResponder.moveRight(_:))))
    XCTAssertTrue(
      coordinator.textView(textView, doCommandBy: #selector(NSResponder.moveDown(_:))))

    XCTAssertEqual(
      navigations,
      [.previousSectionEnd, .previousSectionEnd, .nextSectionStart, .nextSectionStart]
    )
  }

  // Keeps Backspace at offset zero from deleting or merging a structural section boundary.
  func testStructuredBackspaceAtSectionStartIsConsumed() {
    let markdown = MarkdownBox("Content")
    let editor = MarkdownEditorView(
      noteID: "2026-09-01#section",
      text: Binding(
        get: { markdown.value },
        set: { markdown.value = $0 }
      ),
      appearanceSettings: appearance,
      onBoundaryNavigation: { _ in false }
    )
    let coordinator = editor.makeCoordinator()
    let fixture = makeRawEditorFixture(string: markdown.value)
    let textView = fixture.textView
    textView.delegate = coordinator
    textView.setSelectedRange(NSRange(location: 0, length: 0))

    XCTAssertTrue(
      coordinator.textView(textView, doCommandBy: #selector(NSResponder.deleteBackward(_:))))
    XCTAssertEqual(textView.string, "Content")
  }

  // Routes structural Command-Z shortcuts before NSTextView's local undo handling.
  func testStructuredUndoShortcutsUseConfiguredHandlers() throws {
    let fixture = makeRawEditorFixture(string: "Content")
    let textView = fixture.textView
    var undoCount = 0
    var redoCount = 0
    textView.onStructuredUndo = {
      undoCount += 1
      return true
    }
    textView.onStructuredRedo = {
      redoCount += 1
      return true
    }

    let undoEvent = try XCTUnwrap(keyEvent(modifiers: [.command]))
    let redoEvent = try XCTUnwrap(keyEvent(modifiers: [.command, .shift]))
    textView.keyDown(with: undoEvent)
    textView.keyDown(with: redoEvent)

    XCTAssertEqual(undoCount, 1)
    XCTAssertEqual(redoCount, 1)
  }

  // Keeps pasted prompt text below the action row and inside the prompt box.
  func testPromptBlockLongUnbrokenTextStaysInsidePromptContentArea() {
    let longToken = String(repeating: "abcdefghijklmnopqrstuvwxyz", count: 8)
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
    XCTAssertTrue(NSPasteboard.general.setString(longToken, forType: .string))
    textView.paste(nil)

    let narrowWidth: CGFloat = 260
    textView.setFrameSize(NSSize(width: narrowWidth, height: textView.frame.height))
    textView.textContainer?.containerSize = NSSize(
      width: max(narrowWidth - textView.textContainerInset.width * 2, 1),
      height: CGFloat.greatestFiniteMagnitude
    )
    textView.ensureEditorLayoutForEntireDocument()
    textView.layoutSubtreeIfNeeded()

    guard let textStorage = textView.textStorage else {
      return XCTFail("Expected editor text storage.")
    }
    let contentRange = firstPromptContentRange(in: textStorage)
    let startBoundaryRange = firstPromptStartBoundaryRange(in: textStorage)

    guard let contentRect = textView.editorRectInViewCoordinates(forCharacterRange: contentRange),
      let startBoundaryRect = textView.editorRectInViewCoordinates(
        forCharacterRange: startBoundaryRange)
    else {
      return XCTFail("Expected prompt block layout rects.")
    }

    let promptBoxRightEdge =
      narrowWidth - MarkdownEditorPromptBlockLayout.blockHorizontalInset
      - MarkdownEditorPromptBlockLayout.closeButtonLaneWidth
    let promptContentRightEdge =
      promptBoxRightEdge - MarkdownEditorPromptBlockLayout.textHorizontalInset
    let copyButtonMaxY =
      startBoundaryRect.minY + MarkdownEditorPromptBlockLayout.copyButtonTopOffset
      + MarkdownEditorPromptBlockLayout.copyButtonHeight

    XCTAssertGreaterThanOrEqual(contentRect.minY, copyButtonMaxY - 1)
    XCTAssertLessThanOrEqual(contentRect.maxX, promptContentRightEdge + 1)
  }

  // Keeps live typing constrained after an empty prompt block is reloaded.
  func testReloadedEmptyPromptBlockTypingStaysInsidePromptContentArea() {
    let markdown = MarkdownBox(MarkdownEditorPromptBlockMarkdown.emptyBlock)
    let coordinator = makeCoordinator(markdown: markdown)
    let fixture = makeEditorFixture(markdown: markdown.value)
    let textView = fixture.textView
    guard let textStorage = textView.textStorage else {
      return XCTFail("Expected editor text storage.")
    }
    let startBoundaryRange = firstPromptStartBoundaryRange(in: textStorage)
    let startLineRange = (textView.string as NSString).lineRange(for: startBoundaryRange)
    let insertionRange = NSRange(location: NSMaxRange(startLineRange), length: 0)

    textView.delegate = coordinator
    textView.setSelectedRange(insertionRange)
    coordinator.syncTypingAttributesToCurrentSelection(in: textView)

    XCTAssertEqual(textView.typingAttributes[.markdownPromptBlock] as? Bool, true)

    let longToken = String(repeating: "abcdefghijklmnopqrstuvwxyz", count: 8)
    textView.insertText(longToken, replacementRange: insertionRange)

    let narrowWidth: CGFloat = 260
    textView.setFrameSize(NSSize(width: narrowWidth, height: textView.frame.height))
    textView.textContainer?.containerSize = NSSize(
      width: max(narrowWidth - textView.textContainerInset.width * 2, 1),
      height: CGFloat.greatestFiniteMagnitude
    )
    textView.ensureEditorLayoutForEntireDocument()
    textView.layoutSubtreeIfNeeded()

    guard
      let contentRect = textView.editorRectInViewCoordinates(
        forCharacterRange: firstPromptContentRange(in: textStorage))
    else {
      return XCTFail("Expected prompt content layout rect.")
    }

    let promptContentRightEdge =
      narrowWidth - MarkdownEditorPromptBlockLayout.blockHorizontalInset
      - MarkdownEditorPromptBlockLayout.closeButtonLaneWidth
      - MarkdownEditorPromptBlockLayout.textHorizontalInset
    XCTAssertLessThanOrEqual(contentRect.maxX, promptContentRightEdge + 1)
  }

  private func firstPromptContentRange(
    in textStorage: NSTextStorage,
    file: StaticString = #filePath,
    line: UInt = #line
  ) -> NSRange {
    let fullRange = NSRange(location: 0, length: textStorage.length)
    var match: NSRange?
    textStorage.enumerateAttribute(.markdownPromptBlock, in: fullRange, options: []) {
      value, range, stop in
      guard value as? Bool == true else { return }
      match = range
      stop.pointee = true
    }

    guard let match else {
      XCTFail("Expected prompt block content.", file: file, line: line)
      return NSRange(location: 0, length: 0)
    }
    return match
  }

  private func keyEvent(modifiers: NSEvent.ModifierFlags) -> NSEvent? {
    NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: modifiers,
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      characters: "z",
      charactersIgnoringModifiers: "z",
      isARepeat: false,
      keyCode: 6
    )
  }

  private func firstPromptStartBoundaryRange(
    in textStorage: NSTextStorage,
    file: StaticString = #filePath,
    line: UInt = #line
  ) -> NSRange {
    let fullRange = NSRange(location: 0, length: textStorage.length)
    var match: NSRange?
    textStorage.enumerateAttribute(.markdownPromptBoundaryKind, in: fullRange, options: []) {
      value, range, stop in
      guard
        let kind = value as? String,
        MarkdownEditorPromptBlockMarkdown.isStartBoundaryKind(kind)
      else { return }
      match = range
      stop.pointee = true
    }

    guard let match else {
      XCTFail("Expected prompt block start boundary.", file: file, line: line)
      return NSRange(location: 0, length: 0)
    }
    return match
  }
}
