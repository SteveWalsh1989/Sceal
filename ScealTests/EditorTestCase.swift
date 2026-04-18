import AppKit
import SwiftUI
import XCTest

@testable import Sceal

@MainActor
class EditorTestCase: XCTestCase {
  let appearance = NoteAppearanceSettings.default

  final class MarkdownBox {
    var value: String

    init(_ value: String = "") {
      self.value = value
    }
  }

  struct EditorFixture {
    let textView: MarkdownEditorTextView
    let scrollView: NSScrollView
  }

  // Builds a coordinator wired to a mutable markdown binding for editor interaction tests.
  func makeCoordinator(markdown: MarkdownBox) -> MarkdownEditorView.Coordinator {
    let editor = MarkdownEditorView(
      noteID: "2026-04-04",
      text: Binding(
        get: { markdown.value },
        set: { markdown.value = $0 }
      ),
      appearanceSettings: appearance
    )
    return editor.makeCoordinator()
  }

  // Builds a display-formatted editor fixture from raw markdown.
  func makeEditorFixture(markdown: String) -> EditorFixture {
    makeEditorFixture(
      displayString: MarkdownEditorFormatter.formatForDisplay(markdown, appearance: appearance))
  }

  // Builds a raw attributed editor fixture without markdown display formatting.
  func makeRawEditorFixture(string: String) -> EditorFixture {
    makeEditorFixture(
      displayString: NSAttributedString(
        string: string,
        attributes: MarkdownEditorFormatter.baseTypingAttributes(for: appearance)
      ))
  }

  // Builds the full TextKit 2 editor and scroll view pair used in interaction tests.
  func makeEditorFixture(displayString: NSAttributedString) -> EditorFixture {
    let textView = MarkdownEditorTextView(usingTextLayoutManager: true)
    textView.frame = NSRect(x: 0, y: 0, width: 420, height: 240)
    configure(textView)
    textView.textStorage?.setAttributedString(displayString)

    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 420, height: 240))
    scrollView.documentView = textView
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.drawsBackground = false
    scrollView.automaticallyAdjustsContentInsets = false
    scrollView.contentInsets = .init()

    textView.ensureEditorLayoutForEntireDocument()
    let targetHeight = MarkdownEditorView.targetEditorHeight(
      documentHeight: textView.editorDocumentHeight(),
      viewportHeight: scrollView.contentSize.height
    )
    textView.minSize = NSSize(width: 0, height: targetHeight)
    textView.setFrameSize(NSSize(width: textView.frame.width, height: targetHeight))
    scrollView.layoutSubtreeIfNeeded()
    textView.layoutSubtreeIfNeeded()

    return EditorFixture(textView: textView, scrollView: scrollView)
  }

  // Applies the same editor configuration used by the production AppKit host.
  func configure(_ textView: MarkdownEditorTextView) {
    MarkdownEditorView.configureTextView(
      textView,
      appearanceSettings: appearance,
      continuousSpellCheckingEnabled: true,
      delegate: nil
    )
    textView.typingAttributes = MarkdownEditorFormatter.baseTypingAttributes(for: appearance)
  }

  // Finds the first rendered divider so tests can assert selection and layout behavior.
  func firstSectionDividerRange(
    in textStorage: NSTextStorage,
    file: StaticString = #filePath,
    line: UInt = #line
  ) -> NSRange {
    let fullRange = NSRange(location: 0, length: textStorage.length)
    var match: NSRange?

    textStorage.enumerateAttribute(.markdownSectionDivider, in: fullRange, options: []) {
      value,
      range,
      stop in
      guard value as? Bool == true else { return }
      match = range
      stop.pointee = true
    }

    guard let match else {
      XCTFail("Expected a rendered section divider.", file: file, line: line)
      return NSRange(location: 0, length: 0)
    }

    return match
  }

  // Finds the first rendered checkbox glyph so toggle tests hit the right character.
  func firstCheckboxLocation(
    in textStorage: NSTextStorage,
    file: StaticString = #filePath,
    line: UInt = #line
  ) -> Int {
    let fullRange = NSRange(location: 0, length: textStorage.length)
    var location: Int?

    textStorage.enumerateAttribute(.markdownListType, in: fullRange, options: []) {
      value,
      range,
      stop in
      let listType = value as? String
      guard
        listType == MarkdownListType.checkboxUnchecked.rawValue
          || listType == MarkdownListType.checkboxChecked.rawValue
      else { return }

      location = range.location
      stop.pointee = true
    }

    guard let location else {
      XCTFail("Expected a rendered checkbox.", file: file, line: line)
      return 0
    }

    return location
  }
}

