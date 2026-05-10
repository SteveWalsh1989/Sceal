//
//  NotesStore.swift
//
//

// Central state store for notes, appearance settings, and persistence.

import AppKit
import Combine
import Foundation
import OSLog
import SwiftUI
import UniformTypeIdentifiers

struct NoteMonthSection: Identifiable, Equatable, Sendable {
  let monthStartDate: Date
  let notes: [DayNote]

  var id: String {
    NoteDateFormatters.storageDate.string(from: monthStartDate)
  }

  // Month header text, omitting the year for the current year.
  var title: String {
    let isCurrentYear =
      Calendar.current.component(.year, from: monthStartDate)
      == Calendar.current.component(.year, from: Date.now)
    let formatter =
      isCurrentYear
      ? NoteDateFormatters.monthDividerMonthOnly : NoteDateFormatters.monthDivider
    return formatter.string(from: monthStartDate).uppercased()
  }
}

enum UserMessageKind {
  case error
  case info
}

#if DEBUG
  private struct DemoReturnContext {
    let sidebarMode: SidebarMode
    let selectedNoteID: DayNote.ID?
    let selectedListNoteID: DayNote.ID?
    let searchText: String
    let isSearchBarExpanded: Bool
    let listSearchText: String
    let isListSearchBarExpanded: Bool
    let calendarBrowseYear: Int
  }
#endif

@MainActor
final class NotesStore: ObservableObject {
  @Published var sidebarMode: SidebarMode = .daily {
    didSet {
      #if DEBUG
        if isDemoModeEnabled, sidebarMode == .list {
          sidebarMode = .daily
          return
        }
      #endif
      guard oldValue != sidebarMode else { return }

      if sidebarMode == .list {
        clearSearch()
      }

      if oldValue == .list {
        listSearchText = ""
        isListSearchBarExpanded = false
      }

      if sidebarMode == .calendar {
        syncCalendarBrowseYearToSelectedNote()
      }
    }
  }
  @Published private(set) var isLoading = false
  @Published var userMessage: (text: String, kind: UserMessageKind)?
  @Published var isPerformingFileOperation = false
  @Published var progressMessage: String?
  @Published var backupHealth: BackupHealth
  @Published var isBackupRunning = false
  #if DEBUG
    @Published var isDemoModeEnabled = false
    @Published private(set) var demoNotes: [DayNote] = [] {
      didSet {
        guard isDemoModeEnabled else { return }
        cachedMonthSections = nil
        clampCalendarBrowseYear()
      }
    }
  #else
    var isDemoModeEnabled: Bool { false }
  #endif

  let fileManager: FileManager
  let calendar: Calendar
  let libraryLocation: ScealLibraryLocation
  let libraryRepository: LibraryRepository
  let settingsRepository: SettingsRepository
  let appearanceSettingsStore: AppearanceSettingsStore
  let backupSettingsStore: BackupSettingsStore
  let dailyNotesStore: DailyNotesStore
  let editorPreferencesStore: EditorPreferencesStore
  let planAccessStore: PlanAccessStore
  let listNotesStore: ListNotesStore
  let noteTemplatesStore: NoteTemplatesStore
  let archiveService: ArchiveService
  private var hasLoaded = false
  private var cachedMonthSections: [NoteMonthSection]?
  private var pendingSaveTasks: [DayNote.ID: Task<Void, Never>] = [:]
  var pendingListNoteSaveTasks: [DayNote.ID: Task<Void, Never>] = [:]
  private var periodicFlushTask: Task<Void, Never>?
  var periodicBackupCheckTask: Task<Void, Never>?
  #if DEBUG
    private var demoReturnContext: DemoReturnContext?
  #endif

  private static let logger = Logger(subsystem: "com.sceal.app", category: "store")

