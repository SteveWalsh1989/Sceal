import Foundation
import XCTest

@testable import Sceal

@MainActor
final class MigrationStorageFixtureTests: MarkdownPreservationTestCase {
  // Protects the current daily-note front matter and body marker contract.
  func testCompositeDailyNoteFixtureDecodesFrontMatterAndPreservesBody() throws {
    let fixture = try loadFixtureText("Notes/2026-05-10-composite.md")
    let note = try MarkdownNoteCodec.decode(
      contents: fixture,
      sourceURL: try fixtureURL("Notes/2026-05-10-composite.md")
    )

    XCTAssertEqual(note.id, "2026-05-10")
    XCTAssertEqual(note.title, #"Daily "Migration": fixture, sample"#)
    XCTAssertEqual(note.tags, ["migration", "round trip", "storage"])
    XCTAssertTrue(
      note.body.contains("<!-- section heading:blue bullet:blue usesectioncolor:true -->"))
    XCTAssertTrue(note.body.contains("<!-- hcolor:turquoise -->"))
    XCTAssertTrue(note.body.contains("<!-- prompt -->"))
    XCTAssertTrue(note.body.contains("<!-- sceal-table v:1 columns:2 header:true"))
    XCTAssertTrue(note.body.contains("<!-- sceal-image-width:520 -->"))
  }

  // Prevents formatter refactors from changing the supported composite body format.
  func testCompositeDailyNoteBodyRoundTripsThroughEditorFormatter() throws {
    let note = try decodeFixtureNote("Notes/2026-05-10-composite.md")
    let expected = note.body
      .replacingOccurrences(
        of: "```\n\n<!-- hcolor:turquoise -->",
        with: "```\n\n\n<!-- hcolor:turquoise -->"
      )
      .trimmingSingleTrailingNewline()

    XCTAssertEqual(preservedMarkdown(note.body), expected)
  }

  // Keeps blank notes valid so empty daily files remain safe during repository extraction.
  func testBlankDailyNoteFixtureDecodes() throws {
    let note = try decodeFixtureNote("Notes/2026-05-11-blank.md")

    XCTAssertEqual(note.id, "2026-05-11")
    XCTAssertEqual(note.title, "")
    XCTAssertEqual(note.tags, [])
    XCTAssertEqual(note.body, "\n")
  }

  // Protects list notes that use custom IDs while sharing the daily-note codec.
  func testListNoteFixtureDecodesWithCustomIDOverride() throws {
    let fixturePath = "ListNotes/project-alpha.md"
    let note = try MarkdownNoteCodec.decode(
      contents: try loadFixtureText(fixturePath),
      sourceURL: try fixtureURL(fixturePath),
      idOverride: "project-alpha"
    )

    XCTAssertEqual(note.id, "project-alpha")
    XCTAssertEqual(note.fileName, "project-alpha.md")
    XCTAssertEqual(note.title, "Project Alpha")
    XCTAssertEqual(note.tags, ["project", "list"])
    XCTAssertTrue(note.body.contains("<!-- section -->"))
  }

  // Keeps list-note group metadata compatible with the current manifest decoder.
  func testListNotesManifestFixtureDecodes() throws {
    let data = try Data(contentsOf: try fixtureURL("ListNotes/groups.json"))
    let manifest = try JSONDecoder().decode(ListNotesManifest.self, from: data)

    XCTAssertEqual(manifest.ungroupedNoteIDs, [])
    XCTAssertEqual(manifest.groups.count, 1)
    XCTAssertEqual(manifest.groups.first?.id, "group-active")
    XCTAssertEqual(manifest.groups.first?.noteIDs, ["project-alpha"])
    XCTAssertEqual(manifest.allNoteIDs, ["project-alpha"])
  }

  // Invalid files must fail decode instead of being silently repaired in place.
  func testMalformedNoteFixtureFailsWithoutFrontMatter() throws {
    let fixturePath = "Notes/malformed-missing-frontmatter.md"

    XCTAssertThrowsError(
      try MarkdownNoteCodec.decode(
        contents: try loadFixtureText(fixturePath),
        sourceURL: try fixtureURL(fixturePath)
      )
    ) { error in
      guard case MarkdownNoteCodecError.missingFrontMatter = error else {
        return XCTFail("Expected missing front matter, got \(error).")
      }
    }
  }

  private func decodeFixtureNote(_ relativePath: String) throws -> DayNote {
    try MarkdownNoteCodec.decode(
      contents: try loadFixtureText(relativePath),
      sourceURL: try fixtureURL(relativePath)
    )
  }

  private func loadFixtureText(_ relativePath: String) throws -> String {
    try String(contentsOf: try fixtureURL(relativePath), encoding: .utf8)
  }

  private func fixtureURL(_ relativePath: String) throws -> URL {
    let fileURL = URL(fileURLWithPath: relativePath)
    let fileName = fileURL.deletingPathExtension().lastPathComponent
    let fileExtension = fileURL.pathExtension

    guard
      let resourceURL = Bundle(for: Self.self).url(
        forResource: fileName,
        withExtension: fileExtension.isEmpty ? nil : fileExtension
      )
    else {
      throw MigrationStorageFixtureError.missingResource(relativePath)
    }

    return resourceURL
  }
}

extension String {
  fileprivate func trimmingSingleTrailingNewline() -> String {
    hasSuffix("\n") ? String(dropLast()) : self
  }
}

enum MigrationStorageFixtureError: LocalizedError {
  case missingResource(String)

  var errorDescription: String? {
    switch self {
    case .missingResource(let relativePath):
      return "Missing migration fixture resource: \(relativePath)"
    }
  }
}
