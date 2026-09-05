import Foundation
import XCTest

@testable import Sceal

@MainActor
final class StructuredLibraryAuthorityTests: NotesStoreTestCase {
  // Fresh installs must explicitly initialize the structured runtime, even with no notes.
  func testFreshLibraryStartsStructuredAndRecordsCompletion() throws {
    let location = makeLibraryLocation()
    let store = makeStore(libraryLocation: location, enforcesStructuredCutover: true)
    store.prepareStructuredCutoverForProductionLaunch()
    XCTAssertTrue(store.hasLoaded)
    XCTAssertEqual(store.dailyNoteStorageMode, .structuredExperimental)
    XCTAssertEqual(store.structuredNotesCutoverStatus, .completed)
    XCTAssertTrue(try StructuredLibraryState.isCompleted(at: location))
  }

  // Existing production libraries acquire durable authority without reimporting older Markdown.
  func testCompletedPreferenceUpgradesToLibraryRecordAndSurvivesPreferenceLoss() throws {
    let location = makeLibraryLocation()
    let legacy = makeDailyNote(year: 2026, month: 9, day: 1, body: "Old Markdown")
    try LibraryRepository(libraryLocation: location).saveDailyNote(legacy)
    let sourceURL = location.legacyNotesDirectoryURL.appendingPathComponent(legacy.fileName)
    let sourceData = try Data(contentsOf: sourceURL)
    var document = StructuredNoteDocument.empty(id: legacy.id, date: legacy.date)
    document.title = "Newer structured edit"
    try saveStructuredLibrary([document], at: location)
    let defaults = makeUserDefaults()
    SettingsRepository(userDefaults: defaults).saveStructuredNotesCutoverStatus(.completed)
    let firstStore = makeStore(
      userDefaults: defaults, libraryLocation: location, enforcesStructuredCutover: true
    )
    firstStore.prepareStructuredCutoverForProductionLaunch()
    XCTAssertEqual(firstStore.structuredNotes, [document])
    XCTAssertTrue(try StructuredLibraryState.isCompleted(at: location))

    let relaunchedStore = makeStore(
      userDefaults: makeUserDefaults(), libraryLocation: location, enforcesStructuredCutover: true
    )
    relaunchedStore.prepareStructuredCutoverForProductionLaunch()
    XCTAssertEqual(relaunchedStore.structuredNotes, [document])
    XCTAssertEqual(relaunchedStore.dailyNoteStorageMode, .structuredExperimental)
    XCTAssertFalse(relaunchedStore.isStructuredCutoverPromptPresented)
    XCTAssertEqual(try Data(contentsOf: sourceURL), sourceData)
  }

  // Old recovery Markdown is not a prerequisite for opening an already converted library.
  func testCompletedLibraryOpensDespiteMalformedLegacyMarkdown() throws {
    let location = makeLibraryLocation()
    let document = StructuredNoteDocument.empty(
      id: "2026-09-01", date: makeDate(year: 2026, month: 9, day: 1)
    )
    try saveStructuredLibrary([document], at: location)
    try StructuredLibraryState.markCompleted(at: location)
    let legacyFolder = try location.notesDirectoryURL()
    let damagedURL = legacyFolder.appendingPathComponent("2026-09-01.md")
    let damagedBytes = Data([0xFF, 0xFE, 0xFF])
    try damagedBytes.write(to: damagedURL)
    let store = makeStore(libraryLocation: location, enforcesStructuredCutover: true)
    store.prepareStructuredCutoverForProductionLaunch()
    XCTAssertTrue(store.hasLoaded)
    XCTAssertEqual(store.structuredNotes, [document])
    XCTAssertEqual(try Data(contentsOf: damagedURL), damagedBytes)
  }

  // A deleted structured note stays deleted when old Markdown remains as a recovery source.
  func testAuthoritativeEmptyLibraryDoesNotResurrectLegacyNotes() throws {
    let location = makeLibraryLocation()
    let legacy = makeDailyNote(year: 2020, month: 1, day: 1, body: "Deliberately deleted later")
    try LibraryRepository(libraryLocation: location).saveDailyNote(legacy)
    try saveStructuredLibrary([], at: location)
    try StructuredLibraryState.markCompleted(at: location)
    let store = makeStore(libraryLocation: location, enforcesStructuredCutover: true)
    store.prepareStructuredCutoverForProductionLaunch()
    XCTAssertTrue(store.hasLoaded)
    XCTAssertFalse(store.structuredNotes.contains(where: { $0.id == legacy.id }))
    XCTAssertEqual(store.structuredNotesCutoverStatus, .completed)
  }

