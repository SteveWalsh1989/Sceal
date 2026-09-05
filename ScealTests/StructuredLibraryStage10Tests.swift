//
//  StructuredLibraryStage10Tests.swift
//

import Foundation
import XCTest

@testable import Sceal

@MainActor
final class StructuredLibraryStage10Tests: NotesStoreTestCase {
  func testStructuredListNoteCrudGroupsAndContentSurviveRelaunch() throws {
    let location = makeLibraryLocation()
    let defaults = makeUserDefaults()
    let store = makeStore(userDefaults: defaults, libraryLocation: location)
    store.updateDailyNoteStorageMode(.structuredExperimental)
    store.sidebarMode = .list
    try store.loadStructuredListNotesIfNeeded()

    store.createListNote()
    let noteID = try XCTUnwrap(store.selectedStructuredListNoteID)
    let sectionID = try XCTUnwrap(store.selectedStructuredListNote?.nodes.first?.id)
    store.structuredTitleBinding(for: noteID).wrappedValue = "Structured list"
    store.structuredSectionMarkdownBinding(
      documentID: noteID,
      sectionID: sectionID
    ).wrappedValue = "- [ ] Persist this"
    store.createGroup(name: "Plans")
    let groupID = try XCTUnwrap(store.structuredListNoteManifest.groups.first?.id)
    store.moveNoteToGroup(noteID: noteID, groupID: groupID)
    store.flushAllPendingStructuredNoteSaves()

    let relaunchedStore = makeStore(
      userDefaults: defaults,
      libraryLocation: location
    )
    relaunchedStore.sidebarMode = .list
    try relaunchedStore.loadStructuredListNotesIfNeeded()

    XCTAssertEqual(relaunchedStore.dailyNoteStorageMode, .structuredExperimental)
    XCTAssertEqual(relaunchedStore.selectedStructuredListNote?.title, "Structured list")
    let relaunchedNode = try XCTUnwrap(relaunchedStore.selectedStructuredListNote?.nodes.first)
    guard case .section(let relaunchedSection) = relaunchedNode else {
      return XCTFail("Expected the structured list note to retain its root section.")
    }
    XCTAssertEqual(relaunchedSection.markdown, "- [ ] Persist this")
    XCTAssertEqual(relaunchedStore.structuredListNoteManifest.groups.first?.name, "Plans")
    XCTAssertEqual(relaunchedStore.structuredListNoteManifest.groups.first?.noteIDs, [noteID])

    relaunchedStore.deleteListNote(noteID: noteID)
    XCTAssertTrue(
      try StructuredNoteRepository.listNotes(libraryLocation: location).loadDocuments().isEmpty
    )
    XCTAssertFalse(relaunchedStore.structuredListNoteManifest.allNoteIDs.contains(noteID))
  }

  func testMatchingDailyAndListIDsRemainIsolatedAcrossDebouncedSaves() throws {
    let location = makeLibraryLocation()
    let date = makeDate(year: 2026, month: 9, day: 2)
    let sharedID = "2026-09-02"
    let dailyRepository = StructuredNoteRepository(libraryLocation: location)
    let listRepository = StructuredNoteRepository.listNotes(libraryLocation: location)
    try dailyRepository.save(.empty(id: sharedID, date: date))
    try listRepository.save(.empty(id: sharedID, date: date))
    try LibraryRepository(libraryLocation: location).saveStructuredListNotesManifest(
      ListNotesManifest(ungroupedNoteIDs: [sharedID], groups: [])
    )

    let store = makeStore(userDefaults: makeUserDefaults(), libraryLocation: location)
    store.updateDailyNoteStorageMode(.structuredExperimental)
    try store.loadStructuredDailyNotesIfNeeded()
    try store.loadStructuredListNotesIfNeeded()

    store.sidebarMode = .daily
    store.structuredTitleBinding(for: sharedID).wrappedValue = "Daily title"
    store.sidebarMode = .list
    store.structuredTitleBinding(for: sharedID).wrappedValue = "List title"
    store.flushAllPendingStructuredNoteSaves()

    XCTAssertEqual(try dailyRepository.loadDocuments().first?.title, "Daily title")
    XCTAssertEqual(try listRepository.loadDocuments().first?.title, "List title")
  }

