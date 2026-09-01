import Foundation
import XCTest

@testable import Sceal

@MainActor
final class NotesStoreStructuredModeTests: NotesStoreTestCase {
  // Keeps new and release-compatible settings on the existing Markdown path by default.
  func testDefaultsToLegacyMarkdownStorage() {
    let store = makeStore(userDefaults: makeUserDefaults())

    XCTAssertEqual(store.dailyNoteStorageMode, .legacyMarkdown)
    XCTAssertFalse(store.isStructuredDailyNoteMode)
    XCTAssertEqual(store.activeDailyNotesStorageURL, store.legacyDailyNotesStorageURL)
  }

  // Launches directly into an empty structured library without seeding the inactive legacy path.
  func testStructuredLaunchDoesNotCreateOrWriteLegacyNotesDirectory() {
    let userDefaults = makeUserDefaults()
    let libraryLocation = makeLibraryLocation()
    SettingsRepository(userDefaults: userDefaults).saveDailyNoteStorageMode(
      .structuredExperimental
    )
    let store = makeStore(userDefaults: userDefaults, libraryLocation: libraryLocation)

    store.loadIfNeeded()

    XCTAssertTrue(store.isStructuredDailyNoteMode)
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: store.structuredDailyNotesStorageURL.path)
    )
    XCTAssertFalse(FileManager.default.fileExists(atPath: store.legacyDailyNotesStorageURL.path))
    XCTAssertTrue(store.notes.isEmpty)
    XCTAssertTrue(store.structuredNotes.isEmpty)
  }

  // Persists copied documents and their stable section IDs across a fresh store launch.
  func testLegacyCopySurvivesRelaunchWithoutChangingSourceMarkdown() throws {
    let userDefaults = makeUserDefaults()
    let libraryLocation = makeLibraryLocation()
    let legacyRepository = LibraryRepository(libraryLocation: libraryLocation)
    let legacyNote = makeDailyNote(
      year: 2026,
      month: 5,
      day: 20,
      title: "Legacy source",
      tags: ["copy"],
      body: "First\n<!-- section heading:blue -->\nSecond"
    )
    try legacyRepository.saveDailyNote(legacyNote)
    let sourceURL = libraryLocation.legacyNotesDirectoryURL
      .appendingPathComponent(legacyNote.fileName)
    let sourceData = try Data(contentsOf: sourceURL)

    let firstStore = makeStore(
      userDefaults: userDefaults,
      libraryLocation: libraryLocation
    )
    firstStore.loadIfNeeded()
    firstStore.copyLegacyDailyNotesToStructuredLibrary()
    firstStore.updateDailyNoteStorageMode(.structuredExperimental)
    let firstDocument = try XCTUnwrap(firstStore.structuredNotes.first)
    let firstSectionIDs = sectionIDs(in: firstDocument)
    let structuredData = try Data(
      contentsOf: firstStore.structuredNoteRepository.fileURL(for: firstDocument.id)
    )

    let relaunchedStore = makeStore(
      userDefaults: userDefaults,
      libraryLocation: libraryLocation
    )
    relaunchedStore.loadIfNeeded()
    let relaunchedDocument = try XCTUnwrap(relaunchedStore.structuredNotes.first)

    XCTAssertEqual(relaunchedStore.dailyNoteStorageMode, .structuredExperimental)
    XCTAssertEqual(relaunchedStore.selectedStructuredNoteID, legacyNote.id)
    XCTAssertEqual(relaunchedDocument.title, legacyNote.title)
    XCTAssertEqual(sectionIDs(in: relaunchedDocument), firstSectionIDs)
    XCTAssertEqual(try Data(contentsOf: sourceURL), sourceData)
    XCTAssertEqual(
      try Data(
        contentsOf: relaunchedStore.structuredNoteRepository.fileURL(
          for: relaunchedDocument.id
        )
      ),
      structuredData
    )
  }

  // Retains independent selection and search state without rewriting either library on toggles.
  func testModeTogglesPreserveIndependentStateAndFileContents() throws {
    let userDefaults = makeUserDefaults()
    let libraryLocation = makeLibraryLocation()
    let legacyRepository = LibraryRepository(libraryLocation: libraryLocation)
    let structuredRepository = StructuredNoteRepository(libraryLocation: libraryLocation)
    let newerLegacyNote = makeDailyNote(year: 2026, month: 5, day: 22, title: "Newer")
    let olderLegacyNote = makeDailyNote(year: 2026, month: 5, day: 21, title: "Older")
    try legacyRepository.saveDailyNote(newerLegacyNote)
    try legacyRepository.saveDailyNote(olderLegacyNote)
    let structuredDocument = StructuredNoteDocument(
      id: newerLegacyNote.id,
      date: newerLegacyNote.date,
      title: "Structured copy",
      tags: ["v2"],
      nodes: [.section(StructuredNoteSection(markdown: "Structured body"))]
    )
    try structuredRepository.save(structuredDocument)
    let legacyURL = libraryLocation.legacyNotesDirectoryURL
      .appendingPathComponent(newerLegacyNote.fileName)
    let structuredURL = structuredRepository.fileURL(for: structuredDocument.id)
    let legacyData = try Data(contentsOf: legacyURL)
    let structuredData = try Data(contentsOf: structuredURL)
    let store = makeStore(userDefaults: userDefaults, libraryLocation: libraryLocation)
    store.loadIfNeeded()
    store.selectedNoteID = olderLegacyNote.id
    store.searchText = "legacy query"

    store.updateDailyNoteStorageMode(.structuredExperimental)
    store.selectStructuredNote(structuredDocument.id)
    store.activeSearchTextBinding.wrappedValue = "structured query"

    XCTAssertEqual(store.activeDailySelectedNoteID, structuredDocument.id)
    XCTAssertEqual(store.activeDailySearchText, "structured query")
    XCTAssertNil(store.activeNote)

    store.updateDailyNoteStorageMode(.legacyMarkdown)

    XCTAssertEqual(store.activeDailySelectedNoteID, olderLegacyNote.id)
    XCTAssertEqual(store.activeDailySearchText, "legacy query")
    XCTAssertEqual(store.activeNote?.id, olderLegacyNote.id)

    store.updateDailyNoteStorageMode(.structuredExperimental)

    XCTAssertEqual(store.activeDailySelectedNoteID, structuredDocument.id)
    XCTAssertEqual(store.activeDailySearchText, "structured query")
    XCTAssertEqual(try Data(contentsOf: legacyURL), legacyData)
    XCTAssertEqual(try Data(contentsOf: structuredURL), structuredData)
  }

  // Keeps list-note routing on the existing list store while structured daily mode is enabled.
  func testListModeRemainsIndependentFromStructuredDailyMode() {
    let userDefaults = makeUserDefaults()
    SettingsRepository(userDefaults: userDefaults).saveDailyNoteStorageMode(
      .structuredExperimental
    )
    let listNote = makeListNote(
      id: "2026-05-23-list",
      year: 2026,
      month: 5,
      day: 23,
      title: "List note"
    )
    let store = makeStore(userDefaults: userDefaults)
    store.listNotes = [listNote]
    store.rebuildListNoteIndex()
    store.sidebarMode = .list
    store.selectedListNoteID = listNote.id

    XCTAssertFalse(store.isStructuredDailyModeActive)
    XCTAssertEqual(store.activeSelectedNoteID, listNote.id)
    XCTAssertEqual(store.activeNote, listNote)
  }

  // Blocks legacy-only transfer and backup paths from producing incomplete structured results.
  func testStructuredModeGuardsLegacyTransferAndBackupActions() {
    let userDefaults = makeUserDefaults()
    SettingsRepository(userDefaults: userDefaults).saveDailyNoteStorageMode(
      .structuredExperimental
    )
    let store = makeStore(userDefaults: userDefaults)

    store.runBackupNow()
    XCTAssertTrue(store.userMessage?.text.contains("Stage 10") == true)

    store.importFromMarkdown()
    XCTAssertTrue(store.userMessage?.text.contains("Legacy Markdown") == true)

    store.restoreFullLibraryFromArchive()
    XCTAssertTrue(store.userMessage?.text.contains("Stage 10") == true)
  }

  // Collects stable section IDs from root and grouped structured nodes.
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
}
