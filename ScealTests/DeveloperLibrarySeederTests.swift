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

    func testCopyProductionLibraryToDeveloperCopiesNotesAndBacksUpDeveloperRoot() throws {
      let workspaceRootURL = try makeTemporaryDirectory()
      let productionRootURL = workspaceRootURL.appendingPathComponent(
        "Production", isDirectory: true)
      let developerRootURL = workspaceRootURL.appendingPathComponent("Developer", isDirectory: true)
      let productionLocation = ScealLibraryLocation.test(rootURL: productionRootURL)
      let developerLocation = ScealLibraryLocation.test(rootURL: developerRootURL)
      let productionRepository = LibraryRepository(libraryLocation: productionLocation)
      let dailyNote = DayNote(
        date: makeDate(year: 2026, month: 5, day: 9),
        title: "Real daily note",
        tags: ["real"],
        body: "Production daily body"
      )
      let listNote = DayNote(
        date: makeDate(year: 2026, month: 5, day: 9),
        id: "real-list-note",
        title: "Real list note",
        tags: ["list"],
        body: "Production list body"
      )
      let attachmentDirectoryURL = productionRootURL.appendingPathComponent(
        "Attachments/real-list-note",
        isDirectory: true
      )
      let staleDeveloperURL = developerRootURL.appendingPathComponent("stale.txt")

      try productionRepository.saveDailyNote(dailyNote)
      try productionRepository.saveListNote(listNote)
      try productionRepository.saveListNotesManifest(
        ListNotesManifest(
          ungroupedNoteIDs: [listNote.id],
          groups: []
        )
      )
      try FileManager.default.createDirectory(
        at: attachmentDirectoryURL,
        withIntermediateDirectories: true
      )
      try Data("attachment".utf8).write(
        to: attachmentDirectoryURL.appendingPathComponent("file.txt")
      )
      try FileManager.default.createDirectory(
        at: developerRootURL,
        withIntermediateDirectories: true
      )
      try Data("stale developer data".utf8).write(to: staleDeveloperURL)

      let snapshot = try DeveloperLibrarySeeder.copyProductionLibraryToDeveloper(
        at: developerLocation,
        productionLocation: productionLocation
      )

      XCTAssertEqual(snapshot.dailyNotes.map(\.id), [dailyNote.id])
      XCTAssertEqual(snapshot.listNotes.map(\.id), [listNote.id])
      XCTAssertEqual(snapshot.manifest.allNoteIDs, [listNote.id])
      XCTAssertFalse(FileManager.default.fileExists(atPath: staleDeveloperURL.path))
      XCTAssertTrue(
        FileManager.default.fileExists(
          atPath: developerRootURL.appendingPathComponent("Notes/\(dailyNote.fileName)").path
        )
      )
      XCTAssertTrue(
        FileManager.default.fileExists(
          atPath: developerRootURL.appendingPathComponent("ListNotes/\(listNote.fileName)").path
        )
      )
      XCTAssertTrue(
        FileManager.default.fileExists(
          atPath: developerRootURL.appendingPathComponent(
            "Attachments/real-list-note/file.txt"
          ).path
        )
      )
      let backupURL = try XCTUnwrap(snapshot.developerBackupURL)
      XCTAssertTrue(
        FileManager.default.fileExists(
          atPath: backupURL.appendingPathComponent("stale.txt").path
        )
      )
    }

    func testCopyProductionLibraryToDeveloperRefusesMissingProductionRoot() throws {
      let productionLocation = ScealLibraryLocation.test(rootURL: try makeTemporaryDirectory())
      let developerLocation = ScealLibraryLocation.test(rootURL: try makeTemporaryDirectory())

      XCTAssertThrowsError(
        try DeveloperLibrarySeeder.copyProductionLibraryToDeveloper(
          at: developerLocation,
          productionLocation: productionLocation
        )
      ) { error in
        guard case DeveloperLibrarySeederError.missingProductionLibrary = error else {
          return XCTFail("Expected missing production library, got \(error).")
        }
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
