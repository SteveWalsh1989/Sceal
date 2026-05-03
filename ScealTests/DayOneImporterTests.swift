import Foundation
import XCTest

@testable import Sceal

@MainActor
final class DayOneImporterTests: NotesStoreTestCase {
  func testImportsDayOneZipWithJournalJSON() throws {
    let zipURL = try makeDayOneZip(
      entries: [
        dayOneEntry(
          creationDate: "2026-05-03T10:30:00Z",
          timeZone: "Europe/Dublin",
          text: "# Day One Title\\.\n\nImported body\\.",
          tags: ["journal"]
        )
      ]
    )

    let result = try DayOneImporter.importNotes(
      from: zipURL,
      existingNoteIDs: [],
      calendar: makeImportCalendar()
    )

    XCTAssertEqual(result.imported.count, 1)
    XCTAssertEqual(result.imported.first?.id, "2026-05-03")
    XCTAssertEqual(result.imported.first?.title, "Day One Title.")
    XCTAssertEqual(result.imported.first?.body, "Imported body.")
    XCTAssertEqual(result.imported.first?.tags, ["journal"])
  }

  func testImportsRawJSONFile() throws {
    let jsonURL = try makeDayOneJSONFile(
      entries: [
        dayOneEntry(
          creationDate: "2026-05-04T09:00:00Z",
          timeZone: "Europe/Dublin",
          text: "Plain body."
        )
      ]
    )

    let result = try DayOneImporter.importNotes(
      from: jsonURL,
      existingNoteIDs: [],
      calendar: makeImportCalendar()
    )

    XCTAssertEqual(result.imported.count, 1)
    XCTAssertEqual(result.imported.first?.id, "2026-05-04")
    XCTAssertEqual(result.imported.first?.title, "")
    XCTAssertEqual(result.imported.first?.body, "Plain body.")
  }

  func testUsesEntryTimeZoneForJournalDate() throws {
    let jsonURL = try makeDayOneJSONFile(
      entries: [
        dayOneEntry(
          creationDate: "2026-05-04T00:30:00Z",
          timeZone: "America/Los_Angeles",
          text: "Late evening in the original journal timezone."
        )
      ]
    )

    let result = try DayOneImporter.importNotes(
      from: jsonURL,
      existingNoteIDs: [],
      calendar: makeImportCalendar()
    )

    XCTAssertEqual(result.imported.first?.id, "2026-05-03")
  }

  func testMergesSameDayEntries() throws {
    let jsonURL = try makeDayOneJSONFile(
      entries: [
        dayOneEntry(
          uuid: "morning",
          creationDate: "2026-05-03T08:00:00Z",
          timeZone: "Europe/Dublin",
          text: "# Morning\n\nFirst entry."
        ),
        dayOneEntry(
          uuid: "evening",
          creationDate: "2026-05-03T20:00:00Z",
          timeZone: "Europe/Dublin",
          text: "# Evening\n\nSecond entry."
        ),
      ]
    )

    let result = try DayOneImporter.importNotes(
      from: jsonURL,
      existingNoteIDs: [],
      calendar: makeImportCalendar()
    )

    XCTAssertEqual(result.imported.count, 1)
    XCTAssertEqual(result.merged, 1)
    XCTAssertEqual(result.imported.first?.title, "Morning")
    XCTAssertEqual(
      result.imported.first?.body,
      "## Morning\n\nFirst entry.\n\n---\n\n## Evening\n\nSecond entry."
    )
  }

  func testSkipsExistingDates() throws {
    let jsonURL = try makeDayOneJSONFile(
      entries: [
        dayOneEntry(
          creationDate: "2026-05-03T08:00:00Z",
          timeZone: "Europe/Dublin",
          text: "Already imported."
        )
      ]
    )

    let result = try DayOneImporter.importNotes(
      from: jsonURL,
      existingNoteIDs: ["2026-05-03"],
      calendar: makeImportCalendar()
    )

    XCTAssertTrue(result.imported.isEmpty)
    XCTAssertEqual(result.skipped, 1)
  }

