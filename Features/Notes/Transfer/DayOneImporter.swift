//
//  DayOneImporter.swift
//

// Imports Day One JSON exports into Scéal daily notes.

import Foundation
import OSLog

nonisolated enum DayOneImporter {
  nonisolated private static let logger = Logger(subsystem: "com.sceal.app", category: "import")

  struct ImportResult: Sendable {
    let imported: [DayNote]
    let skipped: Int
    let merged: Int
    let failed: Int
    let missingTimeZone: Int
    let omittedPhotos: Int
    let omittedVideos: Int
    let omittedAudios: Int
    let omittedPDFs: Int

    var omittedMediaTotal: Int {
      omittedPhotos + omittedVideos + omittedAudios + omittedPDFs
    }
  }

  private struct JSONSource: Sendable {
    let url: URL
    let cleanupDirectoryURL: URL?
    let extraFailureCount: Int
  }

  private struct RawEntry: Sendable {
    let date: Date
    let noteID: DayNote.ID
    let title: String
    let tags: [String]
    let body: String
    let sortDate: Date
    let uuid: String
  }

  private struct ParsedEntry: Sendable {
    let entry: RawEntry
    let missingTimeZone: Bool
    let mediaCounts: MediaCounts
  }

  private struct MediaCounts: Sendable {
    var photos: Int = 0
    var videos: Int = 0
    var audios: Int = 0
    var pdfs: Int = 0

    var total: Int {
      photos + videos + audios + pdfs
    }

    mutating func add(_ other: MediaCounts) {
      photos += other.photos
      videos += other.videos
      audios += other.audios
      pdfs += other.pdfs
    }
  }

  private struct DayOneArchive: Decodable {
    let entries: [EntryDecodeResult]

    private enum CodingKeys: String, CodingKey {
      case entries
      case metadata
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      _ = try? container.decodeIfPresent(DayOneMetadata.self, forKey: .metadata)

      var entriesContainer = try container.nestedUnkeyedContainer(forKey: .entries)
      var decodedEntries: [EntryDecodeResult] = []

      while !entriesContainer.isAtEnd {
        do {
          decodedEntries.append(.success(try entriesContainer.decode(DayOneEntry.self)))
        } catch {
          _ = try? entriesContainer.decode(DiscardedJSONValue.self)
          decodedEntries.append(.failure)
        }
      }

      entries = decodedEntries
    }
  }

  private struct DayOneMetadata: Decodable {
    let version: String?
  }

  private enum EntryDecodeResult {
    case success(DayOneEntry)
    case failure
  }

  private struct DayOneEntry: Decodable, Sendable {
    let uuid: String?
    let creationDate: String?
    let timeZone: String?
    let text: String?
    let tags: [String]
    let photos: [DayOneMedia]
    let videos: [DayOneMedia]
    let audios: [DayOneMedia]
    let pdfs: [DayOneMedia]

    private enum CodingKeys: String, CodingKey {
      case uuid
      case creationDate
      case timeZone
      case text
      case tags
      case photos
      case videos
      case audios
      case pdfs
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      uuid = try? container.decodeIfPresent(String.self, forKey: .uuid)
      creationDate = try? container.decodeIfPresent(String.self, forKey: .creationDate)
      timeZone = try? container.decodeIfPresent(String.self, forKey: .timeZone)
      text = try? container.decodeIfPresent(String.self, forKey: .text)
      tags = (try? container.decodeIfPresent([String].self, forKey: .tags)) ?? []
      photos = (try? container.decodeIfPresent([DayOneMedia].self, forKey: .photos)) ?? []
      videos = (try? container.decodeIfPresent([DayOneMedia].self, forKey: .videos)) ?? []
      audios = (try? container.decodeIfPresent([DayOneMedia].self, forKey: .audios)) ?? []
      pdfs = (try? container.decodeIfPresent([DayOneMedia].self, forKey: .pdfs)) ?? []
    }
  }

  private struct DayOneMedia: Decodable, Sendable {}

  private struct DiscardedJSONValue: Decodable {
    init(from decoder: Decoder) throws {
      if let unkeyedContainer = try? decoder.unkeyedContainer() {
        var container = unkeyedContainer
        while !container.isAtEnd {
          _ = try? container.decode(DiscardedJSONValue.self)
        }
        return
      }

      if let keyedContainer = try? decoder.container(keyedBy: AnyCodingKey.self) {
        for key in keyedContainer.allKeys {
          _ = try? keyedContainer.decode(DiscardedJSONValue.self, forKey: key)
        }
        return
      }

      let singleValueContainer = try decoder.singleValueContainer()
      if singleValueContainer.decodeNil() { return }
      if (try? singleValueContainer.decode(Bool.self)) != nil { return }
      if (try? singleValueContainer.decode(Double.self)) != nil { return }
      _ = try? singleValueContainer.decode(String.self)
    }
  }

  private struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
      self.stringValue = stringValue
      intValue = nil
    }

    init?(intValue: Int) {
      stringValue = "\(intValue)"
      self.intValue = intValue
    }
  }

  // Imports a Day One JSON export from either a .zip export or a raw .json file.
  nonisolated static func importNotes(
    from sourceURL: URL,
    existingNoteIDs: Set<DayNote.ID>,
    calendar: Calendar = .current
  ) throws -> ImportResult {
    let jsonSource = try resolveJSONSource(from: sourceURL)
    defer {
      if let cleanupDirectoryURL = jsonSource.cleanupDirectoryURL {
        try? FileManager.default.removeItem(at: cleanupDirectoryURL)
      }
    }

    let data = try Data(contentsOf: jsonSource.url)
    let archive = try JSONDecoder().decode(DayOneArchive.self, from: data)

    var entries: [RawEntry] = []
    var skippedIDs = Set<DayNote.ID>()
    var failed = jsonSource.extraFailureCount
    var missingTimeZone = 0
    var mediaCounts = MediaCounts()

    for result in archive.entries {
      switch result {
      case .success(let entry):
        guard let parsed = parseEntry(entry, calendar: calendar) else {
          failed += 1
          continue
        }

        if parsed.missingTimeZone {
          missingTimeZone += 1
        }
        mediaCounts.add(parsed.mediaCounts)

        if existingNoteIDs.contains(parsed.entry.noteID) {
          skippedIDs.insert(parsed.entry.noteID)
          continue
        }

        entries.append(parsed.entry)
      case .failure:
        failed += 1
      }
    }

    let (imported, merged) = mergeEntries(entries)
    logger.info(
      "Day One import: \(imported.count) imported, \(skippedIDs.count) skipped, \(merged) merged, \(failed) failed"
    )

    return ImportResult(
      imported: imported.sorted(by: { $0.date > $1.date }),
      skipped: skippedIDs.count,
      merged: merged,
      failed: failed,
      missingTimeZone: missingTimeZone,
      omittedPhotos: mediaCounts.photos,
      omittedVideos: mediaCounts.videos,
      omittedAudios: mediaCounts.audios,
      omittedPDFs: mediaCounts.pdfs
    )
  }

  // MARK: - Source Resolution

  // Resolves the selected Day One export to the JSON file that should be parsed.
  nonisolated private static func resolveJSONSource(from sourceURL: URL) throws -> JSONSource {
    switch sourceURL.pathExtension.lowercased() {
    case "json":
      return JSONSource(url: sourceURL, cleanupDirectoryURL: nil, extraFailureCount: 0)
    case "zip":
      let extractionDirectoryURL = try extractZip(sourceURL)
      let jsonFiles = try rootJSONFiles(in: extractionDirectoryURL)

      guard let jsonURL = jsonFiles.first else {
        try? FileManager.default.removeItem(at: extractionDirectoryURL)
        throw DayOneImporterError.missingJSONFile
      }

      return JSONSource(
        url: jsonURL,
        cleanupDirectoryURL: extractionDirectoryURL,
        extraFailureCount: max(0, jsonFiles.count - 1)
      )
    default:
      throw DayOneImporterError.unsupportedFileType(sourceURL.lastPathComponent)
    }
  }

  // Extracts a zip export into a temporary directory using the system ditto tool.
  nonisolated private static func extractZip(_ zipURL: URL) throws -> URL {
    let extractionDirectoryURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("day-one-import-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: extractionDirectoryURL,
      withIntermediateDirectories: true
    )

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    process.arguments = ["-x", "-k", zipURL.path, extractionDirectoryURL.path]

    let errorPipe = Pipe()
    process.standardError = errorPipe

    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
      let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
      let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown zip error"
      try? FileManager.default.removeItem(at: extractionDirectoryURL)
      throw DayOneImporterError.zipExtractionFailed(errorMessage)
    }

    return extractionDirectoryURL
  }

  // Finds root-level JSON files and chooses the first sorted filename as the Day One archive.
  nonisolated private static func rootJSONFiles(in directoryURL: URL) throws -> [URL] {
    try FileManager.default.contentsOfDirectory(
      at: directoryURL,
      includingPropertiesForKeys: [.isRegularFileKey],
      options: [.skipsHiddenFiles]
    )
    .filter { $0.pathExtension.lowercased() == "json" }
    .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
  }

  // MARK: - Entry Parsing

  // Converts one Day One entry into Scéal's daily-note shape.
  nonisolated private static func parseEntry(
    _ entry: DayOneEntry,
    calendar: Calendar
  ) -> ParsedEntry? {
    guard let creationDateValue = entry.creationDate,
      let creationDate = parseISO8601Date(creationDateValue)
    else {
      return nil
    }

    let entryTimeZone = entry.timeZone.flatMap { TimeZone(identifier: $0) }
    let missingTimeZone = entryTimeZone == nil
    let noteDate = dailyNoteDate(
      from: creationDate,
      entryTimeZone: entryTimeZone ?? TimeZone(secondsFromGMT: 0)!,
      calendar: calendar
    )
    let noteID = NoteDateFormatters.storageDate.string(from: noteDate)
    let mediaCounts = MediaCounts(
      photos: entry.photos.count,
      videos: entry.videos.count,
      audios: entry.audios.count,
      pdfs: entry.pdfs.count
    )
    let titleAndBody = extractTitleAndBody(from: normalizedMarkdown(entry.text ?? ""))

    return ParsedEntry(
      entry: RawEntry(
        date: noteDate,
        noteID: noteID,
        title: titleAndBody.title,
        tags: uniqueTags(entry.tags),
        body: titleAndBody.body,
        sortDate: creationDate,
        uuid: entry.uuid ?? creationDateValue
      ),
      missingTimeZone: missingTimeZone,
      mediaCounts: mediaCounts
    )
  }

  // Parses Day One ISO-8601 timestamps, including optional fractional seconds.
  nonisolated private static func parseISO8601Date(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    if let date = formatter.date(from: value) {
      return date
    }

    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
  }

  // Converts the original entry instant into the calendar date the user saw in Day One.
  nonisolated private static func dailyNoteDate(
    from creationDate: Date,
    entryTimeZone: TimeZone,
    calendar: Calendar
  ) -> Date {
    var entryCalendar = calendar
    entryCalendar.timeZone = entryTimeZone

    let components = entryCalendar.dateComponents([.year, .month, .day], from: creationDate)
    guard let localDate = calendar.date(from: components) else {
      return calendar.startOfDay(for: creationDate)
    }

    return calendar.startOfDay(for: localDate)
  }

  // MARK: - Markdown Normalization

  // Removes Day One-only media markers and formatting guard characters from exported Markdown.
  nonisolated private static func normalizedMarkdown(_ text: String) -> String {
    var markdown =
      text
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")

    for marker in ["\u{200B}", "\u{200C}", "\u{200D}", "\u{FEFF}"] {
      markdown = markdown.replacingOccurrences(of: marker, with: "")
    }

    markdown = markdown.replacingOccurrences(
      of: #"!\[[^\]]*\]\(dayone-moment://[^)]+\)"#,
      with: "",
      options: .regularExpression
    )
    markdown = markdown.replacingOccurrences(
      of: #"\\([.\-!?,:;])"#,
      with: "$1",
      options: .regularExpression
    )
    markdown = markdown.replacingOccurrences(
      of: #"\n{3,}"#,
      with: "\n\n",
      options: .regularExpression
    )

    return markdown.trimmingCharacters(in: .newlines)
  }

  // Extracts a leading H1 as the Scéal title and imports the remaining text as the body.
  nonisolated private static func extractTitleAndBody(from markdown: String) -> (
    title: String,
    body: String
  ) {
    let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

    if let titleLineIndex = lines.firstIndex(where: {
      !$0.trimmingCharacters(in: .whitespaces).isEmpty
    }) {
      let line = lines[titleLineIndex].trimmingCharacters(in: .whitespaces)
      if line.hasPrefix("# "), !line.hasPrefix("## ") {
        let title = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        let remainingLines = Array(lines.dropFirst(titleLineIndex + 1))
        let bodyStartIndex =
          remainingLines.firstIndex(where: {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
          }) ?? remainingLines.endIndex
        let body = remainingLines[bodyStartIndex...].joined(separator: "\n")
        return (title, body.trimmingCharacters(in: .newlines))
      }
    }

    return ("", markdown.trimmingCharacters(in: .newlines))
  }

  // MARK: - Merge Helpers

  // Merges multiple Day One entries that belong to the same Scéal daily note.
  nonisolated private static func mergeEntries(_ entries: [RawEntry]) -> (
    imported: [DayNote],
    merged: Int
  ) {
    let grouped = Dictionary(grouping: entries, by: \.noteID)
    var imported: [DayNote] = []
    var merged = 0

    for (_, dayEntries) in grouped {
      let sortedEntries = dayEntries.sorted {
        if $0.sortDate == $1.sortDate {
          return $0.uuid < $1.uuid
        }

        return $0.sortDate < $1.sortDate
      }

      guard let first = sortedEntries.first else {
        continue
      }

      let title = bestTitle(in: sortedEntries)
      let tags = uniqueTags(sortedEntries.flatMap(\.tags))

      if sortedEntries.count == 1 {
        imported.append(DayNote(date: first.date, title: title, tags: tags, body: first.body))
        continue
      }

      let combinedBody =
        sortedEntries
        .map { mergedBodySection(for: $0) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n---\n\n")

      imported.append(DayNote(date: first.date, title: title, tags: tags, body: combinedBody))
      merged += sortedEntries.count - 1
    }

    return (imported, merged)
  }

  // Prefers the longest non-empty title when multiple entries share one date.
  nonisolated private static func bestTitle(in entries: [RawEntry]) -> String {
    entries
      .map(\.title)
      .filter { !$0.isEmpty }
      .max(by: { $0.count < $1.count }) ?? ""
  }

  // Preserves source-entry titles inside merged daily note bodies.
  nonisolated private static func mergedBodySection(for entry: RawEntry) -> String {
    guard !entry.title.isEmpty else {
      return entry.body
    }

    if entry.body.isEmpty {
      return "## \(entry.title)"
    }

    return "## \(entry.title)\n\n\(entry.body)"
  }

  // Removes duplicate tags without losing source order.
  nonisolated private static func uniqueTags(_ tags: [String]) -> [String] {
    var seen = Set<String>()
    var results: [String] = []

    for tag in tags {
      let normalized = tag.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !normalized.isEmpty, !seen.contains(normalized) else {
        continue
      }

      seen.insert(normalized)
      results.append(normalized)
    }

    return results
  }
}

enum DayOneImporterError: LocalizedError {
  case unsupportedFileType(String)
  case missingJSONFile
  case zipExtractionFailed(String)

  var errorDescription: String? {
    switch self {
    case .unsupportedFileType(let fileName):
      return "Day One import supports .zip and .json files. \(fileName) is not supported."
    case .missingJSONFile:
      return "The Day One export did not contain a root JSON file."
    case .zipExtractionFailed(let detail):
      return "Failed to extract the Day One zip export. \(detail)"
    }
  }
}
