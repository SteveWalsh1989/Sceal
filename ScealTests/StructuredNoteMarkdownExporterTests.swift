import Foundation
import XCTest

@testable import Sceal

final class StructuredNoteMarkdownExporterTests: XCTestCase {
  // Flattens root sections and grouped children in visible order with a semantic group heading.
  func testBodyExportsRootAndGroupedContentInOrder() throws {
    let first = StructuredNoteSection(markdown: "Root first")
    let groupedFirst = StructuredNoteSection(markdown: "Grouped first")
    let groupedSecond = StructuredNoteSection(markdown: "Grouped second")
    let group = StructuredSectionGroup(
      title: "Feature Group",
      sections: [groupedFirst, groupedSecond]
    )
    let last = StructuredNoteSection(markdown: "Root last")
    let document = makeDocument(nodes: [.section(first), .group(group), .section(last)])

    XCTAssertEqual(
      try StructuredNoteMarkdownExporter.body(for: document),
      "Root first\n\n## Feature Group\n\nGrouped first\n\nGrouped second\n\nRoot last"
    )
  }

  // Preserves complete note metadata through the existing readable Markdown front matter.
  func testCompleteExportPreservesMetadata() throws {
    let document = makeDocument(
      title: #"Portable "Note""#,
      tags: ["portable", "v2"],
      nodes: [.section(StructuredNoteSection(markdown: "Body"))]
    )

    let exported = try StructuredNoteMarkdownExporter.export(document)
    let decodedNote = try MarkdownNoteCodec.decode(
      contents: exported,
      sourceURL: URL(fileURLWithPath: "/tmp/2026-09-01.md")
    )

    XCTAssertEqual(decodedNote.id, document.id)
    XCTAssertEqual(
      NoteDateFormatters.storageDate.string(from: decodedNote.date),
      NoteDateFormatters.storageDate.string(from: document.date)
    )
    XCTAssertEqual(decodedNote.title, document.title)
    XCTAssertEqual(decodedNote.tags, document.tags)
    XCTAssertEqual(decodedNote.body, "Body")
  }

  // Leaves section-owned Markdown markers intact while dropping structured appearance metadata.
  func testBodyPreservesContentMarkersButOmitsStructuredState() throws {
    let markdown = [
      "<!-- hcolor:turquoise -->",
      "## Heading",
      "",
      "<!-- prompt -->",
      "Write a prompt.",
      "<!-- /prompt -->",
      "",
      "```swift",
      "let value = 1",
      "```",
      "",
      "<!-- sceal-image-width:520 -->",
      "![Desk](../Attachments/desk.png)",
      "",
      "<!-- future-marker keep:true -->",
    ].joined(separator: "\n")
    let section = StructuredNoteSection(
      markdown: markdown,
      styleOverrides: StructuredSectionStyleOverrides(
        headingColor: .colorName("pink")
      ),
      isCollapsed: true
    )
    let document = makeDocument(nodes: [.section(section)])

    let exportedBody = try StructuredNoteMarkdownExporter.body(for: document)

    XCTAssertEqual(exportedBody, markdown)
    XCTAssertFalse(exportedBody.contains("<!-- section"))
    XCTAssertFalse(exportedBody.contains("pink"))
  }

  // Proves fixture import and portable export retain normalized textual content and order.
  func testCompositeFixtureImportExportPreservesNormalizedContentOrder() throws {
    let sourceURL = try fixtureURL("Notes/2026-05-10-composite.md")
    let sourceContents = try String(contentsOf: sourceURL, encoding: .utf8)
    let sourceNote = try MarkdownNoteCodec.decode(contents: sourceContents, sourceURL: sourceURL)
    let document = try LegacyMarkdownStructuredNoteAdapter.importDocument(
      contents: sourceContents,
      sourceURL: sourceURL
    )

    let exportedContents = try StructuredNoteMarkdownExporter.export(document)
    let exportedNote = try MarkdownNoteCodec.decode(
      contents: exportedContents,
      sourceURL: URL(fileURLWithPath: "/tmp/exported-2026-05-10.md")
    )

    XCTAssertEqual(exportedNote.title, sourceNote.title)
    XCTAssertEqual(exportedNote.tags, sourceNote.tags)
    XCTAssertEqual(
      normalizedContent(exportedNote.body),
      normalizedContent(removingActiveSectionDirectives(from: sourceNote.body))
    )
  }

  // Keeps existing boundary whitespace and adds only the spacing missing between sections.
  func testBodyPreservesExistingSectionBoundaryWhitespace() throws {
    let document = makeDocument(
      nodes: [
        .section(StructuredNoteSection(markdown: "First\n\n\n")),
        .section(StructuredNoteSection(markdown: "\nSecond")),
      ]
    )

    XCTAssertEqual(
      try StructuredNoteMarkdownExporter.body(for: document),
      "First\n\n\n\nSecond"
    )
  }

  // Rejects invalid documents instead of producing partial portable output.
  func testExportRejectsInvalidDocument() {
    let document = makeDocument(nodes: [])

    XCTAssertThrowsError(try StructuredNoteMarkdownExporter.export(document)) { error in
      XCTAssertEqual(error as? StructuredNoteDocumentError, .emptyDocument)
    }
  }

  // Creates a structured daily-note fixture with stable metadata.
  private func makeDocument(
    title: String = "Structured",
    tags: [String] = ["v2"],
    nodes: [StructuredNoteNode]
  ) -> StructuredNoteDocument {
    StructuredNoteDocument(
      id: "2026-09-01",
      date: Date(timeIntervalSince1970: 1_788_220_800),
      title: title,
      tags: tags,
      nodes: nodes
    )
  }

  // Removes active legacy dividers for normalized content comparison.
  private func removingActiveSectionDirectives(from markdown: String) -> String {
    markdown
      .components(separatedBy: "\n")
      .filter { MarkdownEditorSectionDirectiveMarkdown.parse($0) == nil }
      .joined(separator: "\n")
  }

  // Ignores structural whitespace while preserving every ordered content token.
  private func normalizedContent(_ markdown: String) -> String {
    markdown
      .split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
  }

  // Locates the representative bundled migration fixture.
  private func fixtureURL(_ relativePath: String) throws -> URL {
    let fileURL = URL(fileURLWithPath: relativePath)
    guard
      let resourceURL = Bundle(for: Self.self).url(
        forResource: fileURL.deletingPathExtension().lastPathComponent,
        withExtension: fileURL.pathExtension
      )
    else {
      throw StructuredNoteMarkdownExporterTestError.missingFixture(relativePath)
    }
    return resourceURL
  }
}

private enum StructuredNoteMarkdownExporterTestError: Error {
  case missingFixture(String)
}
