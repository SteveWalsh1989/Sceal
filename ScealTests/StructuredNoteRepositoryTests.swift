import Foundation
import XCTest

@testable import Sceal

final class StructuredNoteRepositoryTests: XCTestCase {
  // Persists date-named structured files and reloads them in newest-first order.
  func testSavesAndReloadsStructuredDailyNotesInsideIsolatedDirectory() throws {
    let fixture = makeRepository()
    let olderDocument = makeDocument(year: 2026, month: 5, day: 10, title: "Older")
    let newerDocument = makeDocument(year: 2026, month: 5, day: 12, title: "Newer")

    try fixture.repository.save(olderDocument)
    try fixture.repository.save(newerDocument)

    XCTAssertEqual(
      try fixture.repository.loadDocuments().map(\.id),
      [newerDocument.id, olderDocument.id]
    )
    XCTAssertTrue(
      fixture.fileManager.fileExists(
        atPath: fixture.repository.fileURL(for: olderDocument.id).path
      )
    )
    XCTAssertFalse(
      fixture.fileManager.fileExists(
        atPath: fixture.repository.legacyNotesDirectoryURL
          .appendingPathComponent("\(olderDocument.id).md").path
      )
    )
  }

  // Copies representative legacy notes without rewriting sources or replacing stable imports.
  func testCopiesLegacyNotesAndSkipsExistingStructuredDocuments() throws {
    let fixture = makeRepository()
    try fixture.fileManager.createDirectory(
      at: fixture.repository.legacyNotesDirectoryURL,
      withIntermediateDirectories: true
    )
    let sourceURLs = try ["2026-05-10-composite.md", "2026-05-11-blank.md"].map {
      try copyFixture($0, to: fixture.repository.legacyNotesDirectoryURL)
    }
    let sourceData = try sourceURLs.map { try Data(contentsOf: $0) }

    let firstResult = try fixture.repository.copyLegacyDailyNotes()
    let firstDocuments = try fixture.repository.loadDocuments()
    let firstSectionIDs = firstDocuments.flatMap(sectionIDs(in:))
    let secondResult = try fixture.repository.copyLegacyDailyNotes()
    let secondDocuments = try fixture.repository.loadDocuments()

    XCTAssertEqual(firstResult, StructuredNoteImportResult(imported: 2, skipped: 0))
    XCTAssertEqual(secondResult, StructuredNoteImportResult(imported: 0, skipped: 2))
    XCTAssertEqual(secondDocuments.map(\.id), firstDocuments.map(\.id))
    XCTAssertEqual(secondDocuments.flatMap(sectionIDs(in:)), firstSectionIDs)
    XCTAssertEqual(try sourceURLs.map { try Data(contentsOf: $0) }, sourceData)
  }

  // Validates every legacy source before writing any structured copy.
  func testMalformedLegacySourcePreventsPartialCopy() throws {
    let fixture = makeRepository()
    try fixture.fileManager.createDirectory(
      at: fixture.repository.legacyNotesDirectoryURL,
      withIntermediateDirectories: true
    )
    try copyFixture("2026-05-10-composite.md", to: fixture.repository.legacyNotesDirectoryURL)
    try copyFixture(
      "malformed-missing-frontmatter.md", to: fixture.repository.legacyNotesDirectoryURL)

    XCTAssertThrowsError(try fixture.repository.copyLegacyDailyNotes()) { error in
      XCTAssertTrue(error.localizedDescription.contains("malformed-missing-frontmatter.md"))
    }
    XCTAssertFalse(
      fixture.fileManager.fileExists(atPath: fixture.repository.storageDirectoryURL.path)
    )
  }