  init(
    fileManager: FileManager = .default,
    calendar: Calendar = .current,
    userDefaults: UserDefaults = .standard,
    libraryLocation: ScealLibraryLocation? = nil,
    previewNotes: [DayNote] = []
  ) {
    self.fileManager = fileManager
    self.calendar = calendar
    let resolvedSettingsRepository = SettingsRepository(userDefaults: userDefaults)
    self.settingsRepository = resolvedSettingsRepository
    self.appearanceSettingsStore = AppearanceSettingsStore(
      settingsRepository: resolvedSettingsRepository
    )
    let resolvedBackupSettingsStore = BackupSettingsStore(
      settingsRepository: resolvedSettingsRepository
    )
    self.backupSettingsStore = resolvedBackupSettingsStore
    self.editorPreferencesStore = EditorPreferencesStore(
      settingsRepository: resolvedSettingsRepository
    )
    self.planAccessStore = PlanAccessStore(settingsRepository: resolvedSettingsRepository)
    self.listNotesStore = ListNotesStore()
    self.noteTemplatesStore = NoteTemplatesStore(settingsRepository: resolvedSettingsRepository)
    self.archiveService = ArchiveService(fileManager: fileManager)
    let resolvedLibraryLocation =
      libraryLocation
      ?? ScealLibraryLocation.defaultForCurrentBuild(
        fileManager: fileManager
      )
    self.libraryLocation = resolvedLibraryLocation
    self.libraryRepository = LibraryRepository(
      libraryLocation: resolvedLibraryLocation,
      fileManager: fileManager
    )
    let sortedNotes = previewNotes.sorted(by: { $0.date > $1.date })
    let loadedBackupSettings = resolvedBackupSettingsStore.settings
    let currentYear = calendar.component(.year, from: .now)
    self.dailyNotesStore = DailyNotesStore(
      notes: sortedNotes,
      selectedNoteID: sortedNotes.first?.id,
      calendarBrowseYear: currentYear
    )
    self.backupHealth = loadedBackupSettings.isConfigured ? .healthy : .notConfigured
    self.hasLoaded = !previewNotes.isEmpty
  }

  var featureAccess: AppFeatureAccess {
    planAccessStore.featureAccess
  }

  var activePlan: AppPlan {
    planAccessStore.activePlan
  }

  var appearanceSettings: NoteAppearanceSettings {
    appearanceSettingsStore.settings
  }

  var noteTemplates: [NoteTemplate] {
    noteTemplatesStore.templates
  }

  var backupSettings: BackupSettings {
    backupSettingsStore.settings
  }

  var continuousSpellCheckingEnabled: Bool {
    editorPreferencesStore.continuousSpellCheckingEnabled
  }

  var newNoteDefault: NewNoteDefault {
    editorPreferencesStore.newNoteDefault
  }

  var notes: [DayNote] {
    get { dailyNotesStore.notes }
    set {
      objectWillChange.send()
      dailyNotesStore.replaceNotes(newValue)
      cachedMonthSections = nil
      clampCalendarBrowseYear()
    }
  }

  var selectedNoteID: DayNote.ID? {
    get { dailyNotesStore.selectedNoteID }
    set {
      objectWillChange.send()
      dailyNotesStore.selectNote(newValue)
      guard sidebarMode == .calendar else { return }
      syncCalendarBrowseYearToSelectedNote()
    }
  }

  var searchText: String {
    get { dailyNotesStore.searchText }
    set {
      objectWillChange.send()
      dailyNotesStore.updateSearchText(newValue)
      cachedMonthSections = nil
    }
  }

  var isSearchBarExpanded: Bool {
    get { dailyNotesStore.isSearchBarExpanded }
    set {
      objectWillChange.send()
      dailyNotesStore.updateSearchBarExpanded(newValue)
    }
  }

  var calendarBrowseYear: Int {
    get { dailyNotesStore.calendarBrowseYear }
    set {
      objectWillChange.send()
      dailyNotesStore.updateCalendarBrowseYear(newValue)
    }
  }

  var listNotes: [DayNote] {
    get { listNotesStore.notes }
    set {
      objectWillChange.send()
      listNotesStore.replaceNotes(newValue)
    }
  }