@MainActor
final class MarkdownEditorSpellCheckingTests: EditorTestCase {
  // Prevents spell-check wiring from turning on autocorrect or substitutions while enabled.
  func testConfigureTextViewAppliesSpellCheckingWithoutOtherAutomaticFeatures() {
    let textView = MarkdownEditorTextView(usingTextLayoutManager: true)

    MarkdownEditorView.configureTextView(
      textView,
      appearanceSettings: appearance,
      continuousSpellCheckingEnabled: true,
      delegate: nil
    )

    XCTAssertTrue(textView.isContinuousSpellCheckingEnabled)
    XCTAssertFalse(textView.isGrammarCheckingEnabled)
    XCTAssertFalse(textView.isAutomaticSpellingCorrectionEnabled)
    XCTAssertFalse(textView.isAutomaticTextReplacementEnabled)
    XCTAssertFalse(textView.isAutomaticQuoteSubstitutionEnabled)
    XCTAssertFalse(textView.isAutomaticDashSubstitutionEnabled)
  }

  // Prevents markdown-specific spans from receiving red underlines while prose stays eligible.
  func testIgnoredRangesSkipMarkdownSensitiveContentAndKeepProseCheckable() throws {
    let markdown = """
      Normal prose line
      `inline cdoe`
      [lnik label](https://example.com)
      https://example.com/rawword
      ```
      codde block
      ```
      <!-- section -->
      ---
      - [ ] chekcbox label
      # Heding
      """
    let display = MarkdownEditorFormatter.formatForDisplay(markdown, appearance: appearance)
    let textStorage = NSTextStorage(attributedString: display)
    let ignoredRanges = MarkdownEditorSpellChecking.ignoredRanges(in: textStorage)
    let string = textStorage.string as NSString

    XCTAssertTrue(
      overlapsIgnoredRange(string.range(of: "inline cdoe"), ignoredRanges: ignoredRanges)
    )
    XCTAssertTrue(
      overlapsIgnoredRange(string.range(of: "lnik label"), ignoredRanges: ignoredRanges)
    )
    XCTAssertTrue(
      overlapsIgnoredRange(
        string.range(of: "https://example.com/rawword"), ignoredRanges: ignoredRanges)
    )
    XCTAssertTrue(
      overlapsIgnoredRange(string.range(of: "codde block"), ignoredRanges: ignoredRanges)
    )
    XCTAssertTrue(
      overlapsIgnoredRange(
        firstAttributedRange(
          for: .markdownSectionDivider,
          in: textStorage,
          file: #filePath,
          line: #line
        ),
        ignoredRanges: ignoredRanges
      )
    )
    XCTAssertTrue(
      overlapsIgnoredRange(
        firstAttributedRange(
          for: .markdownHorizontalRule,
          in: textStorage,
          file: #filePath,
          line: #line
        ),
        ignoredRanges: ignoredRanges
      )
    )
    XCTAssertFalse(
      overlapsIgnoredRange(string.range(of: "Normal prose line"), ignoredRanges: ignoredRanges)
    )
    XCTAssertFalse(
      overlapsIgnoredRange(string.range(of: "chekcbox label"), ignoredRanges: ignoredRanges)
    )
    XCTAssertFalse(
      overlapsIgnoredRange(string.range(of: "Heding"), ignoredRanges: ignoredRanges)
    )
  }

  // Prevents ignored markdown spans from surviving result filtering when AppKit reports them.
  func testFilterTextCheckingResultsDropsIgnoredMatches() {
    let markdown = """
      prose wurd
      `inline cdoe`
      """
    let display = MarkdownEditorFormatter.formatForDisplay(markdown, appearance: appearance)
    let textStorage = NSTextStorage(attributedString: display)
    let string = textStorage.string as NSString
    let proseRange = string.range(of: "wurd")
    let inlineCodeRange = string.range(of: "cdoe")
    let results = [
      NSTextCheckingResult.spellCheckingResult(range: proseRange),
      NSTextCheckingResult.spellCheckingResult(range: inlineCodeRange),
    ]

    let filteredResults = MarkdownEditorSpellChecking.filterTextCheckingResults(
      results,
      ignoredRanges: MarkdownEditorSpellChecking.ignoredRanges(in: textStorage)
    )

    XCTAssertEqual(filteredResults.map(\.range), [proseRange])
  }

  private func firstAttributedRange(
    for key: NSAttributedString.Key,
    in textStorage: NSTextStorage,
    file: StaticString,
    line: UInt
  ) -> NSRange {
    let fullRange = NSRange(location: 0, length: textStorage.length)
    var match: NSRange?

    textStorage.enumerateAttribute(key, in: fullRange, options: []) { value, range, stop in
      guard value as? Bool == true else { return }
      match = range
      stop.pointee = true
    }

    guard let match else {
      XCTFail("Expected range for \(key.rawValue).", file: file, line: line)
      return NSRange(location: 0, length: 0)
    }

    return match
  }

  private func overlapsIgnoredRange(_ range: NSRange, ignoredRanges: [NSRange]) -> Bool {
    ignoredRanges.contains { NSIntersectionRange($0, range).length > 0 }
  }
}
