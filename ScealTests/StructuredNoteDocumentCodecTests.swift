import Foundation
import XCTest

@testable import Sceal

final class StructuredNoteDocumentCodecTests: XCTestCase {
  // Protects every V2 field through its JSON persistence round trip.
  func testRoundTripPreservesCompleteDocument() throws {
    let document = makeDocument()

    let data = try StructuredNoteDocumentCodec.encode(document)
    let decodedDocument = try StructuredNoteDocumentCodec.decode(data)

    XCTAssertEqual(decodedDocument, document)
  }

  // Keeps the node discriminator readable and independent of Swift's synthesized enum shape.
  func testEncodedJSONUsesExplicitNodeTypes() throws {
    let data = try StructuredNoteDocumentCodec.encode(makeDocument())
    let json = try XCTUnwrap(String(data: data, encoding: .utf8))

    XCTAssertTrue(json.contains(#""type" : "section""#))
    XCTAssertTrue(json.contains(#""type" : "group""#))
    XCTAssertFalse(json.contains(#""_0""#))
  }

  // Rejects future schemas before attempting to interpret their document fields.
  func testDecodeRejectsUnsupportedSchemaVersion() {
    let data = Data(#"{"schemaVersion":99}"#.utf8)

    XCTAssertThrowsError(try StructuredNoteDocumentCodec.decode(data)) { error in
      XCTAssertEqual(
        error as? StructuredNoteDocumentError,
        .unsupportedSchemaVersion(
          found: 99,
          supported: StructuredNoteDocument.currentSchemaVersion
        )
      )
    }
  }

  // Prevents invalid in-memory documents from being persisted.
  func testEncodeRejectsEmptyDocument() {
    let document = StructuredNoteDocument(
      id: "2026-09-01",
      date: makeDate(),
      title: "",
      tags: [],
      nodes: []
    )

    XCTAssertThrowsError(try StructuredNoteDocumentCodec.encode(document)) { error in
      XCTAssertEqual(error as? StructuredNoteDocumentError, .emptyDocument)
    }
  }

  // Verifies atomic file helpers without touching the production library.
  func testAtomicWriteAndReadUseCallerProvidedTemporaryURL() throws {
    let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      "StructuredNoteDocumentCodecTests-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true
    )
    addTeardownBlock {
      try? FileManager.default.removeItem(at: directoryURL)
    }
    let fileURL = directoryURL.appendingPathComponent("2026-09-01.scealnote")
    let document = makeDocument()

    try StructuredNoteDocumentCodec.write(document, to: fileURL)

    XCTAssertEqual(try StructuredNoteDocumentCodec.read(from: fileURL), document)
  }

  // Surfaces malformed JSON instead of constructing success-shaped fallback data.
  func testDecodeRejectsMalformedJSON() {
    XCTAssertThrowsError(
      try StructuredNoteDocumentCodec.decode(Data("not-json".utf8))
    )
  }

  // Builds a fixture containing every persisted style and collapse field.
  private func makeDocument() -> StructuredNoteDocument {
    let rootSection = StructuredNoteSection(
      markdown: "# Root\n\nContent",
      styleOverrides: StructuredSectionStyleOverrides(
        headingColor: .colorName("pink"),
        bulletColor: .themeDefault
      ),
      isCollapsed: true
    )
    let groupedSection = StructuredNoteSection(markdown: "## Child\n\n- Item")
    let group = StructuredSectionGroup(
      title: "Feature",
      style: StructuredSectionStyle(
        backgroundColorName: "grey",
        borderColorName: "blue",
        headingColorName: "blue",
        bulletColorName: "blue"
      ),
      isCollapsed: true,
      sections: [groupedSection]
    )

    return StructuredNoteDocument(
      id: "2026-09-01",
      date: makeDate(),
      title: "Structured",
      tags: ["v2", "codec"],
      nodes: [.section(rootSection), .group(group)]
    )
  }

  // Uses whole seconds so ISO-8601 round trips remain exact.
  private func makeDate() -> Date {
    Date(timeIntervalSince1970: 1_788_220_800)
  }
}
