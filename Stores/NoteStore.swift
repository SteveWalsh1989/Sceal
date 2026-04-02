//
//  NoteStore.swift
//
//

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
    ScealDateFormatters.storageDate.string(from: monthStartDate)
  }

  var title: String {
    let isCurrentYear =
      Calendar.current.component(.year, from: monthStartDate)
      == Calendar.current.component(.year, from: Date.now)
    let formatter =
      isCurrentYear
      ? ScealDateFormatters.monthDividerMonthOnly : ScealDateFormatters.monthDivider
    return formatter.string(from: monthStartDate).uppercased()
  }
}

enum UserMessageKind {
  case error
  case info
}

@MainActor
final class NoteStore: ObservableObject {
  @Published private(set) var notes: [DayNote]
  @Published private(set) var appearanceSettings: NoteAppearanceSettings
  @Published private(set) var newNoteDefault: NewNoteDefault
  @Published var selectedNoteID: DayNote.ID?
  @Published private(set) var isLoading = false
  @Published var userMessage: (text: String, kind: UserMessageKind)?

  private let fileManager: FileManager
  private let calendar: Calendar
  private let userDefaults: UserDefaults
  private var hasLoaded = false
  private var noteIndex: [DayNote.ID: Int] = [:]
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

  var monthSections: [NoteMonthSection] {
    let groupedNotes = Dictionary(grouping: notes) { note in
      calendar.date(from: calendar.dateComponents([.year, .month], from: note.date))
        ?? calendar.startOfDay(for: note.date)
    }

    return
      groupedNotes
      .map { key, value in
        NoteMonthSection(
          monthStartDate: key,
          notes: value.sorted(by: { $0.date > $1.date })
        )
      }
      .sorted(by: { $0.monthStartDate > $1.monthStartDate })
  }

  var hasTodayNote: Bool {
    note(withID: dayID(for: .now)) != nil
  }

  var selectedNote: DayNote? {
    guard let selectedNoteID else {
      return nil
    }

    return note(withID: selectedNoteID)
  }

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

  func selectToday() {
    do {
      try ensureTodayNoteExists()
      selectedNoteID = dayID(for: .now)
    } catch {
      report(error, context: "Opening today's note failed")
    }
  }

  func dismissMessage() {
    userMessage = nil
  }

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

  func note(withID noteID: DayNote.ID) -> DayNote? {
    if let index = noteIndex[noteID], notes.indices.contains(index), notes[index].id == noteID {
      return notes[index]
    }
    return notes.first(where: { $0.id == noteID })
  }

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

  func updateBodyFontName(_ bodyFontName: String) {
    updateAppearanceSettings { settings in
      settings.bodyFontName = bodyFontName
    }
  }

  func updateBodyFontSize(_ bodyFontSize: CGFloat) {
    updateAppearanceSettings { settings in
      settings.bodyFontSize = bodyFontSize
    }
  }

  func updateLineHeight(_ lineHeight: CGFloat) {
    updateAppearanceSettings { settings in
      settings.lineHeight = lineHeight
    }
  }

  func updateListItemSpacing(_ listItemSpacing: CGFloat) {
    updateAppearanceSettings { settings in
      settings.listItemSpacing = listItemSpacing
    }
  }

  func updateBulletSize(_ bulletSize: CGFloat) {
    updateAppearanceSettings { settings in
      settings.bulletSize = bulletSize
    }
  }

  func updateSectionDividerGapScale(_ sectionDividerGapScale: CGFloat) {
    updateAppearanceSettings { settings in
      settings.sectionDividerGapScale = sectionDividerGapScale
    }
  }

  func updateSidebarFontSize(_ sidebarFontSize: CGFloat) {
    updateAppearanceSettings { settings in
      settings.sidebarFontSize = sidebarFontSize
    }
  }

  func updateAccentColorName(_ accentColorName: String) {
    updateAppearanceSettings { settings in
      settings.accentColorName = accentColorName
    }
  }

  func updateSidebarShowsTags(_ sidebarShowsTags: Bool) {
    updateAppearanceSettings { settings in
      settings.sidebarShowsTags = sidebarShowsTags
    }
  }