  var listNoteManifest: ListNotesManifest {
    get { listNotesStore.manifest }
    set {
      objectWillChange.send()
      listNotesStore.replaceManifest(newValue)
    }
  }

  var selectedListNoteID: DayNote.ID? {
    get { listNotesStore.selectedNoteID }
    set {
      objectWillChange.send()
      listNotesStore.selectNote(newValue)
    }
  }

  var listSearchText: String {
    get { listNotesStore.searchText }
    set {
      objectWillChange.send()
      listNotesStore.updateSearchText(newValue)
    }
  }

  var isListSearchBarExpanded: Bool {
    get { listNotesStore.isSearchBarExpanded }
    set {
      objectWillChange.send()
      listNotesStore.updateSearchBarExpanded(newValue)
    }
  }

  // Returns whether the active plan can use the requested capability.
  func hasAccess(to capability: AppCapability) -> Bool {
    planAccessStore.hasAccess(to: capability)
  }

  #if DEBUG
    // Persists a local plan override for testing free and paid feature gates.
    func updateDeveloperPlan(_ plan: AppPlan) {
      guard activePlan != plan else { return }
      objectWillChange.send()
      planAccessStore.updateDeveloperPlan(plan)
      refreshBackupHealth()
    }
  #endif

  deinit {
    periodicFlushTask?.cancel()
    periodicFlushTask = nil

    for task in pendingSaveTasks.values {
      task.cancel()
    }
    pendingSaveTasks.removeAll()

    for task in pendingListNoteSaveTasks.values {
      task.cancel()
    }
    pendingListNoteSaveTasks.removeAll()

    periodicBackupCheckTask?.cancel()
    periodicBackupCheckTask = nil
  }

  var isSearchActive: Bool {
    !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var dailyNotesForDisplay: [DayNote] {
    activeDailyNotes
  }

  var isListModeAvailable: Bool {
    #if DEBUG
      !isDemoModeEnabled
    #else
      true
    #endif
  }

  // Fast lookup set for daily search matches in calendar mode.
  var filteredDailyNoteIDs: Set<DayNote.ID> {
    Set(filteredNotes.map(\.id))
  }

  // The oldest/newest years available to the calendar browser, always including today.
  var calendarYearBounds: ClosedRange<Int> {
    let currentYear = calendar.component(.year, from: .now)
    let noteYears = activeDailyNotes.map { calendar.component(.year, from: $0.date) }
    let minimumYear = min(noteYears.min() ?? currentYear, currentYear)
    let maximumYear = max(noteYears.max() ?? currentYear, currentYear)
    return minimumYear...maximumYear
  }

  func clearSearch() {
    searchText = ""
    isSearchBarExpanded = false
  }

  #if DEBUG
    // Toggles the in-memory demo library used for screenshot and local testing flows.
    func setDemoModeEnabled(_ enabled: Bool, referenceDate: Date = .now) {
      guard enabled != isDemoModeEnabled else { return }

      if enabled {
        enableDemoMode(relativeTo: referenceDate)
      } else {
        disableDemoMode()
      }
    }

    private func enableDemoMode(relativeTo referenceDate: Date) {
      demoReturnContext = DemoReturnContext(
        sidebarMode: sidebarMode,
        selectedNoteID: selectedNoteID,
        selectedListNoteID: selectedListNoteID,
        searchText: searchText,
        isSearchBarExpanded: isSearchBarExpanded,
        listSearchText: listSearchText,
        isListSearchBarExpanded: isListSearchBarExpanded,
        calendarBrowseYear: calendarBrowseYear
      )

      demoNotes = DayNote.demoModeNotes(relativeTo: referenceDate, calendar: calendar)
      isDemoModeEnabled = true
      sidebarMode = .daily
      selectedNoteID = demoNotes.first?.id
      searchText = ""
      isSearchBarExpanded = false
      calendarBrowseYear = calendar.component(.year, from: demoNotes.first?.date ?? referenceDate)
    }

    private func disableDemoMode() {
      let returnContext = demoReturnContext
      demoReturnContext = nil
      isDemoModeEnabled = false
      demoNotes = []

      guard let returnContext else {
        selectedNoteID = notes.first?.id
        return
      }

      selectedNoteID = returnContext.selectedNoteID
      selectedListNoteID = returnContext.selectedListNoteID
      sidebarMode = returnContext.sidebarMode
      searchText = returnContext.searchText
      isSearchBarExpanded = returnContext.isSearchBarExpanded
      listSearchText = returnContext.listSearchText
      isListSearchBarExpanded = returnContext.isListSearchBarExpanded
      calendarBrowseYear = returnContext.calendarBrowseYear
    }
  #endif

  private var activeDailyNotes: [DayNote] {
    #if DEBUG
      if isDemoModeEnabled {
        return demoNotes
      }
    #endif

    return notes
  }

  private var filteredNotes: [DayNote] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    let dailyNotes = activeDailyNotes
    guard !query.isEmpty else { return dailyNotes }
    return dailyNotes.filter { note in
      note.title.localizedCaseInsensitiveContains(query)
        || note.tags.contains(where: { $0.localizedCaseInsensitiveContains(query) })
        || Self.searchableBody(note.body).localizedCaseInsensitiveContains(query)
    }
  }