  func testFullLibraryUpgradeWritesSafetyArchiveReportAndLeavesLegacySourcesUnchanged() throws {
    let location = makeLibraryLocation()
    let repository = LibraryRepository(libraryLocation: location)
    let dailyNote = makeDailyNote(
      year: 2026,
      month: 9,
      day: 1,
      title: "Daily",
      body: "# Focus\n\n- preserve this\n<!-- section:blue -->\n## Next\n\nDetails"
    )
    let listNote = makeListNote(
      id: "project-plan",
      year: 2026,
      month: 8,
      day: 30,
      title: "Project plan",
      body: "## Tasks\n\n- [ ] Archive"
    )
    let listManifest = ListNotesManifest(
      ungroupedNoteIDs: [],
      groups: [NoteGroup(name: "Projects", noteIDs: [listNote.id], isCollapsed: true)]
    )
    try repository.saveDailyNote(dailyNote)
    try repository.saveListNote(listNote)
    try repository.saveListNotesManifest(listManifest)
    let attachmentDirectoryURL = repository.attachmentsRootURL.appendingPathComponent(
      dailyNote.id,
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: attachmentDirectoryURL,
      withIntermediateDirectories: true
    )
    try Data("image".utf8).write(
      to: attachmentDirectoryURL.appendingPathComponent("image.png")
    )

    let dailySourceURL = location.legacyNotesDirectoryURL.appendingPathComponent(dailyNote.fileName)
    let listSourceURL = location.rootURL
      .appendingPathComponent(ScealLibraryLocation.listNotesFolderName, isDirectory: true)
      .appendingPathComponent(listNote.fileName)
    let manifestSourceURL = listSourceURL.deletingLastPathComponent()
      .appendingPathComponent("groups.json")
    let sourceData = try [dailySourceURL, listSourceURL, manifestSourceURL].map {
      try Data(contentsOf: $0)
    }
    let store = makeStore(userDefaults: makeUserDefaults(), libraryLocation: location)

    store.upgradeFullLibraryToStructured()

    XCTAssertEqual(store.dailyNoteStorageMode, .legacyMarkdown)
    XCTAssertEqual(
      try [dailySourceURL, listSourceURL, manifestSourceURL].map {
        try Data(contentsOf: $0)
      },
      sourceData
    )
    XCTAssertEqual(
      try StructuredNoteRepository(libraryLocation: location).loadDocuments().map(\.id),
      [dailyNote.id]
    )
    XCTAssertEqual(
      Set(
        try StructuredNoteRepository.listNotes(libraryLocation: location).loadDocuments().map(\.id)),
      [listNote.id]
    )
    XCTAssertEqual(
      try repository.loadStructuredListNotesManifestForArchive(noteIDs: [listNote.id]),
      listManifest
    )

    let safetyArchives = try FileManager.default.contentsOfDirectory(
      at: location.restoreSafetyArchiveDirectoryURL(),
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    ).filter { $0.pathExtension == "zip" }
    XCTAssertEqual(safetyArchives.count, 1)

    let reportURLs = try FileManager.default.contentsOfDirectory(
      at: location.migrationReportsDirectoryURL(),
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    ).filter { $0.pathExtension == "json" }
    let reportURL = try XCTUnwrap(reportURLs.first)
    let report = try JSONDecoder().decode(
      StructuredLibraryMigrationReport.self,
      from: Data(contentsOf: reportURL)
    )
    XCTAssertTrue(report.passedContentValidation)
    XCTAssertTrue(report.legacyLibraryPreserved)
    XCTAssertEqual(report.matchingDailyNoteCount, 1)
    XCTAssertEqual(report.matchingListNoteCount, 1)
    XCTAssertEqual(report.attachmentFolderCount, 1)
    XCTAssertEqual(report.attachmentFileCount, 1)

    var customizedManifest = try repository.loadStructuredListNotesManifestForArchive(
      noteIDs: [listNote.id]
    )
    customizedManifest.groups[0].name = "Custom structured group"
    try repository.saveStructuredListNotesManifest(customizedManifest)

    store.upgradeFullLibraryToStructured()

    XCTAssertEqual(
      try repository.loadStructuredListNotesManifestForArchive(noteIDs: [listNote.id]),
      customizedManifest
    )
    XCTAssertEqual(
      try FileManager.default.contentsOfDirectory(
        at: location.restoreSafetyArchiveDirectoryURL(),
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      ).filter { $0.pathExtension == "zip" }.count,
      2
    )
    XCTAssertEqual(
      try FileManager.default.contentsOfDirectory(
        at: location.migrationReportsDirectoryURL(),
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      ).filter { $0.pathExtension == "json" }.count,
      2
    )
  }