  func updateSidebarDateFormat(_ sidebarDateFormat: SidebarDateFormat) {
    updateAppearanceSettings { settings in
      settings.sidebarDateFormat = sidebarDateFormat
    }
  }

  func updateNewNoteDefault(_ value: NewNoteDefault) {
    newNoteDefault = value
    userDefaults.set(value.rawValue, forKey: Self.newNoteDefaultKey)
  }

  // Opens a folder picker and imports notes from an unzipped Diarly export.
  func importFromDiarly() {
    let panel = NSOpenPanel()
    panel.title = "Select Diarly Export Folder"
    panel.message = "Choose the unzipped Diarly export folder (e.g. Export)"
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false

    guard panel.runModal() == .OK, let folderURL = panel.url else { return }

    let existingIDs = Set(notes.map(\.id))

    do {
      let result = try DiarlyImporter.importNotes(
        from: folderURL, existingNoteIDs: existingIDs, calendar: calendar)

      for note in result.imported {
        try save(note)
      }

      notes = (notes + result.imported).sorted(by: { $0.date > $1.date })
      rebuildNoteIndex()

      if result.imported.isEmpty && result.skipped > 0 {
        userMessage = (
          text: "No new notes imported. \(result.skipped) dates already exist in Scéal.",
          kind: .info
        )
      } else if result.imported.isEmpty {
        userMessage = (text: "No Diarly notes found in the selected folder.", kind: .info)
      } else {
        var details: [String] = []
        if result.skipped > 0 { details.append("\(result.skipped) skipped") }
        if result.merged > 0 { details.append("\(result.merged) same-day entries merged") }
        let suffix = details.isEmpty ? "" : " (\(details.joined(separator: ", ")))"
        userMessage = (text: "Imported \(result.imported.count) notes.\(suffix)", kind: .info)
        selectedNoteID = result.imported.first?.id
      }
    } catch {
      report(error, context: "Importing from Diarly failed")
    }
  }

  // Exports notes within a date range to a zip file at a user-chosen location.
  func exportNotes(startDate: Date, endDate: Date) {
    flushPendingSaves()

    let filtered = notes.filter { note in
      let noteDay = calendar.startOfDay(for: note.date)
      return noteDay >= calendar.startOfDay(for: startDate)
        && noteDay <= calendar.startOfDay(for: endDate)
    }

    guard !filtered.isEmpty else {
      userMessage = (text: "No notes found in the selected date range.", kind: .info)
      return
    }

    let panel = NSSavePanel()
    panel.title = "Export Notes"
    panel.nameFieldStringValue = "sceal-export.zip"
    panel.allowedContentTypes = [.zip]

    guard panel.runModal() == .OK, let saveURL = panel.url else { return }

    let fm = fileManager
    let noteCount = filtered.count
    // Run the heavy export (file staging + ditto zip) off the main actor.
    Task.detached { [weak self] in
      do {
        let zipURL = try ScealExporter.exportNotes(filtered)

        if fm.fileExists(atPath: saveURL.path) {
          try fm.removeItem(at: saveURL)
        }
        try fm.moveItem(at: zipURL, to: saveURL)

        ScealExporter.cleanUp(zipURL: zipURL)
        await MainActor.run {
          self?.userMessage = (text: "Exported \(noteCount) notes.", kind: .info)
        }
      } catch {
        await MainActor.run {
          self?.report(error, context: "Exporting notes failed")
        }
      }
    }
  }

