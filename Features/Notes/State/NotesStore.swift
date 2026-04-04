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

@MainActor
final class NotesStore: ObservableObject {
  @Published var notes: [DayNote] {
    didSet {
      cachedMonthSections = nil
    }
  }
  @Published private(set) var appearanceSettings: NoteAppearanceSettings
  @Published private(set) var newNoteDefault: NewNoteDefault
  @Published var selectedNoteID: DayNote.ID?
  @Published private(set) var isLoading = false
  @Published var userMessage: (text: String, kind: UserMessageKind)?

  let fileManager: FileManager
  let calendar: Calendar
  private let userDefaults: UserDefaults
  private var hasLoaded = false
  private var noteIndex: [DayNote.ID: Int] = [:]
  private var cachedMonthSections: [NoteMonthSection]?
  private var pendingSaveTasks: [DayNote.ID: Task<Void, Never>] = [:]
  private var periodicFlushTask: Task<Void, Never>?

  private static let logger = Logger(subsystem: "com.sceal.app", category: "store")
  private static let appearanceSettingsDefaultsKey = "sceal.noteAppearanceSettings"
  private static let newNoteDefaultKey = "sceal.newNoteDefault"

  init(
    fileManager: FileManager = .default,
    calendar: Calendar = .current,
    userDefaults: UserDefaults = .standard,
    previewNotes: [DayNote] = []
  ) {
    self.fileManager = fileManager
    self.calendar = calendar
    self.userDefaults = userDefaults
    let sortedNotes = previewNotes.sorted(by: { $0.date > $1.date })
    self.notes = sortedNotes
    self.noteIndex = Dictionary(uniqueKeysWithValues: sortedNotes.enumerated().map { ($1.id, $0) })
    self.appearanceSettings = Self.loadAppearanceSettings(from: userDefaults)
    self.newNoteDefault = Self.loadNewNoteDefault(from: userDefaults)
    self.selectedNoteID = sortedNotes.first?.id
    self.hasLoaded = !previewNotes.isEmpty
  }