  func testDeduplicatesTagsRemovesMediaMarkersAndReportsOmittedMedia() throws {
    let jsonURL = try makeDayOneJSONFile(
      entries: [
        dayOneEntry(
          creationDate: "2026-05-03T08:00:00Z",
          timeZone: "Europe/Dublin",
          text: "# Media Day\n\n![](dayone-moment://PHOTO1)\n\nBody after media\\-marker\\.",
          tags: ["travel", "travel", "photos"],
          photos: [["identifier": "PHOTO1"], ["identifier": "PHOTO2"]],
          videos: [["identifier": "VIDEO1"]],
          audios: [["identifier": "AUDIO1"]],
          pdfs: [["identifier": "PDF1"]]
        )
      ]
    )

    let result = try DayOneImporter.importNotes(
      from: jsonURL,
      existingNoteIDs: [],
      calendar: makeImportCalendar()
    )

    XCTAssertEqual(result.imported.first?.tags, ["travel", "photos"])
    XCTAssertEqual(result.imported.first?.body, "Body after media-marker.")
    XCTAssertEqual(result.omittedPhotos, 2)
    XCTAssertEqual(result.omittedVideos, 1)
    XCTAssertEqual(result.omittedAudios, 1)
    XCTAssertEqual(result.omittedPDFs, 1)
    XCTAssertEqual(result.omittedMediaTotal, 5)
  }

  func testInvalidEntriesAreCountedWithoutAbortingImport() throws {
    let jsonURL = try makeDayOneJSONFile(
      entries: [
        dayOneEntry(
          creationDate: "2026-05-03T08:00:00Z",
          timeZone: nil,
          text: "Valid entry without a timezone."
        ),
        ["uuid": "missing-date", "text": "This entry cannot be dated."],
      ]
    )

    let result = try DayOneImporter.importNotes(
      from: jsonURL,
      existingNoteIDs: [],
      calendar: makeImportCalendar()
    )

    XCTAssertEqual(result.imported.count, 1)
    XCTAssertEqual(result.failed, 1)
    XCTAssertEqual(result.missingTimeZone, 1)
    XCTAssertEqual(result.imported.first?.id, "2026-05-03")
  }

  private func makeImportCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }

  private func makeDayOneZip(entries: [[String: Any]]) throws -> URL {
    let directoryURL = try makeTemporaryDirectory()
    try writeDayOneJSON(entries: entries, to: directoryURL.appendingPathComponent("Journal.json"))

    let zipURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("\(UUID().uuidString).zip")
    try ZipArchiveWriter.createZip(from: directoryURL, to: zipURL)
    addTeardownBlock {
      try? FileManager.default.removeItem(at: zipURL)
    }

    return zipURL
  }

  private func makeDayOneJSONFile(entries: [[String: Any]]) throws -> URL {
    let directoryURL = try makeTemporaryDirectory()
    let fileURL = directoryURL.appendingPathComponent("Journal.json")
    try writeDayOneJSON(entries: entries, to: fileURL)
    return fileURL
  }

  private func writeDayOneJSON(entries: [[String: Any]], to fileURL: URL) throws {
    let archive: [String: Any] = [
      "metadata": ["version": "1.0"],
      "entries": entries,
    ]
    let data = try JSONSerialization.data(withJSONObject: archive, options: [.prettyPrinted])
    try data.write(to: fileURL)
  }

  private func dayOneEntry(
    uuid: String = UUID().uuidString,
    creationDate: String,
    timeZone: String? = "Europe/Dublin",
    text: String,
    tags: [String] = [],
    photos: [[String: Any]] = [],
    videos: [[String: Any]] = [],
    audios: [[String: Any]] = [],
    pdfs: [[String: Any]] = []
  ) -> [String: Any] {
    var entry: [String: Any] = [
      "uuid": uuid,
      "creationDate": creationDate,
      "text": text,
    ]

    if let timeZone {
      entry["timeZone"] = timeZone
    }

    if !tags.isEmpty { entry["tags"] = tags }
    if !photos.isEmpty { entry["photos"] = photos }
    if !videos.isEmpty { entry["videos"] = videos }
    if !audios.isEmpty { entry["audios"] = audios }
    if !pdfs.isEmpty { entry["pdfs"] = pdfs }

    return entry
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
}