  // Treats Markdown whitespace as content so migration validation cannot hide hard line breaks.
  func testMigrationReportRejectsTrailingWhitespaceDifferences() throws {
    let location = makeLibraryLocation()
    let date = makeDate(year: 2026, month: 9, day: 2)
    let source = StructuredNoteDocument(
      id: "2026-09-02",
      date: date,
      title: "Exact",
      tags: [],
      nodes: [.section(StructuredNoteSection(markdown: "Line  \n"))]
    )
    let target = StructuredNoteDocument(
      id: source.id,
      date: date,
      title: source.title,
      tags: source.tags,
      nodes: [.section(StructuredNoteSection(markdown: "Line\n"))]
    )
    let store = makeStore(userDefaults: makeUserDefaults(), libraryLocation: location)

    let report = try StructuredLibraryMigrationReporter.makeReport(
      createdAt: .now,
      safetyArchiveURL: location.rootURL.appendingPathComponent("safety.zip"),
      sourceDailyDocuments: [source],
      sourceListDocuments: [],
      sourceListManifest: .empty,
      structuredDailyDocuments: [target],
      structuredListDocuments: [],
      structuredListManifest: .empty,
      attachmentsRootURL: location.rootURL.appendingPathComponent("Attachments"),
      templates: [],
      settings: try store.makeArchiveSettings(),
      legacyLibraryPreserved: true
    )

    XCTAssertFalse(report.passedContentValidation)
    XCTAssertEqual(report.mismatchedDailyNoteIDs, [source.id])
  }