  // Strips <!-- ... --> markers (section color directives) so they don't cause false-positive matches.
  static func searchableBody(_ body: String) -> String {
    guard body.contains("<!--") else { return body }
    var result = body
    while let start = result.range(of: "<!--"),
      let end = result.range(of: "-->", range: start.upperBound..<result.endIndex)
    {
      result.removeSubrange(start.lowerBound..<end.upperBound)
    }
    return result
  }

  // Groups notes by month for sidebar section display.
  var monthSections: [NoteMonthSection] {
    if let cachedMonthSections {
      return cachedMonthSections
    }

    let groupedNotes = Dictionary(grouping: filteredNotes) { note in
      calendar.date(from: calendar.dateComponents([.year, .month], from: note.date))
        ?? calendar.startOfDay(for: note.date)
    }

    let builtSections =
      groupedNotes
      .map { key, value in
        NoteMonthSection(
          monthStartDate: key,
          notes: value.sorted(by: { $0.date > $1.date })
        )
      }
      .sorted(by: { $0.monthStartDate > $1.monthStartDate })
    cachedMonthSections = builtSections
    return builtSections
  }

  // Whether a note already exists for today's date.
  var hasTodayNote: Bool {
    note(withID: dayID(for: .now)) != nil
  }

  // The currently selected note, if any.
  var selectedNote: DayNote? {
    guard let selectedNoteID else {
      return nil
    }

    return note(withID: selectedNoteID)
  }

  // Loads notes from disk on first call, seeds starter notes if empty.
  func loadIfNeeded() {
    guard !hasLoaded else {
      return
    }

    isLoading = true

    do {
      try loadNotes()
      Self.logger.info("Loaded \(self.notes.count) notes")
      userMessage = nil
    } catch {
      report(error, context: "Loading notes failed")
      notes = [DayNote.empty(for: .now, calendar: calendar)]
      rebuildNoteIndex()
      selectedNoteID = notes.first?.id

      do {
        try save(notes[0])
      } catch {
        report(error, context: "Creating today's note failed")
      }
    }

    loadListNotesIfNeeded()

    hasLoaded = true
    isLoading = false
    startPeriodicFlush()
    startPeriodicBackupChecks()
    refreshBackupHealth()
    checkAndRunBackupIfDue(trigger: .launchCatchUp)
  }

  // Creates today's note if needed and selects it.
  func selectToday() {
    #if DEBUG
      if isDemoModeEnabled {
        selectedNoteID = demoNotes.first?.id
        if let date = demoNotes.first?.date {
          calendarBrowseYear = calendar.component(.year, from: date)
        }
        return
      }
    #endif

    do {
      try ensureTodayNoteExists()
      selectedNoteID = dayID(for: .now)
      calendarBrowseYear = calendar.component(.year, from: .now)
    } catch {
      report(error, context: "Opening today's note failed")
    }
  }

