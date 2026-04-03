//
//  DiarlyImporter.swift
//
//

// Parses an unzipped Diarly export folder into DayNote objects.

import Foundation
import OSLog

// Parses an unzipped Diarly export folder into DayNote objects.
enum DiarlyImporter {
  private static let logger = Logger(subsystem: "com.sceal.app", category: "import")

  struct ImportResult {
    let imported: [DayNote]
    let skipped: Int
    let merged: Int
  }

  // Parsed entry before merging — multiple entries can share the same date.
  private struct RawEntry {
    let date: Date
    let noteID: DayNote.ID
    let title: String
    let body: String
  }

  // Walks a Diarly export folder and returns parsed notes, skipping dates that already exist.
  // Same-day entries are merged into a single note separated by a horizontal rule.
  static func importNotes(
    from folderURL: URL,
    existingNoteIDs: Set<DayNote.ID>,
    calendar: Calendar = .current
  ) throws -> ImportResult {
    let fileManager = FileManager.default
    var entries: [RawEntry] = []
    var skippedIDs = Set<DayNote.ID>()

    // Scan for workspace directories (e.g. "work")
    let workspaceURLs = try fileManager.contentsOfDirectory(
      at: folderURL,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    ).filter { isDirectory($0) }

    for workspaceURL in workspaceURLs {
      // Scan for year directories (e.g. "2026")
      let yearURLs = try fileManager.contentsOfDirectory(
        at: workspaceURL,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      ).filter { isDirectory($0) && isYearFolder($0) }

      for yearURL in yearURLs {
        guard let year = Int(yearURL.lastPathComponent) else { continue }

        let noteFiles = try fileManager.contentsOfDirectory(
          at: yearURL,
          includingPropertiesForKeys: nil,
          options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "md" }

        for noteFileURL in noteFiles {
          guard let date = parseDate(from: noteFileURL, year: year, calendar: calendar) else {
            continue
          }

          let noteID = ScealDateFormatters.storageDate.string(from: date)
          if existingNoteIDs.contains(noteID) {
            skippedIDs.insert(noteID)
            continue
          }

          let contents = try String(contentsOf: noteFileURL, encoding: .utf8)
          let (title, body) = extractTitleAndBody(from: contents)
          entries.append(RawEntry(date: date, noteID: noteID, title: title, body: body))
        }
      }
    }

    // Group by date and merge same-day entries into a single note.
    let grouped = Dictionary(grouping: entries, by: \.noteID)
    var imported: [DayNote] = []
    var mergedCount = 0

    for (_, dayEntries) in grouped {
      guard let first = dayEntries.first else { continue }

      if dayEntries.count == 1 {
        imported.append(DayNote(date: first.date, title: first.title, tags: [], body: first.body))
      } else {
        // Use the longest title; combine bodies with a horizontal rule separator.
        let title = dayEntries.max(by: { $0.title.count < $1.title.count })?.title ?? first.title
        let combinedBody = dayEntries.map(\.body).filter { !$0.isEmpty }.joined(separator: "\n\n---\n\n")
        imported.append(DayNote(date: first.date, title: title, tags: [], body: combinedBody))
        mergedCount += dayEntries.count - 1
      }
    }

    logger.info(
      "Diarly import: \(imported.count) imported, \(skippedIDs.count) skipped, \(mergedCount) merged")
    return ImportResult(
      imported: imported.sorted(by: { $0.date > $1.date }),
      skipped: skippedIDs.count,
      merged: mergedCount
    )
  }

  // MARK: - Parsing Helpers

  // Derives a date from a Diarly note path like `.../2026/03-27.md`.
  private static func parseDate(from fileURL: URL, year: Int, calendar: Calendar) -> Date? {
    let filename = fileURL.deletingPathExtension().lastPathComponent
    let parts = filename.split(separator: "-")
    guard parts.count == 2,
      let month = Int(parts[0]),
      let day = Int(parts[1]),
      (1...12).contains(month),
      (1...31).contains(day)
    else {
      return nil
    }

    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day

    guard let date = calendar.date(from: components),
      calendar.component(.month, from: date) == month,
      calendar.component(.day, from: date) == day
    else { return nil }
    return calendar.startOfDay(for: date)
  }

  // Splits file contents into title (first line) and body (remaining content).
  private static func extractTitleAndBody(from contents: String) -> (title: String, body: String) {
    let lines = contents.split(separator: "\n", omittingEmptySubsequences: false)

    guard let firstLine = lines.first else {
      return ("", "")
    }

    var title = String(firstLine).trimmingCharacters(in: .whitespaces)

    // Strip leading `# ` heading prefix if present
    if title.hasPrefix("# ") {
      title = String(title.dropFirst(2)).trimmingCharacters(in: .whitespaces)
    }

    // Body is everything after the first line, with leading blank lines trimmed
    let remainingLines = Array(lines.dropFirst())
    let bodyStartIndex = remainingLines.firstIndex(where: {
      !$0.trimmingCharacters(in: .whitespaces).isEmpty
    }) ?? remainingLines.endIndex

    let body = remainingLines[bodyStartIndex...].joined(separator: "\n")
      .trimmingCharacters(in: .newlines)

    return (title, body)
  }

  // Checks if a file URL points to a directory.
  private static func isDirectory(_ url: URL) -> Bool {
    var isDir: ObjCBool = false
    return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
  }

  // Checks if a folder name is a 4-digit year.
  private static func isYearFolder(_ url: URL) -> Bool {
    guard let year = Int(url.lastPathComponent) else { return false }
    return (2000...2100).contains(year)
  }
}
