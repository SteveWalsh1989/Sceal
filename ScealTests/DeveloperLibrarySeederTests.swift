#if DEBUG
  import Foundation
  import XCTest

  @testable import Sceal

  final class DeveloperLibrarySeederTests: XCTestCase {
    func testResetLibrarySeedsDailyNotesListNotesManifestAndAttachmentInTempRoot() throws {
      let rootURL = try makeTemporaryDirectory()
      let location = ScealLibraryLocation.test(rootURL: rootURL)
      let staleURL = rootURL.appendingPathComponent("stale.txt")
      try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
      try Data("stale".utf8).write(to: staleURL)

      let snapshot = try DeveloperLibrarySeeder.resetLibrary(
        at: location,
        calendar: Calendar(identifier: .gregorian),
        referenceDate: makeDate(year: 2026, month: 5, day: 10)
      )

      XCTAssertEqual(
        snapshot.dailyNotes.map(\.id),
        [
          "2026-05-10", "2026-05-09", "2026-05-08", "2026-05-07",
        ])
      XCTAssertEqual(snapshot.listNotes.map(\.id), ["developer-library-checklist"])
      XCTAssertEqual(snapshot.manifest.allNoteIDs, ["developer-library-checklist"])
      XCTAssertFalse(FileManager.default.fileExists(atPath: staleURL.path))
      XCTAssertTrue(
        FileManager.default.fileExists(
          atPath: rootURL.appendingPathComponent("Notes/2026-05-10.md").path
        )
      )
      XCTAssertTrue(
        FileManager.default.fileExists(
          atPath: rootURL.appendingPathComponent("ListNotes/developer-library-checklist.md").path
        )
      )
      XCTAssertTrue(
        FileManager.default.fileExists(
          atPath: rootURL.appendingPathComponent("ListNotes/groups.json").path
        )
      )
      XCTAssertTrue(
        FileManager.default.fileExists(
          atPath: rootURL.appendingPathComponent(
            "Attachments/developer-library-checklist/developer-attachment.png"
          ).path
        )
      )
      XCTAssertTrue(
        FileManager.default.fileExists(
          atPath: rootURL.appendingPathComponent("Restore Safety Backups").path
        )
      )
    }

    func testResetLibraryRefusesProductionRoot() {
      let productionRootURL = ScealLibraryLocation.production().rootURL

      XCTAssertThrowsError(
        try DeveloperLibrarySeeder.validateResetRoot(productionRootURL)
      ) { error in
        XCTAssertEqual(error as? DeveloperLibrarySeederError, .refusingProductionLibrary)
      }
    }

    private func makeTemporaryDirectory() throws -> URL {
      let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(
          "DeveloperLibrarySeederTests-\(UUID().uuidString)", isDirectory: true)
      addTeardownBlock {
        try? FileManager.default.removeItem(at: directoryURL)
      }
      return directoryURL
    }

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
#endif
