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

  // Creates and immediately persists a valid blank structured note for an empty day.
  func testOpenStructuredDailyDateCreatesPersistedBlankDocument() throws {
    let userDefaults = makeUserDefaults()
    let libraryLocation = makeLibraryLocation()
    SettingsRepository(userDefaults: userDefaults).saveDailyNoteStorageMode(
      .structuredExperimental
    )
    let store = makeStore(userDefaults: userDefaults, libraryLocation: libraryLocation)
    let targetDate = makeDate(year: 2026, month: 6, day: 4)
    let expectedID = NoteDateFormatters.storageDate.string(
      from: store.calendar.startOfDay(for: targetDate)
    )

    store.loadIfNeeded()
    store.openDailyDate(targetDate)

    let document = try XCTUnwrap(store.selectedStructuredNote)
    XCTAssertEqual(document.id, expectedID)
    XCTAssertEqual(document.nodes.count, 1)
    XCTAssertEqual(sectionIDs(in: document).count, 1)
    XCTAssertEqual(section(in: document, id: sectionIDs(in: document)[0])?.markdown, "")
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: store.structuredNoteRepository.fileURL(for: expectedID).path
      )
    )
    XCTAssertFalse(FileManager.default.fileExists(atPath: store.legacyDailyNotesStorageURL.path))
  }

  // Persists title, normalized tags, and root/group section edits exactly across relaunch.
  func testStructuredEditorBindingsSaveAndReloadStableSections() throws {
    let userDefaults = makeUserDefaults()
    let libraryLocation = makeLibraryLocation()
    SettingsRepository(userDefaults: userDefaults).saveDailyNoteStorageMode(
      .structuredExperimental
    )
    let rootSection = StructuredNoteSection(markdown: "Original root")
    let groupedSection = StructuredNoteSection(markdown: "Original grouped")
    let group = StructuredSectionGroup(title: "Feature", sections: [groupedSection])
    let originalDocument = StructuredNoteDocument(
      id: "2026-06-05",
      date: makeDate(year: 2026, month: 6, day: 5),
      title: "Original title",
      tags: ["original"],
      nodes: [.section(rootSection), .group(group)]
    )
    try StructuredNoteRepository(libraryLocation: libraryLocation).save(originalDocument)
    let store = makeStore(userDefaults: userDefaults, libraryLocation: libraryLocation)
    store.loadIfNeeded()

    store.structuredTitleBinding(for: originalDocument.id).wrappedValue = "Edited title"
    store.structuredTagsBinding(for: originalDocument.id).wrappedValue =
      " planning, swift, planning "
    store.structuredSectionMarkdownBinding(
      documentID: originalDocument.id,
      sectionID: rootSection.id
    ).wrappedValue = "# Root\n- Edited item\n<!-- section -->\nLiteral marker"
    store.structuredSectionMarkdownBinding(
      documentID: originalDocument.id,
      sectionID: groupedSection.id
    ).wrappedValue = "```swift\nlet value = 2\n```"
    store.flushPendingSaves()

    let relaunchedStore = makeStore(
      userDefaults: userDefaults,
      libraryLocation: libraryLocation
    )
    relaunchedStore.loadIfNeeded()
    let reloadedDocument = try XCTUnwrap(relaunchedStore.selectedStructuredNote)

    XCTAssertEqual(reloadedDocument.title, "Edited title")
    XCTAssertEqual(reloadedDocument.tags, ["planning", "swift"])
    XCTAssertEqual(sectionIDs(in: reloadedDocument), [rootSection.id, groupedSection.id])
    XCTAssertEqual(
      section(in: reloadedDocument, id: rootSection.id)?.markdown,
      "# Root\n- Edited item\n<!-- section -->\nLiteral marker"
    )
    XCTAssertEqual(
      section(in: reloadedDocument, id: groupedSection.id)?.markdown,
      "```swift\nlet value = 2\n```"
    )
  }

  // Flushes an edited structured document before navigation changes the active note.
  func testSelectingAnotherStructuredNoteFlushesPendingSave() throws {
    let userDefaults = makeUserDefaults()
    let libraryLocation = makeLibraryLocation()
    SettingsRepository(userDefaults: userDefaults).saveDailyNoteStorageMode(
      .structuredExperimental
    )
    let firstDocument = StructuredNoteDocument.empty(
      id: "2026-06-06",
      date: makeDate(year: 2026, month: 6, day: 6)
    )
    let secondDocument = StructuredNoteDocument.empty(
      id: "2026-06-07",
      date: makeDate(year: 2026, month: 6, day: 7)
    )
    let repository = StructuredNoteRepository(libraryLocation: libraryLocation)
    try repository.save(firstDocument)
    try repository.save(secondDocument)
    let store = makeStore(userDefaults: userDefaults, libraryLocation: libraryLocation)
    store.loadIfNeeded()
    store.selectStructuredNote(firstDocument.id)

    store.structuredTitleBinding(for: firstDocument.id).wrappedValue = "Saved before navigation"
    store.selectStructuredNote(secondDocument.id)

    let savedDocument = try StructuredNoteDocumentCodec.read(
      from: repository.fileURL(for: firstDocument.id)
    )
    XCTAssertEqual(savedDocument.title, "Saved before navigation")
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

  // Finds a section fixture without assuming whether it is at the root or inside a group.
  private func section(
    in document: StructuredNoteDocument,
    id sectionID: UUID
  ) -> StructuredNoteSection? {
    for node in document.nodes {
      switch node {
      case .section(let section) where section.id == sectionID:
        return section
      case .group(let group):
        if let section = group.sections.first(where: { $0.id == sectionID }) {
          return section
        }
      default:
        continue
      }
    }
    return nil
  }
}
