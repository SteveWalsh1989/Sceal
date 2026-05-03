import Foundation
import XCTest

@testable import Sceal

@MainActor
final class GenericMarkdownImporterTests: NotesStoreTestCase {
  func testImportsJoplinFrontMatterDateTitleAndTags() throws {
    let directoryURL = try makeTemporaryDirectory()
    try write(
      """
      ---
      title: Joplin Interop
      created: 2021-05-01 16:40:00Z
      tags:
        - export
        - import
      ---

      Body from Joplin.
      """,
      to: "joplin-note.md",
      in: directoryURL
    )

    let result = try GenericMarkdownImporter.importNotes(
      from: directoryURL,
      existingNoteIDs: [],
      calendar: Calendar(identifier: .gregorian)
    )

    XCTAssertEqual(result.imported.count, 1)
    XCTAssertEqual(result.imported.first?.id, "2021-05-01")
    XCTAssertEqual(result.imported.first?.title, "Joplin Interop")
    XCTAssertEqual(result.imported.first?.tags, ["export", "import"])
    XCTAssertEqual(result.imported.first?.body, "Body from Joplin.")
  }

  func testImportsFilenameDatesForObsidianAndLogseqStyleMarkdown() throws {
    let directoryURL = try makeTemporaryDirectory()
    try write(
      """
      # Obsidian Daily

      Daily body.
      """,
      to: "Obsidian/Daily/2026-05-03.md",
      in: directoryURL
    )
    try write(
      "Logseq body.",
      to: "Logseq/journals/2026_05_04.md",
      in: directoryURL
    )

    let result = try GenericMarkdownImporter.importNotes(
      from: directoryURL,
      existingNoteIDs: [],
      calendar: Calendar(identifier: .gregorian)
    )

    XCTAssertEqual(result.imported.map(\.id), ["2026-05-04", "2026-05-03"])
    XCTAssertEqual(result.imported.first(where: { $0.id == "2026-05-03" })?.title, "Obsidian Daily")
    XCTAssertEqual(result.imported.first(where: { $0.id == "2026-05-03" })?.body, "Daily body.")
    XCTAssertEqual(result.imported.first(where: { $0.id == "2026-05-04" })?.title, "")
  }

  func testMergesMarkdownFilesThatShareADate() throws {
    let directoryURL = try makeTemporaryDirectory()
    try write(
      """
      # Morning

      First entry.
      """,
      to: "2026-05-03 Morning.md",
      in: directoryURL
    )
    try write(
      """
      # Evening

      Second entry.
      """,
      to: "2026-05-03 Evening.md",
      in: directoryURL
    )

    let result = try GenericMarkdownImporter.importNotes(
      from: directoryURL,
      existingNoteIDs: [],
      calendar: Calendar(identifier: .gregorian)
    )

    XCTAssertEqual(result.imported.count, 1)
    XCTAssertEqual(result.merged, 1)
    XCTAssertEqual(result.imported.first?.id, "2026-05-03")
    XCTAssertEqual(
      result.imported.first?.body,
      "## Evening\n\nSecond entry.\n\n---\n\n## Morning\n\nFirst entry.")
  }

  func testSkipsExistingDatesAndFilesWithoutDates() throws {
    let directoryURL = try makeTemporaryDirectory()
    try write("Existing body.", to: "2026-05-03.md", in: directoryURL)
    try write("Undated body.", to: "Undated.md", in: directoryURL)

    let result = try GenericMarkdownImporter.importNotes(
      from: directoryURL,
      existingNoteIDs: ["2026-05-03"],
      calendar: Calendar(identifier: .gregorian)
    )

    XCTAssertTrue(result.imported.isEmpty)
    XCTAssertEqual(result.skipped, 1)
    XCTAssertEqual(result.missingDate, 1)
  }

  private func makeTemporaryDirectory() throws -> URL {
    let directoryURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    addTeardownBlock {
      try? FileManager.default.removeItem(at: directoryURL)
    }

    return directoryURL
  }

  private func write(_ contents: String, to path: String, in directoryURL: URL) throws {
    let fileURL = directoryURL.appendingPathComponent(path)
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try contents.write(to: fileURL, atomically: true, encoding: .utf8)
  }
}