  // Refuses a configured target that collides with the legacy Markdown directory.
  func testRefusesLegacyNotesDirectoryAsStructuredStorage() throws {
    let rootURL = makeTemporaryRoot()
    let legacyURL = rootURL.appendingPathComponent("Notes", isDirectory: true)
    let repository = StructuredNoteRepository(
      storageDirectoryURL: legacyURL,
      legacyNotesDirectoryURL: legacyURL
    )
    let document = makeDocument(year: 2026, month: 5, day: 13)

    XCTAssertThrowsError(try repository.save(document)) { error in
      XCTAssertEqual(
        error as? StructuredNoteRepositoryError,
        .refusingLegacyNotesDirectory(legacyURL)
      )
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
  }

  // Rejects a valid payload stored under a filename that disagrees with its document ID.
  func testLoadReportsMismatchedStructuredFilename() throws {
    let fixture = makeRepository()
    let document = makeDocument(year: 2026, month: 5, day: 14)
    try fixture.fileManager.createDirectory(
      at: fixture.repository.storageDirectoryURL,
      withIntermediateDirectories: true
    )
    let mismatchedURL = fixture.repository.storageDirectoryURL
      .appendingPathComponent("2026-05-15")
      .appendingPathExtension(StructuredNoteRepository.fileExtension)
    try StructuredNoteDocumentCodec.write(document, to: mismatchedURL)

    XCTAssertThrowsError(try fixture.repository.loadDocuments()) { error in
      XCTAssertEqual(
        error as? StructuredNoteRepositoryError,
        .fileNameDoesNotMatchDocumentID(mismatchedURL, documentID: document.id)
      )
    }
  }

  // Rejects non-date IDs before constructing unsafe or misleading filenames.
  func testSaveRejectsNonDateDailyDocumentID() {
    let fixture = makeRepository()
    let date = makeDate(year: 2026, month: 5, day: 16)
    let document = StructuredNoteDocument.empty(id: "../escape", date: date)

    XCTAssertThrowsError(try fixture.repository.save(document)) { error in
      XCTAssertEqual(
        error as? StructuredNoteRepositoryError,
        .invalidDailyDocumentID("../escape", expected: "2026-05-16")
      )
    }
    XCTAssertFalse(
      fixture.fileManager.fileExists(atPath: fixture.repository.storageDirectoryURL.path)
    )
  }

  // Creates an isolated repository fixture and removes it after each test.
  private func makeRepository() -> StructuredNoteRepositoryFixture {
    let rootURL = makeTemporaryRoot()
    let fileManager = FileManager.default
    return StructuredNoteRepositoryFixture(
      repository: StructuredNoteRepository(
        libraryLocation: .test(rootURL: rootURL),
        fileManager: fileManager
      ),
      fileManager: fileManager
    )
  }

  // Creates one valid structured daily document with a predictable storage ID.
  private func makeDocument(
    year: Int,
    month: Int,
    day: Int,
    title: String = "Structured"
  ) -> StructuredNoteDocument {
    let date = makeDate(year: year, month: month, day: day)
    return StructuredNoteDocument(
      id: NoteDateFormatters.storageDate.string(from: date),
      date: date,
      title: title,
      tags: ["v2"],
      nodes: [.section(StructuredNoteSection(markdown: "# \(title)"))]
    )
  }

  // Collects every stable section ID regardless of root or grouped placement.
  private func sectionIDs(in document: StructuredNoteDocument) -> [UUID] {
    document.nodes.flatMap { node in
      switch node {
      case .section(let section):
        return [section.id]
      case .group(let group):
        return group.sections.map(\.id)
      }
    }
  }

  // Copies one bundled migration fixture into the injected legacy directory.
  @discardableResult
  private func copyFixture(_ fileName: String, to directoryURL: URL) throws -> URL {
    let sourceURL = try fixtureURL(fileName)
    let destinationURL = directoryURL.appendingPathComponent(fileName)
    try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    return destinationURL
  }

  // Locates a bundled migration fixture by filename.
  private func fixtureURL(_ fileName: String) throws -> URL {
    let fileURL = URL(fileURLWithPath: fileName)
    guard
      let resourceURL = Bundle(for: Self.self).url(
        forResource: fileURL.deletingPathExtension().lastPathComponent,
        withExtension: fileURL.pathExtension
      )
    else {
      throw StructuredNoteRepositoryTestError.missingFixture(fileName)
    }
    return resourceURL
  }

  // Creates a disposable filesystem root for one test.
  private func makeTemporaryRoot() -> URL {
    let rootURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("StructuredNoteRepositoryTests-\(UUID().uuidString)")
    addTeardownBlock {
      try? FileManager.default.removeItem(at: rootURL)
    }
    return rootURL
  }

  // Creates a stable UTC date for date-based filename assertions.
  private func makeDate(year: Int, month: Int, day: Int) -> Date {
    var components = DateComponents()
    components.calendar = Calendar(identifier: .gregorian)
    components.timeZone = TimeZone(secondsFromGMT: 0)
    components.year = year
    components.month = month
    components.day = day
    components.hour = 12
    return components.date!
  }
}

private struct StructuredNoteRepositoryFixture {
  let repository: StructuredNoteRepository
  let fileManager: FileManager
}

private enum StructuredNoteRepositoryTestError: Error {
  case missingFixture(String)
}
