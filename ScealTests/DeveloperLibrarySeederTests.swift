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
      let preserved = try XCTUnwrap(snapshot.developerBackupURL)
      addTeardownBlock { try? FileManager.default.removeItem(at: preserved) }
      XCTAssertEqual(
        try Data(contentsOf: preserved.appendingPathComponent("stale.txt")), Data("stale".utf8))
      XCTAssertTrue(try StructuredLibraryState.isCompleted(at: location))
      XCTAssertEqual(
        try StructuredNoteRepository(libraryLocation: location).loadDocuments().map(\.id),
        snapshot.dailyNotes.map(\.id))
      XCTAssertEqual(
        try StructuredNoteRepository.listNotes(libraryLocation: location).loadDocuments().map(\.id),
        snapshot.listNotes.map(\.id))
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

    // Completed structured libraries do not depend on retained Markdown being parseable.
    func testStructuredCopyPreservesSourceAndDoesNotParseObsoleteMarkdown() throws {
      let workspace = try makeTemporaryDirectory()
      let source = ScealLibraryLocation.test(rootURL: workspace.appendingPathComponent("Source"))
      let destination = ScealLibraryLocation.test(
        rootURL: workspace.appendingPathComponent("Destination"))
      let document = StructuredNoteDocument.empty(
        id: "2026-09-01", date: makeDate(year: 2026, month: 9, day: 1))
      try StructuredNoteRepository(libraryLocation: source).save(document)
      try LibraryRepository(libraryLocation: source).saveStructuredListNotesManifest(.empty)
      try StructuredLibraryState.markCompleted(at: source)
      try LibraryArchiveFiles(files: ["bad.md": Data([0xFF, 0xFE])]).write(
        to: source.legacyNotesDirectoryURL)
      let before = try LibraryArchiveFiles.read(from: source.rootURL)
      let snapshot = try DeveloperLibrarySeeder.copyProductionLibraryToDeveloper(
        at: destination, productionLocation: source)
      XCTAssertEqual(snapshot.dailyNotes.map(\.id), [document.id])
      XCTAssertEqual(try LibraryArchiveFiles.read(from: source.rootURL), before)
      XCTAssertEqual(try LibraryArchiveFiles.read(from: destination.rootURL), before)
    }

    // Source validation happens in staging, before the existing developer folder is displaced.
    func testInvalidStructuredCopyLeavesDeveloperLibraryUntouched() throws {
      let workspace = try makeTemporaryDirectory()
      let source = ScealLibraryLocation.test(rootURL: workspace.appendingPathComponent("Source"))
      let destination = ScealLibraryLocation.test(
        rootURL: workspace.appendingPathComponent("Destination"))
      try LibraryArchiveFiles(files: ["broken.scealnote": Data("broken".utf8)]).write(
        to: source.structuredNotesDirectoryURL)
      try LibraryRepository(libraryLocation: source).saveStructuredListNotesManifest(.empty)
      try StructuredLibraryState.markCompleted(at: source)
      let original = LibraryArchiveFiles(files: ["Notes/keep.md": Data("keep".utf8)])
      try original.write(to: destination.rootURL)
      XCTAssertThrowsError(
        try DeveloperLibrarySeeder.copyProductionLibraryToDeveloper(
          at: destination, productionLocation: source))
      XCTAssertEqual(try LibraryArchiveFiles.read(from: destination.rootURL), original)
    }

    func testDeveloperCopyRejectsOverlappingRootsAndSymlinksToSource() throws {
      let workspace = try makeTemporaryDirectory()
      let source = ScealLibraryLocation.test(rootURL: workspace.appendingPathComponent("Source"))
      try FileManager.default.createDirectory(at: source.rootURL, withIntermediateDirectories: true)
      let link = workspace.appendingPathComponent("Alias")
      try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source.rootURL)
      for root in [source.rootURL.appendingPathComponent("Nested"), workspace, link] {
        XCTAssertFalse(
          DeveloperLibrarySeeder.canCopyProductionLibraryToDeveloper(
            at: .test(rootURL: root), productionLocation: source))
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
