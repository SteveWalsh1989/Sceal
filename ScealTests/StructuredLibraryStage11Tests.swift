import Foundation
import XCTest

@testable import Sceal

@MainActor
final class StructuredLibraryStage11Tests: NotesStoreTestCase {
  func testProductionLaunchRequiresConversionBeforeLoadingLegacyLibrary() throws {
    let location = makeLibraryLocation()
    let note = makeDailyNote(year: 2026, month: 9, day: 3, body: "Legacy")
    try LibraryRepository(libraryLocation: location).saveDailyNote(note)
    let defaults = makeUserDefaults()
    let store = makeStore(
      userDefaults: defaults,
      libraryLocation: location,
      enforcesStructuredCutover: true
    )

    store.prepareStructuredCutoverForProductionLaunch()

    XCTAssertEqual(store.structuredNotesCutoverStatus, .conversionRequired)
    XCTAssertFalse(store.hasLoaded)
    XCTAssertTrue(store.isStructuredCutoverPromptPresented)
    XCTAssertEqual(store.dailyNoteStorageMode, .legacyMarkdown)
    XCTAssertEqual(
      SettingsRepository(userDefaults: defaults).loadStructuredNotesCutoverStatus(),
      .conversionRequired
    )
  }

  func testDeferringCutoverLoadsOnlyLegacyLibrary() throws {
    let location = makeLibraryLocation()
    let note = makeDailyNote(year: 2026, month: 9, day: 3, body: "Legacy")
    try LibraryRepository(libraryLocation: location).saveDailyNote(note)
    let store = makeStore(
      userDefaults: makeUserDefaults(),
      libraryLocation: location,
      enforcesStructuredCutover: true
    )
    store.prepareStructuredCutoverForProductionLaunch()

    store.continueUsingLegacyForNow()

    XCTAssertTrue(store.hasLoaded)
    XCTAssertEqual(store.notes.map(\.id), [note.id])
    XCTAssertEqual(store.dailyNoteStorageMode, .legacyMarkdown)
    XCTAssertEqual(store.structuredNotesCutoverStatus, .conversionRequired)
  }

  func testCutoverCreatesBackupPreservesMarkdownAndInstallsExactStructuredLibrary() throws {
    let location = makeLibraryLocation()
    let repository = LibraryRepository(libraryLocation: location)
    let dailyNote = makeDailyNote(
      year: 2026,
      month: 9,
      day: 3,
      title: "Daily",
      body: "# Focus\n\n- preserve\n<!-- section:orange -->\n## Later"
    )
    let listNote = makeListNote(
      id: "project",
      year: 2026,
      month: 9,
      day: 2,
      title: "Project",
      body: "- [ ] Preserve"
    )
    let manifest = ListNotesManifest(
      ungroupedNoteIDs: [],
      groups: [NoteGroup(name: "Projects", noteIDs: [listNote.id], isCollapsed: true)]
    )
    try repository.saveDailyNote(dailyNote)
    try repository.saveListNote(listNote)
    try repository.saveListNotesManifest(manifest)
    let dailySourceURL = location.legacyNotesDirectoryURL.appendingPathComponent(
      dailyNote.fileName
    )
    let listSourceURL = location.rootURL
      .appendingPathComponent(ScealLibraryLocation.listNotesFolderName, isDirectory: true)
      .appendingPathComponent(listNote.fileName)
    let sourceData = try [dailySourceURL, listSourceURL].map { try Data(contentsOf: $0) }
    let store = makeStore(userDefaults: makeUserDefaults(), libraryLocation: location)
    let snapshot = try store.makeLibrarySnapshot()
    let dailyDocuments = try StructuredNoteRepository(
      libraryLocation: location
    ).prepareLegacyDocuments()
    let listDocuments = try StructuredNoteRepository.listNotes(
      libraryLocation: location
    ).prepareLegacyDocuments()

    let result = try StructuredLibraryCutover.perform(
      snapshot: snapshot,
      sourceDailyDocuments: dailyDocuments,
      sourceListDocuments: listDocuments,
      libraryLocation: location
    )

    XCTAssertEqual(
      try [dailySourceURL, listSourceURL].map { try Data(contentsOf: $0) }, sourceData)
    XCTAssertEqual(result.dailyDocuments.map(\.id), [dailyNote.id])
    XCTAssertEqual(result.listDocuments.map(\.id), [listNote.id])
    XCTAssertEqual(result.listManifest, manifest)
    XCTAssertTrue(FileManager.default.fileExists(atPath: result.safetyArchiveURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: result.reportURL.path))
    let report = try JSONDecoder().decode(
      StructuredLibraryMigrationReport.self,
      from: Data(contentsOf: result.reportURL)
    )
    XCTAssertTrue(report.passedContentValidation)
    XCTAssertTrue(report.legacyLibraryPreserved)
  }