  // Mixed libraries without provenance must never be replaced by a fresh legacy conversion.
  func testAmbiguousMixedLibraryBlocksConversionWithoutChangingEitherCopy() throws {
    let location = makeLibraryLocation()
    let legacy = makeDailyNote(year: 2026, month: 9, day: 1, body: "Legacy text")
    let repository = LibraryRepository(libraryLocation: location)
    try repository.saveDailyNote(legacy)
    let sourceURL = location.legacyNotesDirectoryURL.appendingPathComponent(legacy.fileName)
    let sourceData = try Data(contentsOf: sourceURL)
    var document = StructuredNoteDocument.empty(id: legacy.id, date: legacy.date)
    document.title = "Structured text"
    try saveStructuredLibrary([document], at: location)
    let store = makeStore(libraryLocation: location, enforcesStructuredCutover: true)
    store.prepareStructuredCutoverForProductionLaunch()
    XCTAssertFalse(store.hasLoaded)
    XCTAssertEqual(store.structuredNotesCutoverStatus, .failedValidation)
    XCTAssertTrue(store.isStructuredCutoverPromptPresented)
    XCTAssertThrowsError(
      try StructuredLibraryCutover.perform(
        snapshot: store.makeLibrarySnapshot(),
        sourceDailyDocuments: [LegacyMarkdownStructuredNoteAdapter.importDocument(legacy)],
        sourceListDocuments: [], libraryLocation: location
      )
    )
    XCTAssertEqual(
      try StructuredNoteRepository(libraryLocation: location).loadDocuments(), [document])
    XCTAssertEqual(try Data(contentsOf: sourceURL), sourceData)
    XCTAssertFalse(try StructuredLibraryState.isCompleted(at: location))
  }

  // The guard also applies when the conversion action is invoked after a successful rollout.
  func testCompletedLibraryRejectsReconversionWithoutChangingCurrentState() throws {
    let location = makeLibraryLocation()
    try saveStructuredLibrary([], at: location)
    try StructuredLibraryState.markCompleted(at: location)
    let store = makeStore(libraryLocation: location, enforcesStructuredCutover: true)
    store.prepareStructuredCutoverForProductionLaunch()
    let currentDocuments = store.structuredNotes
    store.backUpAndConvertLegacyLibrary()
    XCTAssertFalse(store.isPerformingFileOperation)
    XCTAssertEqual(store.structuredNotesCutoverStatus, .completed)
    XCTAssertEqual(store.dailyNoteStorageMode, .structuredExperimental)
    XCTAssertEqual(store.structuredNotes, currentDocuments)
  }

  // Repositories normally create folders; an authoritative launch must instead notice missing storage.
  func testMissingAuthoritativeFolderIsNotRecreatedOrConverted() throws {
    let location = makeLibraryLocation()
    try saveStructuredLibrary([], at: location)
    try StructuredLibraryState.markCompleted(at: location)
    let missingFolder = location.structuredNotesDirectoryURL
    try FileManager.default.removeItem(at: missingFolder)
    let store = makeStore(libraryLocation: location, enforcesStructuredCutover: true)
    store.prepareStructuredCutoverForProductionLaunch()
    XCTAssertFalse(store.hasLoaded)
    XCTAssertEqual(store.structuredNotesCutoverStatus, .recoveryRequired)
    XCTAssertFalse(FileManager.default.fileExists(atPath: missingFolder.path))
  }

  // Older completed installs must retain that fact when validation fails before record creation.
  func testMissingStorageBeforeRecordUpgradeStaysBlockedAcrossRelaunchAndRetry() throws {
    let location = makeLibraryLocation()
    let legacy = makeDailyNote(year: 2026, month: 9, day: 1, body: "Old recovery text")
    try LibraryRepository(libraryLocation: location).saveDailyNote(legacy)
    let defaults = makeUserDefaults()
    SettingsRepository(userDefaults: defaults).saveStructuredNotesCutoverStatus(.completed)
    for _ in 0..<2 {
      let store = makeStore(
        userDefaults: defaults, libraryLocation: location, enforcesStructuredCutover: true
      )
      store.prepareStructuredCutoverForProductionLaunch()
      XCTAssertEqual(store.structuredNotesCutoverStatus, .recoveryRequired)
      store.backUpAndConvertLegacyLibrary()
      XCTAssertFalse(store.hasLoaded)
      XCTAssertFalse(store.isPerformingFileOperation)
      XCTAssertFalse(
        FileManager.default.fileExists(atPath: location.structuredNotesDirectoryURL.path))
      XCTAssertEqual(
        SettingsRepository(userDefaults: defaults).loadStructuredNotesCutoverStatus(),
        .recoveryRequired)
    }
  }

