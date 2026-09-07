import Foundation
import XCTest

@testable import Sceal

@MainActor
final class NotesStoreStructuredModeTests: NotesStoreTestCase {
  // Launches directly into an empty structured library without creating retained Markdown storage.
  func testStructuredLaunchDoesNotCreateOrWriteLegacyNotesDirectory() {
    let userDefaults = makeUserDefaults()
    let libraryLocation = makeLibraryLocation()
    let store = makeStore(userDefaults: userDefaults, libraryLocation: libraryLocation)

    store.loadIfNeeded()

    XCTAssertTrue(
      FileManager.default.fileExists(atPath: store.structuredDailyNotesStorageURL.path)
    )
    XCTAssertFalse(FileManager.default.fileExists(atPath: store.legacyDailyNotesStorageURL.path))
    XCTAssertTrue(store.notes.isEmpty)
    XCTAssertTrue(store.structuredNotes.isEmpty)
  }

  // Creates complete archive snapshots with structured authority.
  func testStructuredModePreparesCompleteLosslessLibrarySnapshot() throws {
    let userDefaults = makeUserDefaults()
    let store = makeStore(
      userDefaults: userDefaults,
      libraryLocation: makeLibraryLocation()
    )

    let snapshot = try store.makeLibrarySnapshot()

    XCTAssertEqual(snapshot.settings.dailyNoteStorageModeRawValue, "structuredExperimental")
    XCTAssertTrue(snapshot.structuredDailyNotes.isEmpty)
    XCTAssertTrue(snapshot.structuredListNotes.isEmpty)
    XCTAssertEqual(snapshot.structuredListManifest, .empty)
  }