  func testStoreCutoverMarksCompleteOnlyAfterValidatedReload() async throws {
    let location = makeLibraryLocation()
    let note = makeDailyNote(
      year: 2026,
      month: 9,
      day: 3,
      title: "Production",
      body: "# Ready"
    )
    try LibraryRepository(libraryLocation: location).saveDailyNote(note)
    let defaults = makeUserDefaults()
    let store = makeStore(
      userDefaults: defaults,
      libraryLocation: location,
      enforcesStructuredCutover: true
    )
    store.prepareStructuredCutoverForProductionLaunch()

    store.backUpAndConvertLegacyLibrary()
    for _ in 0..<200 where store.isPerformingFileOperation {
      try await Task.sleep(nanoseconds: 10_000_000)
    }

    XCTAssertFalse(store.isPerformingFileOperation)
    XCTAssertEqual(store.structuredNotesCutoverStatus, .completed)
    XCTAssertEqual(store.dailyNoteStorageMode, .structuredExperimental)
    XCTAssertEqual(store.structuredNotes.map(\.id), [note.id])
    XCTAssertTrue(store.hasLoaded)
    XCTAssertEqual(
      SettingsRepository(userDefaults: defaults).loadStructuredNotesCutoverStatus(),
      .completed
    )
  }

  func testCompletedCutoverLoadsStructuredLibraryOnProductionLaunch() throws {
    let location = makeLibraryLocation()
    let date = makeDate(year: 2026, month: 9, day: 3)
    try StructuredNoteRepository(libraryLocation: location).save(
      .empty(id: "2026-09-03", date: date)
    )
    try LibraryRepository(libraryLocation: location).saveStructuredListNotesManifest(.empty)
    let defaults = makeUserDefaults()
    let settings = SettingsRepository(userDefaults: defaults)
    settings.saveStructuredNotesCutoverStatus(.completed)
    settings.saveDailyNoteStorageMode(.structuredExperimental)
    let store = makeStore(
      userDefaults: defaults,
      libraryLocation: location,
      enforcesStructuredCutover: true
    )

    store.prepareStructuredCutoverForProductionLaunch()

    XCTAssertTrue(store.hasLoaded)
    XCTAssertEqual(store.dailyNoteStorageMode, .structuredExperimental)
    XCTAssertEqual(store.structuredNotes.map(\.id), ["2026-09-03"])
  }

  func testCompletedCutoverRespectsExplicitLegacyRollbackMode() throws {
    let location = makeLibraryLocation()
    let legacyNote = makeDailyNote(year: 2026, month: 9, day: 3, body: "Legacy")
    try LibraryRepository(libraryLocation: location).saveDailyNote(legacyNote)
    let date = makeDate(year: 2026, month: 9, day: 3)
    try StructuredNoteRepository(libraryLocation: location).save(
      .empty(id: "2026-09-03", date: date)
    )
    try LibraryRepository(libraryLocation: location).saveStructuredListNotesManifest(.empty)
    let defaults = makeUserDefaults()
    let settings = SettingsRepository(userDefaults: defaults)
    settings.saveStructuredNotesCutoverStatus(.completed)
    settings.saveDailyNoteStorageMode(.legacyMarkdown)
    let store = makeStore(
      userDefaults: defaults,
      libraryLocation: location,
      enforcesStructuredCutover: true
    )

    store.prepareStructuredCutoverForProductionLaunch()

    XCTAssertTrue(store.hasLoaded)
    XCTAssertEqual(store.dailyNoteStorageMode, .legacyMarkdown)
    XCTAssertEqual(store.notes.map(\.id), [legacyNote.id])
  }

  func testProductionModeCannotEnableStructuredLibraryBeforeValidation() {
    let store = makeStore(enforcesStructuredCutover: true)

    store.updateDailyNoteStorageMode(.structuredExperimental)

    XCTAssertEqual(store.dailyNoteStorageMode, .legacyMarkdown)
    XCTAssertEqual(
      store.userMessage?.text,
      "Back up and convert the legacy library before enabling Structured Notes V2."
    )
  }
}
