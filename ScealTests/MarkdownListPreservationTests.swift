import XCTest

@testable import Sceal

@MainActor
final class MarkdownListPreservationTests: MarkdownPreservationTestCase {
  // Prevents plain bullet items from changing marker style on save.
  func testBulletItem() {
    XCTAssertEqual(preservedMarkdown("- item"), "- item")
  }

  // Prevents numbered items from losing their ordered list marker.
  func testNumberedItem() {
    XCTAssertEqual(preservedMarkdown("1. item"), "1. item")
  }

  // Prevents unchecked checkbox items from becoming regular bullets.
  func testUncheckedCheckbox() {
    XCTAssertEqual(preservedMarkdown("- [ ] task"), "- [ ] task")
  }

  // Prevents checked checkbox items from losing their checked state.
  func testCheckedCheckbox() {
    XCTAssertEqual(preservedMarkdown("- [x] task"), "- [x] task")
  }

  // Prevents nested bullets inside a section directive from losing indentation.
  func testIndentedBulletInsideSectionDirective() {
    XCTAssertEqual(
      preservedMarkdown("<!-- section bullet:blue usesectioncolor:true -->\n  - nested"),
      "<!-- section bullet:blue usesectioncolor:true -->\n  - nested"
    )
  }

  // Prevents nested checkboxes inside a section directive from losing indentation or state.
  func testIndentedCheckboxInsideSectionDirective() {
    XCTAssertEqual(
      preservedMarkdown("<!-- section bullet:blue usesectioncolor:true -->\n  - [ ] nested task"),
      "<!-- section bullet:blue usesectioncolor:true -->\n  - [ ] nested task"
    )
  }
}