  // Creates and immediately persists a valid blank structured note for an empty day.
  func testOpenStructuredDailyDateCreatesPersistedBlankDocument() throws {
    let userDefaults = makeUserDefaults()
    let libraryLocation = makeLibraryLocation()
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

  // Persists complete structural snapshots with order, IDs, content, and appearance intact.
  func testStructuredSnapshotReplacementSavesExactDocument() throws {
    let userDefaults = makeUserDefaults()
    let libraryLocation = makeLibraryLocation()
    let firstSection = StructuredNoteSection(markdown: "AlphaBeta")
    let secondSection = StructuredNoteSection(markdown: "Second")
    let originalDocument = StructuredNoteDocument(
      id: "2026-06-08",
      date: makeDate(year: 2026, month: 6, day: 8),
      title: "Structural save",
      tags: ["v2"],
      nodes: [.section(firstSection), .section(secondSection)]
    )
    let repository = StructuredNoteRepository(libraryLocation: libraryLocation)
    try repository.save(originalDocument)
    let store = makeStore(userDefaults: userDefaults, libraryLocation: libraryLocation)
    store.loadIfNeeded()
    var updatedDocument = try XCTUnwrap(store.selectedStructuredNote)

    let splitSectionID = try updatedDocument.splitSection(
      id: firstSection.id,
      atUTF16Offset: 5
    )
    try updatedDocument.setStyleOverrides(
      StructuredSectionStyleOverrides(
        backgroundColor: .colorName("purple"),
        headingColor: .themeDefault
      ),
      sectionID: splitSectionID
    )
    try updatedDocument.moveRootNode(id: splitSectionID, to: 2)

    store.replaceStructuredDocument(updatedDocument)
    store.flushPendingSaves()

    XCTAssertEqual(
      try StructuredNoteDocumentCodec.read(from: repository.fileURL(for: updatedDocument.id)),
      updatedDocument
    )
  }

  // Persists a complete group lifecycle snapshot with inherited and overridden appearance intact.
  func testStructuredGroupLifecycleSavesAndReloadsExactDocument() throws {
    let userDefaults = makeUserDefaults()
    let libraryLocation = makeLibraryLocation()
    let firstSection = StructuredNoteSection(markdown: "Alpha")
    let secondSection = StructuredNoteSection(markdown: "Beta")
    let originalDocument = StructuredNoteDocument(
      id: "2026-06-09",
      date: makeDate(year: 2026, month: 6, day: 9),
      title: "Group lifecycle",
      tags: ["v2"],
      nodes: [.section(firstSection), .section(secondSection)]
    )
    let repository = StructuredNoteRepository(libraryLocation: libraryLocation)
    try repository.save(originalDocument)
    let store = makeStore(userDefaults: userDefaults, libraryLocation: libraryLocation)
    store.loadIfNeeded()
    var updatedDocument = try XCTUnwrap(store.selectedStructuredNote)

    let groupID = try updatedDocument.createGroup(
      title: "Draft",
      aroundSectionID: firstSection.id
    )
    try updatedDocument.setGroupTitle("Feature Group", groupID: groupID)
    try updatedDocument.setGroupStyle(
      StructuredSectionStyle(
        backgroundColorName: "grey",
        borderColorName: "blue",
        headingColorName: "purple",
        bulletColorName: "orange"
      ),
      groupID: groupID
    )
    try updatedDocument.moveSection(
      id: secondSection.id,
      to: StructuredNoteSectionDestination(parent: .group(groupID), index: 1)
    )
    try updatedDocument.setStyleOverrides(
      StructuredSectionStyleOverrides(
        borderColor: .colorName("pink"),
        headingColor: .themeDefault
      ),
      sectionID: secondSection.id
    )

    store.replaceStructuredDocument(updatedDocument)
    store.flushPendingSaves()

    let relaunchedStore = makeStore(
      userDefaults: userDefaults,
      libraryLocation: libraryLocation
    )
    relaunchedStore.loadIfNeeded()
    let reloadedDocument = try XCTUnwrap(relaunchedStore.selectedStructuredNote)
    XCTAssertEqual(reloadedDocument, updatedDocument)
    XCTAssertEqual(
      try StructuredNoteMarkdownExporter.body(for: reloadedDocument),
      "## Feature Group\n\nAlpha\n\nBeta"
    )
  }

  // Persists the exact result of root, group, cross-container, and detach drag paths.
  func testStructuredDragMutationsSaveAndReloadExactDocument() throws {
    let userDefaults = makeUserDefaults()
    let libraryLocation = makeLibraryLocation()
    let rootSection = StructuredNoteSection(markdown: "Root")
    let groupedSection = StructuredNoteSection(
      markdown: "Grouped",
      styleOverrides: StructuredSectionStyleOverrides(
        headingColor: .colorName("orange")
      )
    )
    let secondGroupedSection = StructuredNoteSection(markdown: "Second grouped")
    let trailingSection = StructuredNoteSection(markdown: "Trailing", isCollapsed: true)
    let group = StructuredSectionGroup(
      title: "Feature",
      style: StructuredSectionStyle(backgroundColorName: "grey"),
      sections: [groupedSection, secondGroupedSection]
    )
    let originalDocument = StructuredNoteDocument(
      id: "2026-06-13",
      date: makeDate(year: 2026, month: 6, day: 13),
      title: "Drag persistence",
      tags: ["v2"],
      nodes: [.section(rootSection), .group(group), .section(trailingSection)]
    )
    let repository = StructuredNoteRepository(libraryLocation: libraryLocation)
    try repository.save(originalDocument)
    let store = makeStore(userDefaults: userDefaults, libraryLocation: libraryLocation)
    store.loadIfNeeded()
    var updatedDocument = try XCTUnwrap(store.selectedStructuredNote)

    try StructuredNoteDragDrop.apply(
      .section(trailingSection.id),
      to: .group(groupID: group.id, insertionIndex: 1),
      in: &updatedDocument
    )
    try StructuredNoteDragDrop.apply(
      .section(groupedSection.id),
      to: .root(insertionIndex: 0),
      in: &updatedDocument
    )
    try StructuredNoteDragDrop.apply(
      .group(group.id),
      to: .root(insertionIndex: 0),
      in: &updatedDocument
    )

    store.replaceStructuredDocument(updatedDocument)
    store.flushPendingSaves()

    let relaunchedStore = makeStore(
      userDefaults: userDefaults,
      libraryLocation: libraryLocation
    )
    relaunchedStore.loadIfNeeded()

    XCTAssertEqual(relaunchedStore.selectedStructuredNote, updatedDocument)
    XCTAssertEqual(
      try StructuredNoteDocumentCodec.read(from: repository.fileURL(for: updatedDocument.id)),
      updatedDocument
    )
  }

  // Keeps collapsed content searchable and persists exact section/group state across relaunch.
  func testStructuredCollapseStateRemainsSearchableAndSurvivesRelaunch() throws {
    let userDefaults = makeUserDefaults()
    let libraryLocation = makeLibraryLocation()
    let rootSection = StructuredNoteSection(markdown: "Root content")
    let groupedSection = StructuredNoteSection(markdown: "Hidden needle content")
    let group = StructuredSectionGroup(title: "Feature", sections: [groupedSection])
    let originalDocument = StructuredNoteDocument(
      id: "2026-06-14",
      date: makeDate(year: 2026, month: 6, day: 14),
      title: "Collapse persistence",
      tags: ["v2"],
      nodes: [.section(rootSection), .group(group)]
    )
    let repository = StructuredNoteRepository(libraryLocation: libraryLocation)
    try repository.save(originalDocument)
    let store = makeStore(userDefaults: userDefaults, libraryLocation: libraryLocation)
    store.loadIfNeeded()
    var updatedDocument = try XCTUnwrap(store.selectedStructuredNote)

    try updatedDocument.setSectionCollapsed(true, sectionID: rootSection.id)
    try updatedDocument.setSectionCollapsed(true, sectionID: groupedSection.id)
    try updatedDocument.setGroupCollapsed(true, groupID: group.id)
    store.replaceStructuredDocument(updatedDocument)
    store.activeSearchTextBinding.wrappedValue = "needle"

    XCTAssertTrue(store.filteredDailyNoteIDs.contains(updatedDocument.id))
    store.flushPendingSaves()

    let relaunchedStore = makeStore(
      userDefaults: userDefaults,
      libraryLocation: libraryLocation
    )
    relaunchedStore.loadIfNeeded()
    relaunchedStore.activeSearchTextBinding.wrappedValue = "needle"

    XCTAssertEqual(relaunchedStore.selectedStructuredNote, updatedDocument)
    XCTAssertTrue(relaunchedStore.filteredDailyNoteIDs.contains(updatedDocument.id))
    XCTAssertEqual(
      try StructuredNoteDocumentCodec.read(from: repository.fileURL(for: updatedDocument.id)),
      updatedDocument
    )
  }

  // Flushes an edited structured document before navigation changes the active note.
  func testSelectingAnotherStructuredNoteFlushesPendingSave() throws {
    let userDefaults = makeUserDefaults()
    let libraryLocation = makeLibraryLocation()
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

  // Applies a custom template default as real sections when opening today's structured note.
  func testStructuredTodayCreationAppliesTemplateDefault() throws {
    let userDefaults = makeUserDefaults()
    let libraryLocation = makeLibraryLocation()
    let template = NoteTemplate(
      title: "Daily plan",
      command: "daily-plan",
      body: "# Plan\n\n- First\n<!-- section -->\n# Review",
      sectionColorName: "purple",
      createsNewSection: true
    )
    let store = makeStore(userDefaults: userDefaults, libraryLocation: libraryLocation)
    store.loadIfNeeded()
    try store.replaceNoteTemplates([template])
    store.updateNewNoteDefault(.template(template.id))

    store.selectToday()
    store.flushPendingSaves()

    let document = try XCTUnwrap(store.selectedStructuredNote)
    let sections = sectionIDs(in: document).compactMap { section(in: document, id: $0) }
    XCTAssertEqual(sections.map(\.markdown), ["# Plan\n\n- First", "# Review"])
    XCTAssertTrue(
      sections.allSatisfy { !$0.markdown.contains("<!-- section") }
    )
    XCTAssertEqual(sections[0].styleOverrides.borderColor, .colorName("purple"))
    XCTAssertEqual(
      try StructuredNoteDocumentCodec.read(
        from: store.structuredNoteRepository.fileURL(for: document.id)
      ),
      document
    )
  }

  // Copies the prior document's groups, styles, and attachments with fresh stable node IDs.
  func testStructuredCopyPreviousDefaultDuplicatesCompleteDocumentAndAttachments() throws {
    let userDefaults = makeUserDefaults()
    let libraryLocation = makeLibraryLocation()
    let store = makeStore(userDefaults: userDefaults, libraryLocation: libraryLocation)
    let previousDate = store.calendar.date(byAdding: .day, value: -1, to: Date.now)!
    let normalizedPreviousDate = store.calendar.startOfDay(for: previousDate)
    let previousID = NoteDateFormatters.storageDate.string(from: normalizedPreviousDate)
    let sourceSection = StructuredNoteSection(
      markdown: "![Desk](../Attachments/\(previousID)/desk.png)",
      styleOverrides: StructuredSectionStyleOverrides(borderColor: .colorName("orange")),
      isCollapsed: true
    )
    let sourceGroup = StructuredSectionGroup(
      title: "Feature",
      style: StructuredSectionStyle(headingColorName: "blue"),
      isCollapsed: true,
      sections: [sourceSection]
    )
    let sourceDocument = StructuredNoteDocument(
      id: previousID,
      date: normalizedPreviousDate,
      title: "Previous",
      tags: ["copy"],
      nodes: [.group(sourceGroup)]
    )
    try store.structuredNoteRepository.save(sourceDocument)
    let sourceAttachmentURL = store.libraryRepository.attachmentsRootURL
      .appendingPathComponent(previousID, isDirectory: true)
    try FileManager.default.createDirectory(
      at: sourceAttachmentURL,
      withIntermediateDirectories: true
    )
    try Data("image".utf8).write(to: sourceAttachmentURL.appendingPathComponent("desk.png"))
    store.loadIfNeeded()
    store.updateNewNoteDefault(.copyPrevious)

    store.selectToday()

    let copiedDocument = try XCTUnwrap(store.selectedStructuredNote)
    XCTAssertNotEqual(copiedDocument.id, sourceDocument.id)
    XCTAssertEqual(copiedDocument.title, sourceDocument.title)
    XCTAssertEqual(copiedDocument.tags, sourceDocument.tags)
    guard case .group(let copiedGroup) = copiedDocument.nodes.first else {
      return XCTFail("Expected the copied group.")
    }
    XCTAssertNotEqual(copiedGroup.id, sourceGroup.id)
    XCTAssertNotEqual(copiedGroup.sections[0].id, sourceSection.id)
    XCTAssertEqual(copiedGroup.style, sourceGroup.style)
    XCTAssertTrue(copiedGroup.isCollapsed)
    XCTAssertTrue(copiedGroup.sections[0].isCollapsed)
    XCTAssertTrue(copiedGroup.sections[0].markdown.contains(copiedDocument.id))
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: store.libraryRepository.attachmentsRootURL
          .appendingPathComponent(copiedDocument.id)
          .appendingPathComponent("desk.png").path
      )
    )
  }

