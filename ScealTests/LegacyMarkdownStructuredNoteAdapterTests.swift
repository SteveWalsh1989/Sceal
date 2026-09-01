import Foundation
import XCTest

@testable import Sceal

final class LegacyMarkdownStructuredNoteAdapterTests: XCTestCase {
  // Imports the representative migration fixture without losing metadata or rich body markers.
  func testCompositeFixtureImportsMetadataContentAndSectionColor() throws {
    let sourceURL = try fixtureURL("Notes/2026-05-10-composite.md")
    let document = try LegacyMarkdownStructuredNoteAdapter.importDocument(
      contents: try String(contentsOf: sourceURL, encoding: .utf8),
      sourceURL: sourceURL
    )

    XCTAssertEqual(document.id, "2026-05-10")
    XCTAssertEqual(document.title, #"Daily "Migration": fixture, sample"#)
    XCTAssertEqual(document.tags, ["migration", "round trip", "storage"])
    XCTAssertEqual(document.nodes.count, 2)

    let leadingSection = try rootSection(in: document, at: 0)
    let contentSection = try rootSection(in: document, at: 1)
    XCTAssertEqual(leadingSection.markdown, "")
    XCTAssertEqual(contentSection.styleOverrides.headingColor, .colorName("blue"))
    XCTAssertEqual(contentSection.styleOverrides.bulletColor, .colorName("blue"))
    XCTAssertFalse(contentSection.markdown.contains("<!-- section"))
    XCTAssertTrue(contentSection.markdown.contains("```swift"))
    XCTAssertTrue(contentSection.markdown.contains("<!-- hcolor:turquoise -->"))
    XCTAssertTrue(contentSection.markdown.contains("<!-- prompt -->"))
    XCTAssertTrue(contentSection.markdown.contains("<!-- sceal-table v:1"))
    XCTAssertTrue(contentSection.markdown.contains("<!-- sceal-image-width:520 -->"))
    XCTAssertTrue(contentSection.markdown.contains("\n\nInclude risks and validation."))
  }

  // Treats section-shaped lines inside protected blocks as content and keeps unknown markers.
  func testSectionMarkersInsideProtectedBlocksDoNotSplitContent() throws {
    let protectedCodeMarker = "<!-- section heading:red -->"
    let protectedPromptMarker = "<!-- section heading:pink -->"
    let protectedTableMarker = "<!-- section heading:green -->"
    let unknownMarker = "<!-- section future:preserve -->"
    let body = [
      "# Root",
      "",
      "```text",
      protectedCodeMarker,
      "```",
      "",
      "<!-- prompt -->",
      protectedPromptMarker,
      "<!-- /prompt -->",
      "",
      "<!-- sceal-table v:1 columns:1 header:false fullwidth:false widths:180 -->",
      "<!-- cell r:0 c:0 -->",
      protectedTableMarker,
      "<!-- /cell -->",
      "<!-- /sceal-table -->",
      "",
      "<!-- section heading:blue bullet:turquoise usesectioncolor:false -->",
      "## Second",
      unknownMarker,
    ].joined(separator: "\n")

    let document = try importBody(body)

    XCTAssertEqual(document.nodes.count, 2)
    let firstSection = try rootSection(in: document, at: 0)
    let secondSection = try rootSection(in: document, at: 1)
    XCTAssertTrue(firstSection.markdown.contains(protectedCodeMarker))
    XCTAssertTrue(firstSection.markdown.contains(protectedPromptMarker))
    XCTAssertTrue(firstSection.markdown.contains(protectedTableMarker))
    XCTAssertTrue(secondSection.markdown.contains(unknownMarker))
    XCTAssertEqual(secondSection.styleOverrides.headingColor, .colorName("blue"))
    XCTAssertEqual(secondSection.styleOverrides.bulletColor, .colorName("turquoise"))
  }

  // Prevents an incomplete table marker from swallowing valid section boundaries after it.
  func testMalformedTableDoesNotHideFollowingSection() throws {
    let malformedTableStart =
      "<!-- sceal-table v:1 columns:0 header:false fullwidth:false widths: -->"
    let document = try importBody(
      [
        malformedTableStart,
        "Unclosed table content",
        "<!-- section -->",
        "Following section",
      ].joined(separator: "\n")
    )

    XCTAssertEqual(document.nodes.count, 2)
    XCTAssertTrue(try rootSection(in: document, at: 0).markdown.contains(malformedTableStart))
    XCTAssertEqual(try rootSection(in: document, at: 1).markdown, "Following section")
  }

  // Converts older same-color directives into independent effective style properties.
  func testLegacySameColorDirectiveUsesHeadingColorForBullets() throws {
    let document = try importBody(
      "<!-- section heading:orange -->\n## Heading\n\n- Item"
    )

    let section = try rootSection(in: document, at: 1)
    XCTAssertEqual(section.styleOverrides.headingColor, .colorName("orange"))
    XCTAssertEqual(section.styleOverrides.bulletColor, .colorName("orange"))
  }

  // Keeps plain dividers inheriting future theme or group appearance values.
  func testPlainSectionDirectiveCreatesInheritedSection() throws {
    let document = try importBody("First\n<!-- section -->\nSecond")

    XCTAssertEqual(document.nodes.count, 2)
    XCTAssertEqual(try rootSection(in: document, at: 0).markdown, "First")
    let secondSection = try rootSection(in: document, at: 1)
    XCTAssertEqual(secondSection.markdown, "Second")
    XCTAssertEqual(secondSection.styleOverrides, .inherited)
  }

  // Keeps an empty legacy daily note as one editable structured section.
  func testBlankFixtureImportsAsOneBlankSection() throws {
    let sourceURL = try fixtureURL("Notes/2026-05-11-blank.md")
    let document = try LegacyMarkdownStructuredNoteAdapter.importDocument(
      contents: try String(contentsOf: sourceURL, encoding: .utf8),
      sourceURL: sourceURL
    )

    XCTAssertEqual(document.nodes.count, 1)
    XCTAssertEqual(try rootSection(in: document, at: 0).markdown, "\n")
  }

  // Reports the failing source note while leaving malformed input untouched.
  func testMalformedSourceReportsFilenameWithoutChangingInput() throws {
    let sourceURL = try fixtureURL("Notes/malformed-missing-frontmatter.md")
    let originalContents = try String(contentsOf: sourceURL, encoding: .utf8)

    XCTAssertThrowsError(
      try LegacyMarkdownStructuredNoteAdapter.importDocument(
        contents: originalContents,
        sourceURL: sourceURL
      )
    ) { error in
      guard
        case .invalidSource(let reportedURL, let reason) =
          error as? LegacyMarkdownStructuredNoteAdapterError
      else {
        return XCTFail("Expected a source-specific import error, got \(error).")
      }
      XCTAssertEqual(reportedURL, sourceURL)
      XCTAssertTrue(reason.contains(sourceURL.lastPathComponent))
      XCTAssertTrue(error.localizedDescription.contains(sourceURL.lastPathComponent))
    }

    XCTAssertEqual(try String(contentsOf: sourceURL, encoding: .utf8), originalContents)
  }

  // Encodes a body with the production codec before exercising the pure adapter.
  private func importBody(_ body: String) throws -> StructuredNoteDocument {
    let note = DayNote(
      date: Date(timeIntervalSince1970: 1_788_220_800),
      title: "Adapter",
      tags: ["v2"],
      body: body
    )
    let sourceURL = URL(fileURLWithPath: "/tmp/2026-09-01.md")
    return try LegacyMarkdownStructuredNoteAdapter.importDocument(
      contents: MarkdownNoteCodec.encode(note),
      sourceURL: sourceURL
    )
  }

  // Extracts one root section while failing clearly if a test fixture changes shape.
  private func rootSection(
    in document: StructuredNoteDocument,
    at index: Int
  ) throws -> StructuredNoteSection {
    guard document.nodes.indices.contains(index),
      case .section(let section) = document.nodes[index]
    else {
      throw LegacyMarkdownStructuredNoteAdapterTestError.missingRootSection(index)
    }
    return section
  }

  // Locates a bundled migration fixture by its relative documentation path.
  private func fixtureURL(_ relativePath: String) throws -> URL {
    let fileURL = URL(fileURLWithPath: relativePath)
    guard
      let resourceURL = Bundle(for: Self.self).url(
        forResource: fileURL.deletingPathExtension().lastPathComponent,
        withExtension: fileURL.pathExtension
      )
    else {
      throw LegacyMarkdownStructuredNoteAdapterTestError.missingFixture(relativePath)
    }
    return resourceURL
  }
}

private enum LegacyMarkdownStructuredNoteAdapterTestError: Error {
  case missingFixture(String)
  case missingRootSection(Int)
}