  // Opens an existing daily note for the target date, creating a blank one when missing.
  func openDailyDate(_ date: Date) {
    let targetDate = calendar.startOfDay(for: date)

    #if DEBUG
      if isDemoModeEnabled {
        guard let note = dailyNote(on: targetDate) else {
          userMessage = (text: "Demo Library only includes the sample notes.", kind: .info)
          return
        }

        selectedNoteID = note.id
        calendarBrowseYear = calendar.component(.year, from: targetDate)
        return
      }
    #endif

    do {
      let note = try ensureDailyNoteExists(
        for: targetDate, applyTodayDefault: calendar.isDateInToday(targetDate))
      selectedNoteID = note.id
      calendarBrowseYear = calendar.component(.year, from: targetDate)
    } catch {
      report(error, context: "Opening note failed")
    }
  }

  // Returns the daily note saved for a date, if one exists.
  func dailyNote(on date: Date) -> DayNote? {
    note(withID: dayID(for: date))
  }

  // Steps the visible calendar year while staying inside the available note range.
  func browseCalendarYear(by delta: Int) {
    let bounds = calendarYearBounds
    let targetYear = min(max(calendarBrowseYear + delta, bounds.lowerBound), bounds.upperBound)
    calendarBrowseYear = targetYear
  }

  // Whether a one-step year navigation stays inside the available note range.
  func canBrowseCalendarYear(by delta: Int) -> Bool {
    calendarYearBounds.contains(calendarBrowseYear + delta)
  }

  // Clears the current user-facing message banner.
  func dismissMessage() {
    userMessage = nil
  }

  // Immediately writes all debounced saves to disk.
  func flushPendingSaves() {
    let noteIDs = Array(pendingSaveTasks.keys)

    for noteID in noteIDs {
      flushPendingSave(for: noteID)
    }

    flushAllPendingListNoteSaves()
  }

