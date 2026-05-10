import XCTest

@testable import Sceal

final class MarkdownEditorImageMarkdownTests: XCTestCase {
  // Keeps resized image width markers clamped to the editor-supported range.
  func testParseWidthMarkerClampsSupportedRange() {
    XCTAssertEqual(
      MarkdownEditorImageMarkdown.parseWidthMarker("<!-- sceal-image-width:520 -->"),
      520
    )
    XCTAssertEqual(
      MarkdownEditorImageMarkdown.parseWidthMarker("<!-- sceal-image-width:20 -->"),
      MarkdownEditorImageMarkdown.minimumWidth
    )
    XCTAssertEqual(
      MarkdownEditorImageMarkdown.parseWidthMarker("<!-- sceal-image-width:900 -->"),
      MarkdownEditorImageMarkdown.maximumWidth
    )
  }

  // Keeps image markdown serialization using the canonical persisted line format.
  func testImageLineAndParseImageRoundTrip() {
    let title = #"Desk \ photo"#
    let path = "../Attachments/2026-05-10/desk.png"
    let line = MarkdownEditorImageMarkdown.imageLine(title: title, path: path)

    XCTAssertEqual(line, #"![Desk \\ photo](../Attachments/2026-05-10/desk.png)"#)
    XCTAssertEqual(MarkdownEditorImageMarkdown.parseImage(line)?.title, title)
    XCTAssertEqual(MarkdownEditorImageMarkdown.parseImage(line)?.path, path)
  }

  // Keeps AppKit and Swift numeric width attributes convertible during markdown reconstruction.
  func testWidthValueAcceptsCGFloatAndNSNumber() {
    XCTAssertEqual(MarkdownEditorImageMarkdown.widthValue(from: CGFloat(440)), 440)
    XCTAssertEqual(MarkdownEditorImageMarkdown.widthValue(from: NSNumber(value: 520)), 520)
    XCTAssertNil(MarkdownEditorImageMarkdown.widthValue(from: "520"))
  }
}