  // Unknown versions and damaged completion records cannot be treated as a new installation.
  func testInvalidCompletionRecordBlocksStartupWithoutOverwritingIt() throws {
    for contents in ["invalid", "{\"version\":2,\"storageFormat\":\"structured\"}"] {
      let location = makeLibraryLocation()
      try saveStructuredLibrary([], at: location)
      let data = Data(contents.utf8)
      try data.write(to: location.structuredLibraryStateURL)
      let store = makeStore(libraryLocation: location, enforcesStructuredCutover: true)
      store.prepareStructuredCutoverForProductionLaunch()
      XCTAssertFalse(store.hasLoaded)
      XCTAssertEqual(store.structuredNotesCutoverStatus, .failedValidation)
      XCTAssertEqual(try Data(contentsOf: location.structuredLibraryStateURL), data)
    }
  }

  // Completion-record write failures preserve authority and permit a safe retry after repair.
  func testUnwritableCompletionRecordRetainsAuthorityAndCanRetry() throws {
    let location = makeLibraryLocation()
    let document = StructuredNoteDocument.empty(
      id: "2026-09-01", date: makeDate(year: 2026, month: 9, day: 1)
    )
    try saveStructuredLibrary([document], at: location)
    let attributes = try FileManager.default.attributesOfItem(atPath: location.rootURL.path)
    let permissions = try XCTUnwrap(attributes[.posixPermissions])
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: permissions], ofItemAtPath: location.rootURL.path
      )
    }
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o500], ofItemAtPath: location.rootURL.path
    )
    let defaults = makeUserDefaults()
    SettingsRepository(userDefaults: defaults).saveStructuredNotesCutoverStatus(.completed)
    let store = makeStore(
      userDefaults: defaults, libraryLocation: location, enforcesStructuredCutover: true
    )
    store.prepareStructuredCutoverForProductionLaunch()
    XCTAssertFalse(store.hasLoaded)
    XCTAssertEqual(store.structuredNotesCutoverStatus, .recoveryRequired)
    XCTAssertNotNil(store.structuredNotesCutoverFailureDescription)
    XCTAssertFalse(try StructuredLibraryState.isCompleted(at: location))
    try FileManager.default.setAttributes(
      [.posixPermissions: permissions], ofItemAtPath: location.rootURL.path
    )
    store.prepareStructuredCutoverForProductionLaunch()
    XCTAssertTrue(store.hasLoaded)
    XCTAssertEqual(store.structuredNotes, [document])
    XCTAssertTrue(try StructuredLibraryState.isCompleted(at: location))
    XCTAssertNil(store.structuredNotesCutoverFailureDescription)
  }

  // A damaged active document must not fall back to a stale Markdown copy of the same note.
  func testCorruptStructuredDocumentRequiresRecoveryAndRemainsUntouched() throws {
    let location = makeLibraryLocation()
    try saveStructuredLibrary([], at: location)
    try StructuredLibraryState.markCompleted(at: location)
    let damagedURL = location.structuredNotesDirectoryURL.appendingPathComponent(
      "2026-09-01.scealnote")
    let damagedBytes = Data("invalid structured document".utf8)
    try damagedBytes.write(to: damagedURL)
    let store = makeStore(libraryLocation: location, enforcesStructuredCutover: true)
    store.prepareStructuredCutoverForProductionLaunch()
    XCTAssertFalse(store.hasLoaded)
    XCTAssertEqual(store.structuredNotesCutoverStatus, .recoveryRequired)
    XCTAssertNotNil(store.structuredNotesCutoverFailureDescription)
    store.backUpAndConvertLegacyLibrary()
    XCTAssertFalse(store.isPerformingFileOperation)
    XCTAssertEqual(try Data(contentsOf: damagedURL), damagedBytes)
  }

  // Builds both required structured folders without reading or changing production data.
  private func saveStructuredLibrary(
    _ documents: [StructuredNoteDocument], at location: ScealLibraryLocation
  ) throws {
    let repository = StructuredNoteRepository(libraryLocation: location)
    _ = try repository.loadDocuments()
    for document in documents {
      try repository.save(document)
    }
    try LibraryRepository(libraryLocation: location).saveStructuredListNotesManifest(.empty)
  }
}