  // Opens a folder picker and imports notes from an unzipped Scéal export.
  func importFromSceal() {
    let panel = NSOpenPanel()
    panel.title = "Select Scéal Export Folder"
    panel.message = "Choose the unzipped Scéal export folder"
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false

    guard panel.runModal() == .OK, let folderURL = panel.url else { return }

    let existingIDs = Set(notes.map(\.id))

    do {
      let result = try ScealImporter.importNotes(
        from: folderURL, existingNoteIDs: existingIDs)

      for note in result.imported {
        try save(note)
      }

      notes = (notes + result.imported).sorted(by: { $0.date > $1.date })
      rebuildNoteIndex()

      if result.imported.isEmpty && result.skipped > 0 {
        userMessage = (
          text: "No new notes imported. \(result.skipped) dates already exist in Scéal.",
          kind: .info
        )
      } else if result.imported.isEmpty {
        userMessage = (text: "No Scéal notes found in the selected folder.", kind: .info)
      } else {
        var details: [String] = []
        if result.skipped > 0 { details.append("\(result.skipped) skipped") }
        if result.failed > 0 { details.append("\(result.failed) failed to parse") }
        let suffix = details.isEmpty ? "" : " (\(details.joined(separator: ", ")))"
        userMessage = (text: "Imported \(result.imported.count) notes.\(suffix)", kind: .info)
        selectedNoteID = result.imported.first?.id
      }
    } catch {
      report(error, context: "Importing from Scéal failed")
    }
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

  func titleBinding(for noteID: DayNote.ID) -> Binding<String> {
    Binding(
      get: { self.note(withID: noteID)?.title ?? "" },
      set: { self.updateTitle($0, for: noteID) }
    )
  }

  func tagsBinding(for noteID: DayNote.ID) -> Binding<String> {
    Binding(
      get: { self.note(withID: noteID)?.tags.joined(separator: ", ") ?? "" },
      set: { self.updateTags($0, for: noteID) }
    )
  }

  func bodyBinding(for noteID: DayNote.ID) -> Binding<String> {
    Binding(
      get: { self.note(withID: noteID)?.body ?? "" },
      set: { self.updateBody($0, for: noteID) }
    )
  }

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

  private func loadNote(from fileURL: URL) throws -> DayNote {
    let contents = try String(contentsOf: fileURL, encoding: .utf8)
    return try MarkdownNoteFile.decode(contents: contents, sourceURL: fileURL)
  }

  private func updateTitle(_ title: String, for noteID: DayNote.ID) {
    update(noteID: noteID) { note in
      note.title = title
    }
  }

  private func updateTags(_ rawTags: String, for noteID: DayNote.ID) {
    update(noteID: noteID) { note in
      note.tags = normalizedTags(from: rawTags)
    }
  }

  private func updateBody(_ body: String, for noteID: DayNote.ID) {
    update(noteID: noteID) { note in
      note.body = body
    }
  }

  private func updateAppearanceSettings(_ mutate: (inout NoteAppearanceSettings) -> Void) {
    var updatedSettings = appearanceSettings
    mutate(&updatedSettings)
    appearanceSettings = updatedSettings.clamped
    persistAppearanceSettings()
  }

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

  private func save(_ note: DayNote) throws {
    let noteURL = try notesDirectoryURL().appendingPathComponent(note.fileName)
    let fileContents = try MarkdownNoteFile.encode(note)
    try fileContents.write(to: noteURL, atomically: true, encoding: .utf8)
  }

  private func deleteFile(for note: DayNote) throws {
    let noteURL = try notesDirectoryURL().appendingPathComponent(note.fileName)

    guard fileManager.fileExists(atPath: noteURL.path) else {
      return
    }

    try fileManager.removeItem(at: noteURL)
  }

  private func persistAppearanceSettings() {
    do {
      let data = try JSONEncoder().encode(appearanceSettings)
      userDefaults.set(data, forKey: Self.appearanceSettingsDefaultsKey)
    } catch {
      report(error, context: "Saving appearance settings failed")
    }
  }

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

  private static func loadNewNoteDefault(from userDefaults: UserDefaults) -> NewNoteDefault {
    guard
      let rawValue = userDefaults.string(forKey: newNoteDefaultKey),
      let value = NewNoteDefault(rawValue: rawValue)
    else {
      return .blank
    }

    return value
  }

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

  private func dayID(for date: Date) -> DayNote.ID {
    ScealDateFormatters.storageDate.string(from: calendar.startOfDay(for: date))
  }

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

  private func rebuildNoteIndex() {
    noteIndex = Dictionary(uniqueKeysWithValues: notes.enumerated().map { ($1.id, $0) })
  }

  private func report(_ error: Error, context: String) {
    let message =
      error.localizedDescription.isEmpty ? String(describing: error) : error.localizedDescription
    Self.logger.error("\(context): \(message)")
    userMessage = (text: "\(context). \(message)", kind: .error)
  }
}