  // Routes date changes through structured persistence while retaining the source attachment folder.
  func testStructuredDateChangeMovesDocumentAndCopiesAttachments() throws {
    let userDefaults = makeUserDefaults()
    let libraryLocation = makeLibraryLocation()
    let sourceDate = makeDate(year: 2026, month: 8, day: 1)
    let targetDate = makeDate(year: 2026, month: 8, day: 2)
    let sourceID = NoteDateFormatters.storageDate.string(from: sourceDate)
    let targetID = NoteDateFormatters.storageDate.string(from: targetDate)
    let sourceSection = StructuredNoteSection(
      markdown: "![Desk](../Attachments/\(sourceID)/desk.png)"
    )
    let document = StructuredNoteDocument(
      id: sourceID,
      date: sourceDate,
      title: "Move",
      tags: [],
      nodes: [.section(sourceSection)]
    )
    let repository = StructuredNoteRepository(libraryLocation: libraryLocation)
    try repository.save(document)
    let sourceAttachmentURL = libraryLocation.rootURL
      .appendingPathComponent("Attachments/\(sourceID)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: sourceAttachmentURL,
      withIntermediateDirectories: true
    )
    try Data("image".utf8).write(to: sourceAttachmentURL.appendingPathComponent("desk.png"))
    let store = makeStore(userDefaults: userDefaults, libraryLocation: libraryLocation)
    store.loadIfNeeded()

    store.changeDate(noteID: sourceID, to: targetDate)

    let movedDocument = try XCTUnwrap(store.selectedStructuredNote)
    XCTAssertEqual(movedDocument.id, targetID)
    XCTAssertEqual(sectionIDs(in: movedDocument), [sourceSection.id])
    XCTAssertFalse(FileManager.default.fileExists(atPath: repository.fileURL(for: sourceID).path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: repository.fileURL(for: targetID).path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: sourceAttachmentURL.path))
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: libraryLocation.rootURL
          .appendingPathComponent("Attachments/\(targetID)/desk.png").path
      )
    )
    XCTAssertEqual(
      section(in: movedDocument, id: sourceSection.id)?.markdown,
      "![Desk](../Attachments/\(targetID)/desk.png)"
    )
  }

  // Deletes only the structured document so a legacy note can retain its shared attachments.
  func testStructuredDeleteLeavesSharedAttachmentsUntouched() throws {
    let userDefaults = makeUserDefaults()
    let libraryLocation = makeLibraryLocation()
    let date = makeDate(year: 2026, month: 8, day: 3)
    let documentID = NoteDateFormatters.storageDate.string(from: date)
    let document = StructuredNoteDocument.empty(id: documentID, date: date)
    let repository = StructuredNoteRepository(libraryLocation: libraryLocation)
    try repository.save(document)
    let attachmentURL = libraryLocation.rootURL
      .appendingPathComponent("Attachments/\(documentID)/desk.png")
    try FileManager.default.createDirectory(
      at: attachmentURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data("image".utf8).write(to: attachmentURL)
    let store = makeStore(userDefaults: userDefaults, libraryLocation: libraryLocation)
    store.loadIfNeeded()

    store.delete(noteID: documentID)

    XCTAssertTrue(store.structuredNotes.isEmpty)
    XCTAssertNil(store.selectedStructuredNoteID)
    XCTAssertFalse(FileManager.default.fileExists(atPath: repository.fileURL(for: documentID).path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: attachmentURL.path))
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
