import XCTest

@testable import Sceal

@MainActor
class MarkdownPreservationTestCase: XCTestCase {
  let appearance = NoteAppearanceSettings.default

  // Runs markdown through display formatting and conversion so preservation tests stay tiny.
  func preservedMarkdown(_ markdown: String) -> String {
    let display = MarkdownEditorFormatter.formatForDisplay(markdown, appearance: appearance)
    return MarkdownEditorFormatter.convertToMarkdown(from: display)
  }
}
