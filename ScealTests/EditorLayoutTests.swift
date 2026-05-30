import XCTest

@testable import Sceal

@MainActor
final class EditorLayoutTests: EditorTestCase {
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
