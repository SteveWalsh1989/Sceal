import Foundation
import XCTest

@testable import Sceal

final class LibraryRepositoryTests: XCTestCase {
  // Daily notes load from the injected root, not the user's production library.
  func testLoadsDailyNotesFromInjectedRoot() throws {
    let repository = makeRepository()
    let notesDirectoryURL = try repository.dailyNotesDirectoryURL()
    try copyFixture("2026-05-10-composite.md", to: notesDirectoryURL)
    try copyFixture("2026-05-11-blank.md", to: notesDirectoryURL)

    let notes = try repository.loadDailyNotes()

    XCTAssertEqual(notes.map(\.id), ["2026-05-11", "2026-05-10"])
    XCTAssertEqual(notes.first?.title, "")
    XCTAssertEqual(notes.last?.title, #"Daily "Migration": fixture, sample"#)
  }

  // Saving a daily note writes the current markdown format under the injected root.
  func testSavesAndReloadsDailyNoteInInjectedRoot() throws {
    let repository = makeRepository()
    let note = DayNote(
      date: makeDate(year: 2026, month: 5, day: 12),
      title: "Saved",
      tags: ["repository", "migration"],
      body: "# Saved\n\n<!-- section -->\n"
    )

    try repository.saveDailyNote(note)
    let reloadedNote = try XCTUnwrap(repository.loadDailyNotes().first)

    XCTAssertEqual(reloadedNote.id, note.id)
    XCTAssertEqual(NoteDateFormatters.storageDate.string(from: reloadedNote.date), note.id)
    XCTAssertEqual(reloadedNote.title, note.title)
    XCTAssertEqual(reloadedNote.tags, note.tags)
    XCTAssertEqual(reloadedNote.body, note.body)
  }

  // List note loading reconciles groups.json without touching any live library path.
  func testLoadsListNotesAndReconcilesManifestInInjectedRoot() throws {
    let repository = makeRepository()
    let listNotesDirectoryURL = try repository.listNotesDirectoryURL()
    try copyFixture("project-alpha.md", to: listNotesDirectoryURL)
    var manifest = ListNotesManifest(
      ungroupedNoteIDs: ["missing-note"],
      groups: [NoteGroup(name: "Active", noteIDs: ["project-alpha", "missing-group-note"])]
    )
    try repository.saveListNotesManifest(manifest)

    let snapshot = try repository.loadListNotes()
    manifest.removeNoteID("missing-note")
    manifest.removeNoteID("missing-group-note")

    XCTAssertEqual(snapshot.notes.map(\.id), ["project-alpha"])
    XCTAssertEqual(snapshot.manifest, manifest)
    XCTAssertEqual(repository.loadListNotesManifest(), manifest)
  }

  // Delete helpers remove only the requested file inside the injected root.
  func testDeletesDailyNoteFileInInjectedRoot() throws {
    let repository = makeRepository()
    let note = DayNote(date: makeDate(year: 2026, month: 5, day: 13), title: "", tags: [], body: "")
    let noteURL = try repository.dailyNotesDirectoryURL().appendingPathComponent(note.fileName)

    try repository.saveDailyNote(note)
    XCTAssertTrue(FileManager.default.fileExists(atPath: noteURL.path))

    try repository.deleteDailyNoteFile(for: note)

    XCTAssertFalse(FileManager.default.fileExists(atPath: noteURL.path))
  }

  private func makeRepository() -> LibraryRepository {
    let rootURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("LibraryRepositoryTests-\(UUID().uuidString)", isDirectory: true)
    addTeardownBlock {
      try? FileManager.default.removeItem(at: rootURL)
    }

    return LibraryRepository(libraryLocation: .test(rootURL: rootURL))
  }

  private func copyFixture(_ fileName: String, to directoryURL: URL) throws {
    let sourceURL = try fixtureURL(fileName)
    let destinationURL = directoryURL.appendingPathComponent(fileName)
    try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
  }

  private func fixtureURL(_ fileName: String) throws -> URL {
    let fileURL = URL(fileURLWithPath: fileName)
    guard
      let resourceURL = Bundle(for: Self.self).url(
        forResource: fileURL.deletingPathExtension().lastPathComponent,
        withExtension: fileURL.pathExtension
      )
    else {
      throw LibraryRepositoryTestError.missingFixture(fileName)
    }

    return resourceURL
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

private enum LibraryRepositoryTestError: LocalizedError {
  case missingFixture(String)

  var errorDescription: String? {
    switch self {
    case .missingFixture(let fileName):
      return "Missing repository fixture: \(fileName)"
    }
  }
}