  // Groups notes by month for sidebar section display.
  var monthSections: [NoteMonthSection] {
    if let cachedMonthSections {
      return cachedMonthSections
    }

    let groupedNotes = Dictionary(grouping: notes) { note in
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

    hasLoaded = true
    isLoading = false
    startPeriodicFlush()
  }

  // Creates today's note if needed and selects it.
  func selectToday() {
    do {
      try ensureTodayNoteExists()
      selectedNoteID = dayID(for: .now)
    } catch {
      report(error, context: "Opening today's note failed")
    }
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
    if let index = noteIndex[noteID], notes.indices.contains(index), notes[index].id == noteID {
      return notes[index]
    }
    return notes.first(where: { $0.id == noteID })
  }

  // Sets the selected note ID.
  func select(noteID: DayNote.ID) {
    selectedNoteID = noteID
  }

  // Selects the next newer note (earlier in date-descending array).
  func selectNextNote() {
    guard let currentID = selectedNoteID,
      let currentIndex = notes.firstIndex(where: { $0.id == currentID }),
      currentIndex > notes.startIndex
    else { return }
    selectedNoteID = notes[currentIndex - 1].id
  }

  // Selects the next older note (later in date-descending array).
  func selectPreviousNote() {
    guard let currentID = selectedNoteID,
      let currentIndex = notes.firstIndex(where: { $0.id == currentID }),
      notes.indices.contains(currentIndex + 1)
    else { return }
    selectedNoteID = notes[currentIndex + 1].id
  }

  // Persists the new-note default preference to UserDefaults.
  func updateNewNoteDefault(_ value: NewNoteDefault) {
    newNoteDefault = value
    userDefaults.set(value.rawValue, forKey: Self.newNoteDefaultKey)
  }

  // Deletes the requested note so shared UI flows can confirm destructive actions centrally.
  func delete(noteID: DayNote.ID) {
    guard let note = note(withID: noteID) else {
      return
    }

    let adjacentNoteIDs = adjacentNoteIDs(for: noteID)
    flushPendingSave(for: noteID)

    do {
      try deleteFile(for: note)
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
    guard let currentIndex = notes.firstIndex(where: { $0.id == noteID }) else {
      return (nil, nil)
    }

    let previousNoteID = notes.indices.contains(currentIndex + 1) ? notes[currentIndex + 1].id : nil
    let nextNoteID = currentIndex > notes.startIndex ? notes[currentIndex - 1].id : nil

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
    let directoryURL = try notesDirectoryURL()
    let fileURLs = try fileManager.contentsOfDirectory(
      at: directoryURL,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )

    let loadedNotes =
      try fileURLs
      .filter { $0.pathExtension == "md" }
      .map(loadNote)
      .sorted(by: { $0.date > $1.date })

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
    let todayID = dayID(for: .now)
    guard note(withID: todayID) == nil else {
      return
    }

    let todayNote: DayNote
    if newNoteDefault == .copyPrevious, let mostRecent = notes.first {
      todayNote = mostRecent.copyForToday(calendar: calendar)
    } else {
      todayNote = DayNote.empty(for: .now, calendar: calendar)
    }

    notes = ([todayNote] + notes).sorted(by: { $0.date > $1.date })
    rebuildNoteIndex()
    try save(todayNote)
  }

  // Decodes a single note from a markdown file URL.
  private func loadNote(from fileURL: URL) throws -> DayNote {
    let contents = try String(contentsOf: fileURL, encoding: .utf8)
    return try MarkdownNoteCodec.decode(contents: contents, sourceURL: fileURL)
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
    var updatedSettings = appearanceSettings
    mutate(&updatedSettings)
    appearanceSettings = updatedSettings.clamped
    persistAppearanceSettings()
  }

  // Applies a mutation to a note, rebuilds the index, and schedules a save.
  private func update(noteID: DayNote.ID, mutate: (inout DayNote) -> Void) {
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
    let noteURL = try notesDirectoryURL().appendingPathComponent(note.fileName)
    let fileContents = try MarkdownNoteCodec.encode(note)
    try fileContents.write(to: noteURL, atomically: true, encoding: .utf8)
  }

  // Removes the markdown file for a note from disk.
  private func deleteFile(for note: DayNote) throws {
    let noteURL = try notesDirectoryURL().appendingPathComponent(note.fileName)

    guard fileManager.fileExists(atPath: noteURL.path) else {
      return
    }

    try fileManager.removeItem(at: noteURL)
  }

  // Encodes appearance settings to UserDefaults.
  func persistAppearanceSettings() {
    do {
      let data = try JSONEncoder().encode(appearanceSettings)
      userDefaults.set(data, forKey: Self.appearanceSettingsDefaultsKey)
    } catch {
      report(error, context: "Saving appearance settings failed")
    }
  }

  // Decodes appearance settings from UserDefaults with defaults.
  private static func loadAppearanceSettings(from userDefaults: UserDefaults)
    -> NoteAppearanceSettings
  {
    guard
      let data = userDefaults.data(forKey: appearanceSettingsDefaultsKey),
      let settings = try? JSONDecoder().decode(NoteAppearanceSettings.self, from: data)
    else {
      return .default
    }

    return settings.clamped
  }

  // Reads the new-note default preference from UserDefaults.
  private static func loadNewNoteDefault(from userDefaults: UserDefaults) -> NewNoteDefault {
    guard
      let rawValue = userDefaults.string(forKey: newNoteDefaultKey),
      let value = NewNoteDefault(rawValue: rawValue)
    else {
      return .blank
    }

    return value
  }

  // Returns the notes directory, creating it if needed.
  private func notesDirectoryURL() throws -> URL {
    let appSupportURL = try fileManager.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )

    let notesDirectoryURL =
      appSupportURL
      .appendingPathComponent("Sceal", isDirectory: true)
      .appendingPathComponent("Notes", isDirectory: true)

    try fileManager.createDirectory(
      at: notesDirectoryURL,
      withIntermediateDirectories: true
    )

    return notesDirectoryURL
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
    noteIndex = Dictionary(uniqueKeysWithValues: notes.enumerated().map { ($1.id, $0) })
  }

  // Logs an error and surfaces it as a user-facing message.
  func report(_ error: Error, context: String) {
    let message =
      error.localizedDescription.isEmpty ? String(describing: error) : error.localizedDescription
    Self.logger.error("\(context): \(message)")
    userMessage = (text: "\(context). \(message)", kind: .error)
  }
}