  func testVersionTwoArchiveRestoresExactStructuredDocumentsSettingsAndAttachments() throws {
    let sourceLocation = makeLibraryLocation()
    var customColors = AppTheme.defaultLight.colors
    customColors.noteBodyBorder = ThemeColor(red: 0.2, green: 0.4, blue: 0.6)
    let archivedAppearance = NoteAppearanceSettings(
      bodyFontSize: 18,
      themeID: AppTheme.defaultLight.id,
      colorOverrides: customColors
    )
    let settings = ScealArchiveSettings(
      appearanceSettingsData: try JSONEncoder().encode(archivedAppearance),
      continuousSpellCheckingEnabled: false,
      newNoteDefaultRawValue: NewNoteDefault.copyPrevious.rawValue,
      dailyNoteStorageModeRawValue: DailyNoteStorageMode.structuredExperimental.rawValue,
      backupScheduleRawValue: BackupSchedule.weekly.rawValue,
      backupOnInactive: false,
      themeID: archivedAppearance.themeID,
      includesCustomThemeColors: true,
      layoutSettings: ScealArchiveLayoutSettings(
        settingsSidebarWidth: 210,
        templatesListWidth: 230,
        templatesListCollapsed: true
      )
    )
    let dailyDate = makeDate(year: 2026, month: 9, day: 2)
    let dailyDocument = StructuredNoteDocument(
      id: "2026-09-02",
      date: dailyDate,
      title: "Structured daily",
      tags: ["archive"],
      nodes: [
        .group(
          StructuredSectionGroup(
            title: "Feature",
            style: StructuredSectionStyle(borderColorName: "teal"),
            isCollapsed: true,
            sections: [
              StructuredNoteSection(
                markdown: "## Exact\n\n- content",
                styleOverrides: StructuredSectionStyleOverrides(
                  primaryColor: .colorName("pink"),
                  headingFollowsPrimaryColor: true,
                  borderFollowsPrimaryColor: true,
                  bulletFollowsPrimaryColor: true
                ),
                isCollapsed: true
              )
            ]
          )
        )
      ]
    )
    let listDocument = StructuredNoteDocument(
      id: "release-plan",
      date: makeDate(year: 2026, month: 9, day: 1),
      title: "Release plan",
      tags: ["list"],
      nodes: [.section(StructuredNoteSection(markdown: "- [ ] Ship"))]
    )
    let structuredManifest = ListNotesManifest(
      ungroupedNoteIDs: [],
      groups: [NoteGroup(name: "Releases", noteIDs: [listDocument.id], isCollapsed: true)]
    )
    let legacyDaily = makeDailyNote(
      year: 2026,
      month: 8,
      day: 31,
      title: "Legacy daily",
      body: "Legacy body"
    )
    let legacyList = makeListNote(
      id: "legacy-list",
      year: 2026,
      month: 8,
      day: 30,
      title: "Legacy list",
      body: "Legacy list body"
    )
    let legacyManifest = ListNotesManifest(
      ungroupedNoteIDs: [legacyList.id],
      groups: []
    )
    let attachmentsRootURL = sourceLocation.rootURL.appendingPathComponent(
      NoteImageAttachmentStore.attachmentsFolderName,
      isDirectory: true
    )
    let attachmentDirectoryURL = attachmentsRootURL.appendingPathComponent(
      listDocument.id,
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: attachmentDirectoryURL,
      withIntermediateDirectories: true
    )
    try Data("attachment".utf8).write(
      to: attachmentDirectoryURL.appendingPathComponent("plan.png")
    )
    let template = NoteTemplate(
      id: "custom-release",
      title: "Release checklist",
      command: "release",
      menuDescription: "Insert the release prompt",
      body: "## Release\n\n- [ ] Verify",
      cursorPlacement: .end,
      sectionColorName: "teal",
      createsNewSection: true
    )
    let archiveURL = try ScealBackupArchiveExporter.exportBackup(
      dailyNotes: [legacyDaily],
      listNotes: [legacyList],
      manifest: legacyManifest,
      templates: [template],
      structuredDailyNotes: [dailyDocument],
      structuredListNotes: [listDocument],
      structuredListManifest: structuredManifest,
      settings: settings,
      authority: .structured,
      kind: .manual,
      createdAt: dailyDate,
      attachmentsRootURL: attachmentsRootURL
    )
    defer { ZipArchiveWriter.cleanUp(zipURL: archiveURL) }

    let destinationLocation = makeLibraryLocation()
    let destinationRepository = LibraryRepository(libraryLocation: destinationLocation)
    let result = try ScealBackupArchiveImporter.restoreLibrary(
      from: archiveURL,
      currentDailyNotes: [],
      currentListNotes: [],
      currentManifest: .empty,
      currentSettings: settings,
      destinationURLs: destinationRepository.storageURLs(),
      safetyArchiveDirectoryURL: destinationLocation.restoreSafetyArchiveDirectoryURL()
    )

    XCTAssertEqual(result.metadata.backupFormatVersion, 2)
    XCTAssertEqual(result.metadata.structuredStorageIsAuthoritative, true)
    XCTAssertTrue(result.dailyNotes.isEmpty)
    XCTAssertTrue(result.listNotes.isEmpty)
    XCTAssertEqual(result.manifest, .empty)
    XCTAssertEqual(
      try Data(contentsOf: result.retainedArchiveURL), try Data(contentsOf: archiveURL))
    XCTAssertEqual(result.structuredDailyNotes, [dailyDocument])
    XCTAssertEqual(result.structuredListNotes, [listDocument])
    XCTAssertEqual(result.structuredListManifest, structuredManifest)
    XCTAssertEqual(result.templates, [template])
    XCTAssertEqual(result.settings, settings)
    XCTAssertEqual(
      try StructuredNoteRepository(libraryLocation: destinationLocation).loadDocuments(),
      [dailyDocument]
    )
    XCTAssertEqual(
      try StructuredNoteRepository.listNotes(libraryLocation: destinationLocation).loadDocuments(),
      [listDocument]
    )
    XCTAssertEqual(
      try destinationRepository.loadStructuredListNotesManifestForArchive(
        noteIDs: [listDocument.id]
      ),
      structuredManifest
    )
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: destinationRepository.attachmentsRootURL
          .appendingPathComponent("\(listDocument.id)/plan.png").path
      )
    )
  }

  func testArchiveSettingsRestorePreservesMachineSpecificBackupPermission() throws {
    let defaults = makeUserDefaults()
    let store = makeStore(userDefaults: defaults)
    let bookmark = Data("machine-bookmark".utf8)
    store.backupSettingsStore.configureFolder(
      bookmarkData: bookmark,
      displayPath: "/Volumes/Backups"
    )
    let appearance = NoteAppearanceSettings(
      bodyFontSize: 18,
      themeID: "default-light"
    )
    let settings = ScealArchiveSettings(
      appearanceSettingsData: try JSONEncoder().encode(appearance),
      continuousSpellCheckingEnabled: false,
      newNoteDefaultRawValue: NewNoteDefault.copyPrevious.rawValue,
      dailyNoteStorageModeRawValue: DailyNoteStorageMode.structuredExperimental.rawValue,
      backupScheduleRawValue: BackupSchedule.weekly.rawValue,
      backupOnInactive: false,
      themeID: appearance.themeID,
      includesCustomThemeColors: false,
      layoutSettings: ScealArchiveLayoutSettings(
        settingsSidebarWidth: 205,
        templatesListWidth: 240,
        templatesListCollapsed: true
      )
    )

    try store.applyArchiveSettings(settings)

    XCTAssertEqual(store.appearanceSettings.bodyFontSize, 18)
    XCTAssertEqual(store.appearanceSettings.themeID, "default-light")
    XCTAssertFalse(store.continuousSpellCheckingEnabled)
    XCTAssertEqual(store.newNoteDefault, .copyPrevious)
    XCTAssertEqual(store.dailyNoteStorageMode, .structuredExperimental)
    XCTAssertEqual(store.backupSettings.schedule, .weekly)
    XCTAssertFalse(store.backupSettings.backupOnInactive)
    XCTAssertEqual(store.backupSettings.folderBookmarkData, bookmark)
    XCTAssertEqual(store.backupSettings.folderDisplayPath, "/Volumes/Backups")
    XCTAssertEqual(
      store.settingsRepository.loadArchiveLayoutSettings(),
      settings.layoutSettings
    )
  }

  func testArchiveSettingsRejectMalformedAppearanceBeforeRestore() throws {
    let settings = ScealArchiveSettings(
      appearanceSettingsData: Data("{}".utf8),
      continuousSpellCheckingEnabled: true,
      newNoteDefaultRawValue: NewNoteDefault.blank.rawValue,
      dailyNoteStorageModeRawValue: DailyNoteStorageMode.legacyMarkdown.rawValue,
      backupScheduleRawValue: BackupSchedule.manualOnly.rawValue,
      backupOnInactive: true,
      themeID: NoteAppearanceSettings.defaultThemeID,
      includesCustomThemeColors: false,
      layoutSettings: ScealArchiveLayoutSettings(
        settingsSidebarWidth: 180,
        templatesListWidth: 180,
        templatesListCollapsed: false
      )
    )

    XCTAssertThrowsError(try settings.validate()) { error in
      XCTAssertEqual(error as? ScealArchiveSettingsError, .invalidAppearanceSettings)
    }
  }

  func testArchiveSnapshotRejectsMalformedManifestEvenForAnEmptyListLibrary() throws {
    let location = makeLibraryLocation()
    let listNotesDirectoryURL = try location.listNotesDirectoryURL()
    try Data("not-json".utf8).write(
      to: listNotesDirectoryURL.appendingPathComponent("groups.json")
    )

    XCTAssertThrowsError(
      try LibraryRepository(libraryLocation: location).loadArchiveSourceSnapshot()
    ) { error in
      guard case .invalidLegacyManifest = error as? LibraryRepositoryError else {
        return XCTFail("Expected strict archive preparation to reject the manifest.")
      }
    }
  }
}