  // Flushes pending saves every 5 seconds as a safety net against data loss on crash.
  private func startPeriodicFlush() {
    periodicFlushTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        guard !Task.isCancelled else { break }
        self?.flushPendingSaves()
      }
    }
  }

  // Looks up a note by ID using the fast index, falling back to linear search.
  func note(withID noteID: DayNote.ID) -> DayNote? {
    #if DEBUG
      if isDemoModeEnabled {
        return demoNotes.first(where: { $0.id == noteID })
      }
    #endif

    return dailyNotesStore.note(withID: noteID)
  }

  // Sets the selected note ID.
  func select(noteID: DayNote.ID) {
    selectedNoteID = noteID
  }

  // Selects the next newer note (earlier in date-descending array).
  func selectNextNote() {
    guard let currentID = selectedNoteID,
      let currentIndex = activeDailyNotes.firstIndex(where: { $0.id == currentID }),
      currentIndex > activeDailyNotes.startIndex
    else { return }
    selectedNoteID = activeDailyNotes[currentIndex - 1].id
  }

  // Selects the next older note (later in date-descending array).
  func selectPreviousNote() {
    guard let currentID = selectedNoteID,
      let currentIndex = activeDailyNotes.firstIndex(where: { $0.id == currentID }),
      activeDailyNotes.indices.contains(currentIndex + 1)
    else { return }
    selectedNoteID = activeDailyNotes[currentIndex + 1].id
  }

  // Persists the new-note default preference to UserDefaults.
  func updateNewNoteDefault(_ value: NewNoteDefault) {
    objectWillChange.send()
    editorPreferencesStore.updateNewNoteDefault(value)
  }

  // Persists the body editor's continuous spell-check setting.
  func updateContinuousSpellCheckingEnabled(_ value: Bool) {
    objectWillChange.send()
    editorPreferencesStore.updateContinuousSpellCheckingEnabled(value)
  }

  // Moves a note to a new date by re-creating it with the target date's ID and file.
  func changeDate(noteID: DayNote.ID, to newDate: Date) {
    #if DEBUG
      if isDemoModeEnabled {
        userMessage = (text: "Demo Library notes cannot be moved.", kind: .info)
        return
      }
    #endif

    let targetDate = calendar.startOfDay(for: newDate)
    let targetID = dayID(for: targetDate)

    guard let sourceNote = note(withID: noteID) else { return }

    if note(withID: targetID) != nil {
      let formatted = NoteDateFormatters.editorDate.string(from: targetDate)
      userMessage = (text: "A note already exists for \(formatted).", kind: .error)
      return
    }

    flushPendingSave(for: noteID)

    let movedNote = DayNote(
      date: targetDate,
      title: sourceNote.title,
      tags: sourceNote.tags,
      body: NoteImageAttachmentStore.rewritingAttachmentReferences(
        in: sourceNote.body,
        from: sourceNote.id,
        to: targetID
      )
    )

    do {
      try save(movedNote)
      try libraryRepository.moveAttachments(
        from: sourceNote.id,
        to: movedNote.id
      )
      try deleteFile(for: sourceNote)
    } catch {
      report(error, context: "Changing note date failed")
      return
    }

    notes.removeAll(where: { $0.id == noteID })
    notes.append(movedNote)
    notes.sort(by: { $0.date > $1.date })
    rebuildNoteIndex()
    selectedNoteID = movedNote.id
  }

  // Deletes the requested note so shared UI flows can confirm destructive actions centrally.
  func delete(noteID: DayNote.ID) {
    #if DEBUG
      if isDemoModeEnabled {
        userMessage = (text: "Demo Library notes cannot be deleted.", kind: .info)
        return
      }
    #endif

    guard let note = note(withID: noteID) else {
      return
    }

    let adjacentNoteIDs = adjacentNoteIDs(for: noteID)
    flushPendingSave(for: noteID)

    do {
      try deleteFile(for: note)
      try libraryRepository.deleteAttachments(for: note.id)
    } catch {
      report(error, context: "Deleting note failed")
      return
    }

    notes.removeAll(where: { $0.id == noteID })
    rebuildNoteIndex()

    if notes.isEmpty {
      do {
        try seedStarterNotes()
        selectedNoteID = notes.first?.id
        userMessage = nil
      } catch {
        report(error, context: "Loading sample notes after delete failed")
        selectedNoteID = nil
      }
      return
    }

    selectedNoteID = adjacentNoteIDs.previous ?? adjacentNoteIDs.next ?? notes.first?.id
  }

  // Returns the nearest older and newer notes so header arrows only step through saved notes.
  func adjacentNoteIDs(for noteID: DayNote.ID) -> (previous: DayNote.ID?, next: DayNote.ID?) {
    let dailyNotes = activeDailyNotes
    guard let currentIndex = dailyNotes.firstIndex(where: { $0.id == noteID }) else {
      return (nil, nil)
    }

    let previousNoteID =
      dailyNotes.indices.contains(currentIndex + 1) ? dailyNotes[currentIndex + 1].id : nil
    let nextNoteID = currentIndex > dailyNotes.startIndex ? dailyNotes[currentIndex - 1].id : nil

    return (previousNoteID, nextNoteID)
  }

  // Two-way binding for the note title, auto-saving on change.
  func titleBinding(for noteID: DayNote.ID) -> Binding<String> {
    Binding(
      get: { self.note(withID: noteID)?.title ?? "" },
      set: { self.updateTitle($0, for: noteID) }
    )
  }

  // Two-way binding for the raw tags string, auto-saving on change.
  func tagsBinding(for noteID: DayNote.ID) -> Binding<String> {
    Binding(
      get: { self.note(withID: noteID)?.tags.joined(separator: ", ") ?? "" },
      set: { self.updateTags($0, for: noteID) }
    )
  }

  // Two-way binding for the note body, auto-saving on change.
  func bodyBinding(for noteID: DayNote.ID) -> Binding<String> {
    Binding(
      get: { self.note(withID: noteID)?.body ?? "" },
      set: { self.updateBody($0, for: noteID) }
    )
  }

  // Reads all .md files from the notes directory and seeds if empty.
  private func loadNotes() throws {
    let loadedNotes = try libraryRepository.loadDailyNotes()
    if loadedNotes.isEmpty {
      try seedStarterNotes()
    } else {
      notes = loadedNotes
      rebuildNoteIndex()
    }

    selectedNoteID = notes.first?.id
  }

  // Seeds recent example notes so the first launch shows formatting features immediately.
  private func seedStarterNotes() throws {
    let sampleNotes = DayNote.sampleSeedNotes(relativeTo: .now, calendar: calendar)

    for note in sampleNotes {
      try save(note)
    }

    notes = sampleNotes
    rebuildNoteIndex()
  }

  // Creates today's note (blank or copy-previous) if it doesn't exist.
  private func ensureTodayNoteExists() throws {
    _ = try ensureDailyNoteExists(for: .now, applyTodayDefault: true)
  }

  // Creates a daily note for the date when missing and returns the existing or new note.
  private func ensureDailyNoteExists(for date: Date, applyTodayDefault: Bool) throws -> DayNote {
    let targetDate = calendar.startOfDay(for: date)
    let targetID = dayID(for: targetDate)

    if let existingNote = note(withID: targetID) {
      return existingNote
    }

    let newNote = makeDailyNote(for: targetDate, applyTodayDefault: applyTodayDefault)
    notes = ([newNote] + notes).sorted(by: { $0.date > $1.date })
    rebuildNoteIndex()
    try save(newNote)
    return newNote
  }

  // Builds a day note using the configured default when creating today's note.
  private func makeDailyNote(for date: Date, applyTodayDefault: Bool) -> DayNote {
    let startOfDay = calendar.startOfDay(for: date)

    guard applyTodayDefault else {
      return DayNote.empty(for: startOfDay, calendar: calendar)
    }

    if case .copyPrevious = newNoteDefault, let mostRecent = notes.first {
      return DayNote(
        date: startOfDay,
        title: mostRecent.title,
        tags: mostRecent.tags,
        body: mostRecent.body
      )
    }

    if case .template(let templateID) = newNoteDefault,
      let template = noteTemplate(withID: templateID)
    {
      return DayNote(
        date: startOfDay,
        title: "",
        tags: [],
        body: template.resolvedBodyForInsertion
      )
    }

    return DayNote.empty(for: startOfDay, calendar: calendar)
  }

  // Updates a note's title and schedules a save.
  private func updateTitle(_ title: String, for noteID: DayNote.ID) {
    update(noteID: noteID) { note in
      note.title = title
    }
  }

  // Updates a note's tags (normalized) and schedules a save.
  private func updateTags(_ rawTags: String, for noteID: DayNote.ID) {
    update(noteID: noteID) { note in
      note.tags = normalizedTags(from: rawTags)
    }
  }

  // Updates a note's body and schedules a save.
  private func updateBody(_ body: String, for noteID: DayNote.ID) {
    update(noteID: noteID) { note in
      note.body = body
    }
  }

  // Applies a mutation to appearance settings, clamps, and persists.
  func updateAppearanceSettings(_ mutate: (inout NoteAppearanceSettings) -> Void) {
    objectWillChange.send()

    do {
      try appearanceSettingsStore.updateSettings(mutate)
    } catch {
      report(error, context: "Saving appearance settings failed")
    }
  }

  // Applies a mutation to a note, rebuilds the index, and schedules a save.
  private func update(noteID: DayNote.ID, mutate: (inout DayNote) -> Void) {
    #if DEBUG
      if isDemoModeEnabled {
        guard let index = demoNotes.firstIndex(where: { $0.id == noteID }) else {
          return
        }

        var updatedNotes = demoNotes
        mutate(&updatedNotes[index])
        demoNotes = updatedNotes
        return
      }
    #endif

    guard let index = notes.firstIndex(where: { $0.id == noteID }) else {
      return
    }

    var updatedNotes = notes
    mutate(&updatedNotes[index])
    notes = updatedNotes
    rebuildNoteIndex()
    scheduleSave(for: noteID)
  }

  // Debounces saves at 350ms to avoid excessive disk writes.
  private func scheduleSave(for noteID: DayNote.ID) {
    pendingSaveTasks[noteID]?.cancel()
    pendingSaveTasks[noteID] = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 350_000_000)
      guard !Task.isCancelled else {
        return
      }

      self?.persistPendingSave(for: noteID)
    }
  }

  // Writes a single pending note to disk.
  private func persistPendingSave(for noteID: DayNote.ID) {
    pendingSaveTasks[noteID] = nil

    guard let note = note(withID: noteID) else {
      return
    }

    do {
      try save(note)
    } catch {
      report(error, context: "Saving note failed")
    }
  }

  // Cancels debounce and immediately writes a single note.
  private func flushPendingSave(for noteID: DayNote.ID) {
    let hadPendingSave = pendingSaveTasks[noteID] != nil
    pendingSaveTasks[noteID]?.cancel()
    pendingSaveTasks[noteID] = nil

    guard hadPendingSave, let note = note(withID: noteID) else {
      return
    }

    do {
      try save(note)
    } catch {
      report(error, context: "Saving note before delete failed")
    }
  }

  // Encodes and writes a note to its markdown file.
  func save(_ note: DayNote) throws {
    try libraryRepository.saveDailyNote(note)
  }

  // Removes the markdown file for a note from disk.
  private func deleteFile(for note: DayNote) throws {
    try libraryRepository.deleteDailyNoteFile(for: note)
  }

  // Encodes appearance settings to UserDefaults.
  func persistAppearanceSettings() {
    do {
      try appearanceSettingsStore.persistSettings()
    } catch {
      report(error, context: "Saving appearance settings failed")
    }
  }

  // Returns the notes directory, creating it if needed.
  func notesDirectoryURL() throws -> URL {
    try libraryRepository.dailyNotesDirectoryURL()
  }

  // Formats a date as the YYYY-MM-DD storage key.
  private func dayID(for date: Date) -> DayNote.ID {
    NoteDateFormatters.storageDate.string(from: calendar.startOfDay(for: date))
  }

  // Splits, trims, and deduplicates a raw comma-separated tags string.
  private func normalizedTags(from rawTags: String) -> [String] {
    var seenTags = Set<String>()
    var normalizedTags: [String] = []

    for rawTag in rawTags.split(separator: ",", omittingEmptySubsequences: false) {
      let trimmedTag = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmedTag.isEmpty else {
        continue
      }

      let dedupeKey = trimmedTag.lowercased()
      guard seenTags.insert(dedupeKey).inserted else {
        continue
      }

      normalizedTags.append(trimmedTag)
    }

    return normalizedTags
  }

  // Rebuilds the ID-to-array-index lookup dictionary.
  func rebuildNoteIndex() {
    dailyNotesStore.rebuildNoteIndex()
  }

  // Keeps the visible calendar year inside the available note range after note changes.
  private func clampCalendarBrowseYear() {
    let bounds = calendarYearBounds
    if calendarBrowseYear < bounds.lowerBound {
      calendarBrowseYear = bounds.lowerBound
    } else if calendarBrowseYear > bounds.upperBound {
      calendarBrowseYear = bounds.upperBound
    }
  }

  // When calendar mode is active, the grid follows the currently selected daily note.
  private func syncCalendarBrowseYearToSelectedNote() {
    if let selectedNote {
      calendarBrowseYear = calendar.component(.year, from: selectedNote.date)
    } else {
      clampCalendarBrowseYear()
    }
  }

  // Logs an error and surfaces it as a user-facing message.
  func report(_ error: Error, context: String) {
    let message =
      error.localizedDescription.isEmpty ? String(describing: error) : error.localizedDescription
    Self.logger.error("\(context): \(message)")
    userMessage = (text: "\(context). \(message)", kind: .error)
  }
}
