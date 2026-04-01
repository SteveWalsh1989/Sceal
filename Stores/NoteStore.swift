//
//  NoteStore.swift
//  dayra
//
//

import Combine
import Foundation
import SwiftUI

struct NoteMonthSection: Identifiable, Equatable {
  let monthStartDate: Date
  let notes: [DayNote]

  var id: String {
    DayraDateFormatters.storageDate.string(from: monthStartDate)
  }

  var title: String {
    DayraDateFormatters.monthDivider.string(from: monthStartDate).uppercased()
  }
}

@MainActor
final class NoteStore: ObservableObject {
  @Published private(set) var notes: [DayNote]
  @Published var selectedNoteID: DayNote.ID?
  @Published private(set) var isLoading = false
  @Published var errorMessage: String?

  private let fileManager: FileManager
  private let calendar: Calendar
  private var hasLoaded = false
  private var pendingSaveTasks: [DayNote.ID: Task<Void, Never>] = [:]

  init(
    fileManager: FileManager = .default,
    calendar: Calendar = .current,
    previewNotes: [DayNote] = []
  ) {
    self.fileManager = fileManager
    self.calendar = calendar
    self.notes = previewNotes.sorted(by: { $0.date > $1.date })
    self.selectedNoteID = previewNotes.sorted(by: { $0.date > $1.date }).first?.id
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
      errorMessage = nil
    } catch {
      report(error, context: "Loading notes failed")
      notes = [DayNote.empty(for: .now, calendar: calendar)]
      selectedNoteID = notes.first?.id

      do {
        try save(notes[0])
      } catch {
        report(error, context: "Creating today's note failed")
      }
    }

    hasLoaded = true
    isLoading = false
  }

  func selectToday() {
    do {
      try ensureTodayNoteExists()
      selectedNoteID = dayID(for: .now)
    } catch {
      report(error, context: "Opening today's note failed")
    }
  }

  func dismissError() {
    errorMessage = nil
  }

  func flushPendingSaves() {
    let noteIDs = Array(pendingSaveTasks.keys)

    for noteID in noteIDs {
      pendingSaveTasks[noteID]?.cancel()
      pendingSaveTasks[noteID] = nil
      persistPendingSave(for: noteID)
    }
  }

  func note(withID noteID: DayNote.ID) -> DayNote? {
    notes.first(where: { $0.id == noteID })
  }

  func select(noteID: DayNote.ID) {
    selectedNoteID = noteID
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

    notes = loadedNotes

    try ensureTodayNoteExists()

    let todayID = dayID(for: .now)
    selectedNoteID = note(withID: todayID) == nil ? notes.first?.id : todayID
  }

  private func ensureTodayNoteExists() throws {
    let todayID = dayID(for: .now)
    guard note(withID: todayID) == nil else {
      return
    }

    let todayNote = DayNote.empty(for: .now, calendar: calendar)
    notes = ([todayNote] + notes).sorted(by: { $0.date > $1.date })
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

  private func update(noteID: DayNote.ID, mutate: (inout DayNote) -> Void) {
    guard let index = notes.firstIndex(where: { $0.id == noteID }) else {
      return
    }

    var updatedNotes = notes
    mutate(&updatedNotes[index])
    notes = updatedNotes
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

  private func save(_ note: DayNote) throws {
    let noteURL = try notesDirectoryURL().appendingPathComponent(note.fileName)
    let fileContents = try MarkdownNoteFile.encode(note)
    try fileContents.write(to: noteURL, atomically: true, encoding: .utf8)
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
      .appendingPathComponent("dayra", isDirectory: true)
      .appendingPathComponent("Notes", isDirectory: true)

    try fileManager.createDirectory(
      at: notesDirectoryURL,
      withIntermediateDirectories: true
    )

    return notesDirectoryURL
  }

  private func dayID(for date: Date) -> DayNote.ID {
    DayraDateFormatters.storageDate.string(from: calendar.startOfDay(for: date))
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

  private func report(_ error: Error, context: String) {
    let message =
      error.localizedDescription.isEmpty ? String(describing: error) : error.localizedDescription
    errorMessage = "\(context). \(message)"
  }
}
