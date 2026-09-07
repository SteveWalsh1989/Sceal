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

enum UserMessageKind: Equatable {
  case error
  case info
}

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
  @Published var isLibraryRecoveryBlocked = false
  @Published var progressMessage: String?
  @Published var backupHealth: BackupHealth
  @Published var isBackupRunning = false
  @Published var structuredNotesCutoverStatus: StructuredNotesCutoverStatus
  @Published var structuredNotesCutoverFailureDescription: String?
  @Published var structuredNotes: [StructuredNoteDocument] = []
  @Published var selectedStructuredNoteID: String?
  @Published var structuredSearchText = ""
  @Published var isStructuredSearchBarExpanded = false
  @Published var structuredCalendarBrowseYear: Int
  @Published var structuredListNotes: [StructuredNoteDocument] = []
  @Published var structuredListNoteManifest: ListNotesManifest = .empty
  @Published var selectedStructuredListNoteID: String?
  @Published var listSearchText = ""
  @Published var isListSearchBarExpanded = false
  #if DEBUG
    @Published var isDemoModeEnabled = false
  #else
    var isDemoModeEnabled: Bool { false }
  #endif

  let fileManager: FileManager
  let calendar: Calendar
  let enforcesStructuredCutover: Bool
  private(set) var libraryLocation: ScealLibraryLocation
  private(set) var libraryRepository: LibraryRepository
  private(set) var structuredNoteRepository: StructuredNoteRepository
  private(set) var structuredListNoteRepository: StructuredNoteRepository
  let settingsRepository: SettingsRepository
  let appearanceSettingsStore: AppearanceSettingsStore
  let backupSettingsStore: BackupSettingsStore
  let editorPreferencesStore: EditorPreferencesStore
  let planAccessStore: PlanAccessStore
  let noteTemplatesStore: NoteTemplatesStore
  let archiveService: ArchiveService
  var hasLoaded = false
  var hasLoadedStructuredNotes = false
  var hasLoadedStructuredListNotes = false
  var cachedMonthSections: [NoteMonthSection]?
  var pendingStructuredNoteSaveTasks: [StructuredNoteSaveKey: Task<Void, Never>] = [:]
  private var periodicFlushTask: Task<Void, Never>?
  var periodicBackupCheckTask: Task<Void, Never>?
  private var userMessageDismissTask: Task<Void, Never>?
  #if DEBUG
    private var structuredDemoReturnContext:
      (
        location: ScealLibraryLocation, notes: [StructuredNoteDocument], selectedID: String?,
        query: String, expanded: Bool, year: Int, sidebarMode: SidebarMode,
        listSelectedID: String?, listQuery: String, listExpanded: Bool
      )?
  #endif

  static let logger = Logger(subsystem: "com.sceal.app", category: "store")

  nonisolated static var defaultEnforcesStructuredCutover: Bool {
    true
  }

  init(
    fileManager: FileManager = .default,
    calendar: Calendar = .current,
    userDefaults: UserDefaults = .standard,
    libraryLocation: ScealLibraryLocation? = nil,
    previewStructuredNotes: [StructuredNoteDocument] = [],
    enforcesStructuredCutover: Bool = NotesStore.defaultEnforcesStructuredCutover
  ) {
    self.fileManager = fileManager
    self.calendar = calendar
    self.enforcesStructuredCutover = enforcesStructuredCutover
    let resolvedSettingsRepository = SettingsRepository(userDefaults: userDefaults)
    self.settingsRepository = resolvedSettingsRepository
    let loadedCutoverStatus = resolvedSettingsRepository.loadStructuredNotesCutoverStatus()
    self.structuredNotesCutoverStatus = loadedCutoverStatus
    self.structuredNotesCutoverFailureDescription = nil
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
    self.structuredNoteRepository = StructuredNoteRepository(
      libraryLocation: resolvedLibraryLocation,
      fileManager: fileManager
    )
    self.structuredListNoteRepository = StructuredNoteRepository.listNotes(
      libraryLocation: resolvedLibraryLocation,
      fileManager: fileManager
    )
    let sortedNotes = previewStructuredNotes.sorted(by: { $0.date > $1.date })
    let loadedBackupSettings = resolvedBackupSettingsStore.settings
    let currentYear = calendar.component(.year, from: .now)
    self.structuredCalendarBrowseYear = currentYear
    self.structuredNotes = sortedNotes
    self.selectedStructuredNoteID = sortedNotes.first?.id
    self.backupHealth = loadedBackupSettings.isConfigured ? .healthy : .notConfigured
    self.hasLoaded = !previewStructuredNotes.isEmpty
    self.hasLoadedStructuredNotes = !previewStructuredNotes.isEmpty
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

  var effectiveNewNoteDefault: NewNoteDefault {
    guard case .template(let templateID) = newNoteDefault,
      isNoteTemplateLockedByPlan(templateID)
    else {
      return newNoteDefault
    }

    return .blank
  }

  var notes: [DayNote] { structuredNoteSummaries }

  var selectedNoteID: DayNote.ID? {
    get { selectedStructuredNoteID }
    set {
      selectStructuredNote(newValue)
    }
  }

  var searchText: String {
    get { structuredSearchText }
    set { updateStructuredSearchText(newValue) }
  }

  var isSearchBarExpanded: Bool {
    get { isStructuredSearchBarExpanded }
    set { updateStructuredSearchBarExpanded(newValue) }
  }

  var calendarBrowseYear: Int {
    get { structuredCalendarBrowseYear }
    set { structuredCalendarBrowseYear = newValue }
  }

  var listNotes: [DayNote] { structuredListNoteSummaries }

  var listNoteManifest: ListNotesManifest {
    get { structuredListNoteManifest }
    set { structuredListNoteManifest = newValue }
  }

  var selectedListNoteID: DayNote.ID? {
    get { selectedStructuredListNoteID }
    set { selectStructuredListNote(newValue) }
  }

  // Returns whether the active plan can use the requested capability.
  func hasAccess(to capability: AppCapability) -> Bool {
    planAccessStore.hasAccess(to: capability)
  }

  #if DEBUG
    // Persists a local plan override for testing free and paid feature gates.
    func updateDeveloperPlan(_ plan: AppPlan) {
      guard activePlan != plan else {
        planAccessStore.updateDeveloperPlan(plan)
        return
      }
      objectWillChange.send()
      planAccessStore.updateDeveloperPlan(plan)
      refreshBackupHealth()
    }

    var canResetDeveloperLibrary: Bool {
      DeveloperLibrarySeeder.canResetLibrary(
        at: libraryLocation.rootURL,
        fileManager: fileManager
      )
    }

    var canCopyProductionLibraryToDeveloper: Bool {
      DeveloperLibrarySeeder.canCopyProductionLibraryToDeveloper(
        at: libraryLocation,
        fileManager: fileManager
      )
    }
  #endif

  deinit {
    periodicFlushTask?.cancel()
    periodicFlushTask = nil

    for task in pendingStructuredNoteSaveTasks.values {
      task.cancel()
    }
    pendingStructuredNoteSaveTasks.removeAll()

    periodicBackupCheckTask?.cancel()
    periodicBackupCheckTask = nil
  }

  var isSearchActive: Bool {
    !structuredSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var dailyNotesForDisplay: [DayNote] {
    structuredNoteSummaries
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
    let noteYears = structuredNotes.map { calendar.component(.year, from: $0.date) }
    let minimumYear = min(noteYears.min() ?? currentYear, currentYear)
    let maximumYear = max(noteYears.max() ?? currentYear, currentYear)
    return minimumYear...maximumYear
  }

  func clearSearch() {
    updateStructuredSearchText("")
    updateStructuredSearchBarExpanded(false)
  }

  #if DEBUG
    // Switches to disposable structured samples without replacing the user's library.
    func setDemoModeEnabled(_ enabled: Bool, referenceDate: Date = .now) {
      guard enabled != isDemoModeEnabled else { return }

      if enabled {
        guard canBeginLibraryFileOperation() else { return }
        do {
          try flushPendingSavesForLibraryOperation()
          try enableDemoMode(relativeTo: referenceDate)
        } catch {
          report(error, context: "Opening demo library failed")
          return
        }
      } else {
        disableDemoMode()
      }
    }

    // Replaces the active DEBUG file-backed library with deterministic throwaway data.
    func resetDeveloperLibrary(referenceDate: Date = .now) {
      guard canBeginLibraryFileOperation() else { return }
      guard canResetDeveloperLibrary else {
        userMessage = (
          text: "Developer library reset is not available for this storage location.",
          kind: .error
        )
        return
      }

      isPerformingFileOperation = true
      progressMessage = "Resetting developer library..."
      defer {
        isPerformingFileOperation = false
        progressMessage = nil
      }

      do {
        try flushPendingSavesForLibraryOperation()
        if isDemoModeEnabled {
          disableDemoMode()
          guard !isDemoModeEnabled else { return }
        }

        let snapshot = try DeveloperLibrarySeeder.resetLibrary(
          at: libraryLocation,
          fileManager: fileManager,
          calendar: calendar,
          referenceDate: referenceDate
        )
        applyDeveloperLibrarySnapshot(snapshot)
        userMessage = (text: "Developer library reset.", kind: .info)
      } catch {
        report(error, context: "Resetting developer library failed")
      }
    }

    // Copies the production library into DEBUG storage so local testing can use real data safely.
    func copyProductionLibraryToDeveloperLibrary() {
      guard canBeginLibraryFileOperation() else { return }
      guard canCopyProductionLibraryToDeveloper else {
        userMessage = (
          text: "Production library copy is not available for this storage location.",
          kind: .error
        )
        return
      }

      isPerformingFileOperation = true
      progressMessage = "Copying production library..."
      defer {
        isPerformingFileOperation = false
        progressMessage = nil
      }

      do {
        try flushPendingSavesForLibraryOperation()
        if isDemoModeEnabled {
          disableDemoMode()
          guard !isDemoModeEnabled else { return }
        }

        let snapshot = try DeveloperLibrarySeeder.copyProductionLibraryToDeveloper(
          at: libraryLocation,
          fileManager: fileManager
        )
        applyDeveloperLibrarySnapshot(snapshot)

        let backupText =
          snapshot.developerBackupURL == nil ? "" : " Previous developer library was backed up."
        userMessage = (
          text:
            "Copied \(snapshot.dailyNotes.count) daily notes and \(snapshot.listNotes.count) list notes into the developer library.\(backupText)",
          kind: .info
        )
      } catch {
        report(error, context: "Copying production library failed")
      }
    }

    private func applyDeveloperLibrarySnapshot(_: DeveloperLibrarySeedSnapshot) {
      hasLoaded = false
      hasLoadedStructuredNotes = false
      hasLoadedStructuredListNotes = false
      sidebarMode = .daily
      structuredSearchText = ""
      isStructuredSearchBarExpanded = false
      listSearchText = ""
      isListSearchBarExpanded = false
      setStructuredCutoverStatus(.notStarted)
      prepareStructuredCutoverForProductionLaunch()
    }

    private func enableDemoMode(relativeTo referenceDate: Date) throws {
      let location = ScealLibraryLocation.test(
        rootURL: fileManager.temporaryDirectory.appendingPathComponent(
          "sceal-demo-\(UUID().uuidString)"))
      let documents = try DayNote.demoModeNotes(relativeTo: referenceDate, calendar: calendar)
        .map(LegacyMarkdownStructuredNoteAdapter.importDocument)
      let repository = StructuredNoteRepository(
        libraryLocation: location, fileManager: fileManager)
      for document in documents { try repository.save(document) }
      try LibraryRepository(libraryLocation: location, fileManager: fileManager)
        .saveStructuredListNotesManifest(.empty)
      try StructuredLibraryState.markCompleted(at: location)
      structuredDemoReturnContext = (
        libraryLocation, structuredNotes, selectedStructuredNoteID, structuredSearchText,
        isStructuredSearchBarExpanded, structuredCalendarBrowseYear, sidebarMode,
        selectedStructuredListNoteID, listSearchText, isListSearchBarExpanded
      )
      useDeveloperLibraryLocation(location)
      structuredNotes = documents
      selectedStructuredNoteID = documents.first?.id
      structuredSearchText = ""
      isStructuredSearchBarExpanded = false
      structuredCalendarBrowseYear = calendar.component(.year, from: referenceDate)
      isDemoModeEnabled = true
      sidebarMode = .daily
    }

    private func disableDemoMode() {
      guard let context = structuredDemoReturnContext else { return }
      do { try flushPendingSavesForLibraryOperation() } catch {
        report(error, context: "Leaving demo library failed")
        return
      }
      useDeveloperLibraryLocation(context.location)
      structuredNotes = context.notes
      selectedStructuredNoteID = context.selectedID
      structuredSearchText = context.query
      isStructuredSearchBarExpanded = context.expanded
      structuredCalendarBrowseYear = context.year
      selectedStructuredListNoteID = context.listSelectedID
      listSearchText = context.listQuery
      isListSearchBarExpanded = context.listExpanded
      sidebarMode = context.sidebarMode
      structuredDemoReturnContext = nil
      isDemoModeEnabled = false
    }

    // Only the demo workflow changes repositories, and always to a newly created disposable root.
    private func useDeveloperLibraryLocation(_ location: ScealLibraryLocation) {
      libraryLocation = location
      libraryRepository = LibraryRepository(libraryLocation: location, fileManager: fileManager)
      structuredNoteRepository = StructuredNoteRepository(
        libraryLocation: location, fileManager: fileManager)
      structuredListNoteRepository = StructuredNoteRepository.listNotes(
        libraryLocation: location, fileManager: fileManager)
      cachedMonthSections = nil
    }
  #endif

  private var filteredNotes: [DayNote] {
    let query = structuredSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    let dailyNotes = structuredNoteSummaries
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
    if let cachedMonthSections { return cachedMonthSections }

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
    structuredNotes.contains(where: {
      $0.id == NoteDateFormatters.storageDate.string(from: calendar.startOfDay(for: .now))
    })
  }

  // Loads notes from disk on first call, seeds starter notes if empty.
  func loadIfNeeded() {
    guard !hasLoaded else {
      return
    }

    if enforcesStructuredCutover {
      prepareStructuredCutoverForProductionLaunch()
      return
    }
    loadValidatedLibraryIfNeeded()
  }

  // Production callers must pass the authority/conversion gate before loading editable data.
  func loadValidatedLibraryIfNeeded() {
    guard !hasLoaded else { return }
    guard recoverLibraryInstallationBeforeLoading() else { return }
    isLoading = true
    defer { isLoading = false }

    do {
      try loadStructuredDailyNotesIfNeeded()
      try loadStructuredListNotesIfNeeded()
    } catch {
      structuredNotesCutoverFailureDescription = error.localizedDescription
      setStructuredCutoverStatus(.recoveryRequired)
      report(error, context: "Opening the structured library failed")
      return
    }

    hasLoaded = true
    startPeriodicFlush()
    startPeriodicBackupChecks()
    refreshBackupHealth()
    checkAndRunBackupIfDue(trigger: .launchCatchUp)
  }

  // Creates today's note if needed and selects it.
  func selectToday() {
    selectStructuredDailyDate(.now)
  }

  // Opens an existing daily note for the target date, creating a blank one when missing.
  func openDailyDate(_ date: Date) {
    selectStructuredDailyDate(calendar.startOfDay(for: date))
  }

  // Returns the daily note saved for a date, if one exists.
  func dailyNote(on date: Date) -> DayNote? {
    let noteID = NoteDateFormatters.storageDate.string(from: calendar.startOfDay(for: date))
    return structuredNoteSummaries.first(where: { $0.id == noteID })
  }

  // Steps the visible calendar year while staying inside the available note range.
  func browseCalendarYear(by delta: Int) {
    let bounds = calendarYearBounds
    let currentYear = structuredCalendarBrowseYear
    let targetYear = min(max(currentYear + delta, bounds.lowerBound), bounds.upperBound)
    structuredCalendarBrowseYear = targetYear
  }

  // Whether a one-step year navigation stays inside the available note range.
  func canBrowseCalendarYear(by delta: Int) -> Bool {
    calendarYearBounds.contains(structuredCalendarBrowseYear + delta)
  }

  // Clears the current user-facing message banner.
  func dismissMessage() {
    userMessageDismissTask?.cancel()
    userMessageDismissTask = nil
    userMessage = nil
  }

  // Shows a user-facing message briefly without affecting persistent errors and notices.
  func showTransientMessage(
    _ text: String,
    kind: UserMessageKind,
    dismissAfterNanoseconds: UInt64 = 1_800_000_000
  ) {
    userMessageDismissTask?.cancel()
    let message = (text: text, kind: kind)
    userMessage = message

    userMessageDismissTask = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: dismissAfterNanoseconds)
      guard
        !Task.isCancelled,
        let self,
        self.userMessage?.text == message.text,
        self.userMessage?.kind == message.kind
      else { return }

      self.userMessage = nil
      self.userMessageDismissTask = nil
    }
  }

  // Immediately writes all debounced saves to disk.
  func flushPendingSaves() {
    guard !isLibraryRecoveryBlocked else { return }
    flushAllPendingStructuredNoteSaves()
  }

  // A file operation must not snapshot old disk content or replace retryable unsaved edits.
  func flushPendingSavesForLibraryOperation() throws {
    guard !isLibraryRecoveryBlocked,
      try LibraryInstallTransaction.read(at: libraryLocation.rootURL, fileManager: fileManager)
        == nil
    else { throw LibraryInstallTransactionError.pendingRecovery }
    flushPendingSaves()
    guard pendingStructuredNoteSaveTasks.isEmpty else {
      throw LibraryOperationError.pendingChanges
    }
  }

  // Shared admission check also covers automatic backups, which have no blocking progress UI.
  func canBeginLibraryFileOperation() -> Bool {
    guard !enforcesStructuredCutover || isLibraryReadyForEditing else {
      userMessage = (
        text: "Finish opening or recovering the library before starting this operation.",
        kind: .info
      )
      return false
    }
    guard !isLibraryRecoveryBlocked else {
      userMessage = (
        text: LibraryInstallTransactionError.pendingRecovery.localizedDescription, kind: .error
      )
      return false
    }
    guard !isPerformingFileOperation, !isBackupRunning else {
      userMessage = (
        text: LibraryOperationError.operationInProgress.localizedDescription, kind: .info
      )
      return false
    }
    return true
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

  // Sets the selected note ID.
  func select(noteID: DayNote.ID) {
    selectStructuredNote(noteID)
  }

  // Selects the next newer note (earlier in date-descending array).
  func selectNextNote() {
    let dailyNotes = structuredNoteSummaries
    guard let currentID = selectedStructuredNoteID,
      let currentIndex = dailyNotes.firstIndex(where: { $0.id == currentID }),
      currentIndex > dailyNotes.startIndex
    else { return }
    select(noteID: dailyNotes[currentIndex - 1].id)
  }

  // Selects the next older note (later in date-descending array).
  func selectPreviousNote() {
    let dailyNotes = structuredNoteSummaries
    guard let currentID = selectedStructuredNoteID,
      let currentIndex = dailyNotes.firstIndex(where: { $0.id == currentID }),
      dailyNotes.indices.contains(currentIndex + 1)
    else { return }
    select(noteID: dailyNotes[currentIndex + 1].id)
  }

  // Persists the new-note default preference to UserDefaults.
  func updateNewNoteDefault(_ value: NewNoteDefault) {
    if case .template(let templateID) = value, isNoteTemplateLockedByPlan(templateID) {
      userMessage = (text: "Paid is required to use that template as a default.", kind: .info)
      return
    }

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
    changeStructuredNoteDate(noteID: noteID, to: newDate)
  }

  // Deletes the requested note so shared UI flows can confirm destructive actions centrally.
  func delete(noteID: DayNote.ID) {
    deleteStructuredNote(noteID: noteID)
  }

  // Returns the nearest older and newer notes so header arrows only step through saved notes.
  func adjacentNoteIDs(for noteID: DayNote.ID) -> (previous: DayNote.ID?, next: DayNote.ID?) {
    adjacentStructuredNoteIDs(for: noteID)
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

  // Splits, trims, and deduplicates a raw comma-separated tags string.
  func normalizedTags(from rawTags: String) -> [String] {
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
    if let selectedStructuredNote {
      structuredCalendarBrowseYear = calendar.component(.year, from: selectedStructuredNote.date)
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
