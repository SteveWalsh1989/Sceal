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

  func testValidatedRestoreCompletesCutoverAndPersistsStructuredMode() {
    let defaults = makeUserDefaults()
    let settings = SettingsRepository(userDefaults: defaults)
    settings.saveStructuredNotesCutoverStatus(.conversionRequired)
    settings.saveDailyNoteStorageMode(.legacyMarkdown)
    let store = makeStore(
      userDefaults: defaults,
      enforcesStructuredCutover: true
    )

    store.completeStructuredCutoverAfterValidatedRestore()

    XCTAssertEqual(store.structuredNotesCutoverStatus, .completed)
    XCTAssertEqual(store.dailyNoteStorageMode, .structuredExperimental)
    XCTAssertEqual(settings.loadStructuredNotesCutoverStatus(), .completed)
    XCTAssertEqual(settings.loadDailyNoteStorageMode(), .structuredExperimental)
  }

  func testLegacyOnlyVersionTwoArchiveConvertsBeforeReplacingStructuredStorage() throws {
    let sourceLocation = makeLibraryLocation()
    let legacyNote = makeDailyNote(
      year: 2026,
      month: 9,
      day: 1,
      title: "Legacy-only backup",
      body: "First\n<!-- section heading:orange -->\nSecond"
    )
    let sourceStore = makeStore(
      userDefaults: makeUserDefaults(),
      libraryLocation: sourceLocation
    )
    let legacySettings = try sourceStore.makeArchiveSettings()
    let archiveURL = try ScealBackupArchiveExporter.exportBackup(
      dailyNotes: [legacyNote],
      listNotes: [],
      manifest: .empty,
      structuredDailyNotes: [],
      structuredListNotes: [],
      structuredListManifest: .empty,
      settings: legacySettings,
      kind: .manual
    )
    defer { ZipArchiveWriter.cleanUp(zipURL: archiveURL) }
    let destinationLocation = makeLibraryLocation()
    let destinationRepository = LibraryRepository(libraryLocation: destinationLocation)

    let result = try ScealBackupArchiveImporter.restoreLibrary(
      from: archiveURL,
      currentDailyNotes: [],
      currentListNotes: [],
      currentManifest: .empty,
      destinationURLs: destinationRepository.storageURLs(),
      safetyArchiveDirectoryURL: destinationLocation.restoreSafetyArchiveDirectoryURL()
    )

    XCTAssertEqual(result.metadata.structuredStorageIsAuthoritative, false)
    XCTAssertEqual(result.structuredDailyNotes.map(\.id), [legacyNote.id])
    XCTAssertEqual(result.structuredDailyNotes.first?.nodes.count, 2)
    XCTAssertEqual(
      result.settings?.dailyNoteStorageModeRawValue,
      DailyNoteStorageMode.structuredExperimental.rawValue
    )
    XCTAssertEqual(
      try StructuredNoteRepository(libraryLocation: destinationLocation).loadDocuments(),
      result.structuredDailyNotes
    )
  }

  func testAuthoritativeVersionTwoArchiveDoesNotReintroduceDeletedLegacyNotes() throws {
    let sourceLocation = makeLibraryLocation()
    let legacyNote = makeDailyNote(year: 2026, month: 9, day: 1, body: "Deleted in V2")
    let defaults = makeUserDefaults()
    let sourceStore = makeStore(userDefaults: defaults, libraryLocation: sourceLocation)
    sourceStore.updateDailyNoteStorageMode(.structuredExperimental)
    let structuredSettings = try sourceStore.makeArchiveSettings()
    let archiveURL = try ScealBackupArchiveExporter.exportBackup(
      dailyNotes: [legacyNote],
      listNotes: [],
      manifest: .empty,
      structuredDailyNotes: [],
      structuredListNotes: [],
      structuredListManifest: .empty,
      settings: structuredSettings,
      kind: .manual
    )
    defer { ZipArchiveWriter.cleanUp(zipURL: archiveURL) }
    let destinationLocation = makeLibraryLocation()
    let destinationRepository = LibraryRepository(libraryLocation: destinationLocation)

    let result = try ScealBackupArchiveImporter.restoreLibrary(
      from: archiveURL,
      currentDailyNotes: [],
      currentListNotes: [],
      currentManifest: .empty,
      destinationURLs: destinationRepository.storageURLs(),
      safetyArchiveDirectoryURL: destinationLocation.restoreSafetyArchiveDirectoryURL()
    )

    XCTAssertEqual(result.metadata.structuredStorageIsAuthoritative, true)
    XCTAssertTrue(result.structuredDailyNotes.isEmpty)
    XCTAssertTrue(
      try StructuredNoteRepository(libraryLocation: destinationLocation).loadDocuments().isEmpty
    )
  }

  func testLegacyAuthoritativeVersionTwoArchiveReplacesStaleCopiesAndConvertsMissingNotes()
    throws
  {
    let sourceLocation = makeLibraryLocation()
    let retainedLegacyNote = makeDailyNote(
      year: 2026,
      month: 9,
      day: 1,
      title: "Legacy title",
      body: "Legacy source"
    )
    let missingLegacyNote = makeDailyNote(
      year: 2026,
      month: 9,
      day: 2,
      title: "Missing copy",
      body: "Convert me"
    )
    let retainedStructuredDocument = StructuredNoteDocument(
      id: retainedLegacyNote.id,
      date: retainedLegacyNote.date,
      title: "Exact structured title",
      tags: ["structured"],
      nodes: [.section(StructuredNoteSection(markdown: "Edited structured content"))]
    )
    let sourceStore = makeStore(
      userDefaults: makeUserDefaults(),
      libraryLocation: sourceLocation
    )
    let archiveURL = try ScealBackupArchiveExporter.exportBackup(
      dailyNotes: [retainedLegacyNote, missingLegacyNote],
      listNotes: [],
      manifest: .empty,
      structuredDailyNotes: [retainedStructuredDocument],
      structuredListNotes: [],
      structuredListManifest: .empty,
      settings: try sourceStore.makeArchiveSettings(),
      kind: .manual
    )
    defer { ZipArchiveWriter.cleanUp(zipURL: archiveURL) }
    let destinationLocation = makeLibraryLocation()
    let destinationRepository = LibraryRepository(libraryLocation: destinationLocation)

    let result = try ScealBackupArchiveImporter.restoreLibrary(
      from: archiveURL,
      currentDailyNotes: [],
      currentListNotes: [],
      currentManifest: .empty,
      destinationURLs: destinationRepository.storageURLs(),
      safetyArchiveDirectoryURL: destinationLocation.restoreSafetyArchiveDirectoryURL()
    )

    XCTAssertEqual(result.metadata.structuredStorageIsAuthoritative, false)
    XCTAssertEqual(
      Set(result.structuredDailyNotes.map(\.id)),
      [
        retainedLegacyNote.id, missingLegacyNote.id,
      ])
    XCTAssertEqual(
      result.structuredDailyNotes.first(where: { $0.id == retainedLegacyNote.id })?.title,
      retainedLegacyNote.title
    )
    XCTAssertEqual(
      result.structuredDailyNotes.first(where: { $0.id == missingLegacyNote.id })?.title,
      missingLegacyNote.title
    )
  }

  func testUnmarkedHistoricalVersionTwoArchivePreservesExactCopiesAndConvertsMissingNotes()
    throws
  {
    let sourceLocation = makeLibraryLocation()
    let retainedLegacyNote = makeDailyNote(
      year: 2026,
      month: 9,
      day: 1,
      title: "Legacy title",
      body: "Legacy source"
    )
    let missingLegacyNote = makeDailyNote(
      year: 2026,
      month: 9,
      day: 2,
      title: "Missing copy",
      body: "Convert me"
    )
    let retainedStructuredDocument = StructuredNoteDocument(
      id: retainedLegacyNote.id,
      date: retainedLegacyNote.date,
      title: "Exact structured title",
      tags: ["structured"],
      nodes: [.section(StructuredNoteSection(markdown: "Edited structured content"))]
    )
    let sourceStore = makeStore(
      userDefaults: makeUserDefaults(),
      libraryLocation: sourceLocation
    )
    let archiveURL = try ScealBackupArchiveExporter.exportBackup(
      dailyNotes: [retainedLegacyNote, missingLegacyNote],
      listNotes: [],
      manifest: .empty,
      structuredDailyNotes: [retainedStructuredDocument],
      structuredListNotes: [],
      structuredListManifest: .empty,
      settings: try sourceStore.makeArchiveSettings(),
      kind: .manual
    )
    defer { ZipArchiveWriter.cleanUp(zipURL: archiveURL) }
    let historicalArchiveURL = try archiveWithoutStructuredAuthorityMarker(archiveURL)
    let destinationLocation = makeLibraryLocation()
    let destinationRepository = LibraryRepository(libraryLocation: destinationLocation)

    let result = try ScealBackupArchiveImporter.restoreLibrary(
      from: historicalArchiveURL,
      currentDailyNotes: [],
      currentListNotes: [],
      currentManifest: .empty,
      destinationURLs: destinationRepository.storageURLs(),
      safetyArchiveDirectoryURL: destinationLocation.restoreSafetyArchiveDirectoryURL()
    )

    XCTAssertNil(result.metadata.structuredStorageIsAuthoritative)
    XCTAssertEqual(
      result.structuredDailyNotes.first(where: { $0.id == retainedLegacyNote.id }),
      retainedStructuredDocument
    )
    XCTAssertEqual(
      result.structuredDailyNotes.first(where: { $0.id == missingLegacyNote.id })?.title,
      missingLegacyNote.title
    )
  }

  // Recreates a historical version 2 fixture written before authority metadata existed.
  private func archiveWithoutStructuredAuthorityMarker(_ archiveURL: URL) throws -> URL {
    let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      "StructuredStage11-Historical-\(UUID().uuidString)",
      isDirectory: true
    )
    let extractionURL = baseURL.appendingPathComponent("Extracted", isDirectory: true)
    try FileManager.default.createDirectory(at: extractionURL, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: baseURL) }
    try ZipArchiveWriter.extractZip(from: archiveURL, to: extractionURL)
    let managedRootURL = extractionURL.appendingPathComponent(
      ScealBackupArchiveExporter.managedFolderName,
      isDirectory: true
    )
    let rootURL =
      FileManager.default.fileExists(
        atPath: managedRootURL.appendingPathComponent("backup-metadata.json").path
      ) ? managedRootURL : extractionURL
    let metadataURL = rootURL.appendingPathComponent("backup-metadata.json")
    guard
      var metadata = try JSONSerialization.jsonObject(
        with: Data(contentsOf: metadataURL)
      ) as? [String: Any]
    else {
      throw StructuredLibraryStage11TestError.invalidMetadataFixture
    }
    metadata.removeValue(forKey: "structuredStorageIsAuthoritative")
    try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
      .write(to: metadataURL, options: .atomic)
    let outputURL = baseURL.appendingPathComponent("historical-v2.zip")
    try ZipArchiveWriter.createZip(from: rootURL, to: outputURL)
    return outputURL
  }
}

private enum StructuredLibraryStage11TestError: Error {
  case invalidMetadataFixture
}
