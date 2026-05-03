#if DEBUG
  import XCTest

  @testable import Sceal

  @MainActor
  final class NotesStoreDemoModeTests: NotesStoreTestCase {
    // Keeps the demo library anchored to exactly four recent daily notes.
    func testDemoModeNotesUseTodayThroughPreviousThreeDays() {
      let referenceDate = makeDate(year: 2026, month: 4, day: 4)
      let notes = DayNote.demoModeNotes(
        relativeTo: referenceDate,
        calendar: Calendar(identifier: .gregorian)
      )

      XCTAssertEqual(notes.map(\.id), ["2026-04-04", "2026-04-03", "2026-04-02", "2026-04-01"])
    }

    // Enabling demo mode switches to the in-memory daily samples without replacing real notes.
    func testEnablingDemoModeSelectsTodayAndPreservesRealNotes() {
      let realNote = makeDailyNote(year: 2026, month: 3, day: 20, title: "Real")
      let listNote = makeListNote(id: "2026-03-20-aaaaaa", year: 2026, month: 3, day: 20)
      let store = makeStore(previewNotes: [realNote])
      store.listNotes = [listNote]
      store.rebuildListNoteIndex()

      store.setDemoModeEnabled(true, referenceDate: makeDate(year: 2026, month: 4, day: 4))

      XCTAssertTrue(store.isDemoModeEnabled)
      XCTAssertEqual(store.sidebarMode, .daily)
      XCTAssertEqual(store.activeSelectedNoteID, "2026-04-04")
      XCTAssertEqual(store.notes, [realNote])
      XCTAssertEqual(store.listNotes, [listNote])
    }

    // Demo edits should stay in memory and never mutate the file-backed daily note array.
    func testEditingDemoNoteOnlyUpdatesDemoNotes() {
      let realNote = makeDailyNote(year: 2026, month: 3, day: 20, title: "Real", body: "Real body")
      let store = makeStore(previewNotes: [realNote])
      store.setDemoModeEnabled(true, referenceDate: makeDate(year: 2026, month: 4, day: 4))

      store.bodyBinding(for: "2026-04-04").wrappedValue = "Edited demo body"

      XCTAssertEqual(store.note(withID: "2026-04-04")?.body, "Edited demo body")
      XCTAssertEqual(store.notes, [realNote])
    }

    // Disabling demo mode returns the user to the exact real-note navigation context.
    func testDisablingDemoModeRestoresPreviousNavigationState() {
      let realNote = makeDailyNote(year: 2026, month: 3, day: 20, title: "Real")
      let listNote = makeListNote(id: "2026-03-20-aaaaaa", year: 2026, month: 3, day: 20)
      let store = makeStore(previewNotes: [realNote])
      store.listNotes = [listNote]
      store.rebuildListNoteIndex()
      store.selectedNoteID = realNote.id
      store.selectedListNoteID = listNote.id
      store.sidebarMode = .list
      store.searchText = "daily query"
      store.isSearchBarExpanded = true
      store.listSearchText = "list query"
      store.isListSearchBarExpanded = true
      store.calendarBrowseYear = 2025

      store.setDemoModeEnabled(true, referenceDate: makeDate(year: 2026, month: 4, day: 4))
      store.setDemoModeEnabled(false)

      XCTAssertFalse(store.isDemoModeEnabled)
      XCTAssertEqual(store.sidebarMode, .list)
      XCTAssertEqual(store.selectedNoteID, realNote.id)
      XCTAssertEqual(store.selectedListNoteID, listNote.id)
      XCTAssertEqual(store.searchText, "daily query")
      XCTAssertTrue(store.isSearchBarExpanded)
      XCTAssertEqual(store.listSearchText, "list query")
      XCTAssertTrue(store.isListSearchBarExpanded)
      XCTAssertEqual(store.calendarBrowseYear, 2025)
    }

    // Re-enabling demo mode rebuilds canonical samples and discards old in-memory edits.
    func testReenablingDemoModeResetsDemoContent() {
      let store = makeStore(previewNotes: [makeDailyNote(year: 2026, month: 3, day: 20)])
      let referenceDate = makeDate(year: 2026, month: 4, day: 4)

      store.setDemoModeEnabled(true, referenceDate: referenceDate)
      let canonicalBody = store.note(withID: "2026-04-04")?.body
      store.bodyBinding(for: "2026-04-04").wrappedValue = "Edited demo body"
      store.setDemoModeEnabled(false)

      store.setDemoModeEnabled(true, referenceDate: referenceDate)

      XCTAssertEqual(store.note(withID: "2026-04-04")?.body, canonicalBody)
    }

    // Demo mode blocks list mode so the sidebar cannot route into real list notes accidentally.
    func testDemoModeKeepsListModeUnavailable() {
      let store = makeStore(previewNotes: [makeDailyNote(year: 2026, month: 3, day: 20)])
      store.setDemoModeEnabled(true, referenceDate: makeDate(year: 2026, month: 4, day: 4))

      store.sidebarMode = .list

      XCTAssertEqual(store.sidebarMode, .daily)
      XCTAssertFalse(store.isListModeAvailable)
    }

    // Developer settings should only be present in DEBUG builds.
    func testDeveloperSettingsSectionIsAvailableInDebug() {
      XCTAssertTrue(SettingsSection.allCases.contains(.developer))
    }
  }
#endif
