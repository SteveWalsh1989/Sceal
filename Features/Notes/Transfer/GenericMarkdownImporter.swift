//
//  GenericMarkdownImporter.swift
//

// Imports dated Markdown files from common note apps into Scéal daily notes.

import Foundation

enum GenericMarkdownImporter {

  struct ImportResult: Sendable {
    let imported: [DayNote]
    let skipped: Int
    let merged: Int
    let missingDate: Int
    let failed: Int
  }

  private struct FrontMatter: Sendable {
    let values: [String: String]
    let tags: [String]
  }

  private struct RawEntry: Sendable {
    let date: Date
    let noteID: DayNote.ID
    let title: String
    let tags: [String]
    let body: String
    let sourcePath: String
  }

  private struct ParsedMarkdown: Sendable {
    let date: Date
    let title: String
    let tags: [String]
    let body: String
  }

  // Walks a Markdown folder, importing files with dates from front matter or unambiguous filenames.
  nonisolated static func importNotes(
    from folderURL: URL,
    existingNoteIDs: Set<DayNote.ID>,
    calendar: Calendar = .current
  ) throws -> ImportResult {
    let fileManager = FileManager.default
    var entries: [RawEntry] = []
    var skippedIDs = Set<DayNote.ID>()
    var missingDate = 0
    var failed = 0

    let markdownFiles = collectMarkdownFiles(in: folderURL, fileManager: fileManager)

    for fileURL in markdownFiles {
      do {
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        guard let parsed = parseMarkdown(contents, sourceURL: fileURL, calendar: calendar) else {
          missingDate += 1
          continue
        }

        let noteID = NoteDateFormatters.storageDate.string(from: parsed.date)
        if existingNoteIDs.contains(noteID) {
          skippedIDs.insert(noteID)
          continue
        }

        entries.append(
          RawEntry(
            date: parsed.date,
            noteID: noteID,
            title: parsed.title,
            tags: parsed.tags,
            body: parsed.body,
            sourcePath: fileURL.standardizedFileURL.path
          )
        )
      } catch {
        failed += 1
      }
    }

    let (imported, merged) = mergeEntries(entries)
    return ImportResult(
      imported: imported.sorted(by: { $0.date > $1.date }),
      skipped: skippedIDs.count,
      merged: merged,
      missingDate: missingDate,
      failed: failed
    )
  }

  // MARK: - File Collection

  // Recursively collects Markdown files while ignoring hidden files and folders.
  nonisolated private static func collectMarkdownFiles(
    in directoryURL: URL,
    fileManager: FileManager
  ) -> [URL] {
    guard
      let enumerator = fileManager.enumerator(
        at: directoryURL,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
      )
    else {
      return []
    }

    var results: [URL] = []

    for case let fileURL as URL in enumerator {
      guard isMarkdownFile(fileURL) else { continue }
      results.append(fileURL)
    }

    return results.sorted(by: { $0.standardizedFileURL.path < $1.standardizedFileURL.path })
  }

  // Accepts the common Markdown extensions used by note-taking apps.
  nonisolated private static func isMarkdownFile(_ url: URL) -> Bool {
    let pathExtension = url.pathExtension.lowercased()
    return pathExtension == "md" || pathExtension == "markdown"
  }

  // MARK: - Parsing

  // Parses one Markdown file, requiring a trustworthy date from metadata or the file path.
  nonisolated private static func parseMarkdown(
    _ rawContents: String,
    sourceURL: URL,
    calendar: Calendar
  ) -> ParsedMarkdown? {
    let contents =
      rawContents
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
    let (frontMatter, markdownBody) = extractFrontMatter(from: contents)

    guard
      let date = dateFromFrontMatter(frontMatter, calendar: calendar)
        ?? dateFromPath(sourceURL, calendar: calendar)
    else {
      return nil
    }

    let titleAndBody = extractTitleAndBody(
      from: markdownBody,
      frontMatter: frontMatter,
      sourceURL: sourceURL
    )

    return ParsedMarkdown(
      date: date,
      title: titleAndBody.title,
      tags: frontMatter?.tags ?? [],
      body: titleAndBody.body
    )
  }

  // Splits an optional YAML-style front matter block from the Markdown body.
  nonisolated private static func extractFrontMatter(from contents: String) -> (
    frontMatter: FrontMatter?,
    body: String
  ) {
    let marker = "---"
    let prefix = "\(marker)\n"

    guard contents.hasPrefix(prefix) else {
      return (nil, contents)
    }

    let metadataStart = contents.index(contents.startIndex, offsetBy: prefix.count)
    guard let metadataEnd = contents[metadataStart...].range(of: "\n\(marker)\n") else {
      return (nil, contents)
    }

    let metadataBlock = String(contents[metadataStart..<metadataEnd.lowerBound])
    let body = String(contents[metadataEnd.upperBound...])
    return (parseFrontMatterBlock(metadataBlock), body)
  }

  // Parses the small front matter subset exported by apps such as Joplin.
  nonisolated private static func parseFrontMatterBlock(_ block: String) -> FrontMatter {
    var values: [String: String] = [:]
    var tags: [String] = []
    var currentListKey: String?

    for rawLine in block.split(separator: "\n", omittingEmptySubsequences: false) {
      let line = String(rawLine)
      let trimmed = line.trimmingCharacters(in: .whitespaces)

      guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else {
        continue
      }

      if trimmed.hasPrefix("- "), currentListKey == "tags" {
        tags.append(contentsOf: parseTagValue(String(trimmed.dropFirst(2))))
        continue
      }

      currentListKey = nil

      guard let separatorIndex = line.firstIndex(of: ":") else {
        continue
      }

      let key = line[..<separatorIndex]
        .trimmingCharacters(in: .whitespaces)
        .lowercased()
      let valueStart = line.index(after: separatorIndex)
      let value = String(line[valueStart...]).trimmingCharacters(in: .whitespaces)

      guard !key.isEmpty else {
        continue
      }

      if value.isEmpty {
        currentListKey = key
        continue
      }

      values[key] = trimmedScalar(value)
      if key == "tags" {
        tags.append(contentsOf: parseTagValue(value))
      }
    }

    return FrontMatter(values: values, tags: uniqueTags(tags))
  }

  // MARK: - Date Detection

  // Reads date metadata from common front matter keys.
  nonisolated private static func dateFromFrontMatter(
    _ frontMatter: FrontMatter?,
    calendar: Calendar
  ) -> Date? {
    guard let values = frontMatter?.values else {
      return nil
    }

    let dateKeys = [
      "date",
      "created",
      "created_at",
      "created at",
      "creationdate",
      "creation_date",
      "created time",
    ]

    for key in dateKeys {
      guard let value = values[key],
        let components = dateComponents(in: value)
      else {
        continue
      }

      return date(from: components, calendar: calendar)
    }

    return nil
  }

  // Reads date metadata from common daily-note filenames such as 2026-05-03.md.
  nonisolated private static func dateFromPath(_ sourceURL: URL, calendar: Calendar) -> Date? {
    let filename = sourceURL.deletingPathExtension().lastPathComponent

    if let components = dateComponents(in: filename),
      let date = date(from: components, calendar: calendar)
    {
      return date
    }

    if let year = Int(sourceURL.deletingLastPathComponent().lastPathComponent),
      let monthDay = monthDayComponents(in: filename)
    {
      return date(
        from: DateComponents(year: year, month: monthDay.month, day: monthDay.day),
        calendar: calendar
      )
    }

    return nil
  }

  // Finds the first unambiguous year-month-day pattern in a string.
  nonisolated private static func dateComponents(in value: String) -> DateComponents? {
    let patterns = [
      #"(?<!\d)(\d{4})[-_./](\d{1,2})[-_./](\d{1,2})(?!\d)"#,
      #"(?<!\d)(\d{4})(\d{2})(\d{2})(?!\d)"#,
    ]

    for pattern in patterns {
      guard let groups = captureGroups(in: value, pattern: pattern),
        groups.count == 3,
        let year = Int(groups[0]),
        let month = Int(groups[1]),
        let day = Int(groups[2])
      else {
        continue
      }

      return DateComponents(year: year, month: month, day: day)
    }

    return nil
  }

  // Finds month-day filenames when the parent folder supplies the year.
  nonisolated private static func monthDayComponents(in value: String) -> (month: Int, day: Int)? {
    guard
      let groups = captureGroups(
        in: value,
        pattern: #"(?<!\d)(\d{1,2})[-_.](\d{1,2})(?!\d)"#
      ),
      groups.count == 2,
      let month = Int(groups[0]),
      let day = Int(groups[1])
    else {
      return nil
    }

    return (month, day)
  }

  // Builds a valid start-of-day date from parsed components.
  nonisolated private static func date(from components: DateComponents, calendar: Calendar) -> Date?
  {
    guard
      let year = components.year,
      let month = components.month,
      let day = components.day,
      (1900...2100).contains(year),
      (1...12).contains(month),
      (1...31).contains(day)
    else {
      return nil
    }

    var resolvedComponents = DateComponents()
    resolvedComponents.calendar = calendar
    resolvedComponents.year = year
    resolvedComponents.month = month
    resolvedComponents.day = day

    guard let date = calendar.date(from: resolvedComponents),
      calendar.component(.year, from: date) == year,
      calendar.component(.month, from: date) == month,
      calendar.component(.day, from: date) == day
    else {
      return nil
    }

    return calendar.startOfDay(for: date)
  }

  // MARK: - Content Normalization

  // Chooses a Scéal title and removes a leading H1 when it clearly acts as the note title.
  nonisolated private static func extractTitleAndBody(
    from body: String,
    frontMatter: FrontMatter?,
    sourceURL: URL
  ) -> (title: String, body: String) {
    if let frontMatterTitle = frontMatter?.values["title"],
      !frontMatterTitle.isEmpty
    {
      return (frontMatterTitle, body.trimmingCharacters(in: .newlines))
    }

    let lines = body.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
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
        let remainingBody = remainingLines[bodyStartIndex...].joined(separator: "\n")
        return (title, remainingBody.trimmingCharacters(in: .newlines))
      }
    }

    return (titleFromFilename(sourceURL), body.trimmingCharacters(in: .newlines))
  }

  // Derives a readable title from filename text that remains after removing a leading date.
  nonisolated private static func titleFromFilename(_ sourceURL: URL) -> String {
    let filename = sourceURL.deletingPathExtension().lastPathComponent
    let datePrefixPatterns = [
      #"^\d{4}[-_./]\d{1,2}[-_./]\d{1,2}"#,
      #"^\d{8}"#,
      #"^\d{1,2}[-_.]\d{1,2}"#,
    ]

    var title = filename
    for pattern in datePrefixPatterns {
      title = title.replacingOccurrences(
        of: pattern,
        with: "",
        options: .regularExpression
      )
    }

    return
      title
      .trimmingCharacters(in: CharacterSet(charactersIn: " -_."))
      .replacingOccurrences(of: "_", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  // MARK: - Merge Helpers

  // Merges multiple Markdown files for the same date into Scéal's one-note-per-day shape.
  nonisolated private static func mergeEntries(_ entries: [RawEntry]) -> (
    imported: [DayNote],
    merged: Int
  ) {
    let grouped = Dictionary(grouping: entries, by: \.noteID)
    var imported: [DayNote] = []
    var merged = 0

    for (_, dayEntries) in grouped {
      let sortedEntries = dayEntries.sorted(by: { $0.sourcePath < $1.sourcePath })
      guard let first = sortedEntries.first else {
        continue
      }

      let title = bestTitle(in: sortedEntries)
      let tags = mergedTags(from: sortedEntries)

      if sortedEntries.count == 1 {
        imported.append(
          DayNote(date: first.date, title: title, tags: tags, body: first.body)
        )
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

  // Prefers the longest non-empty title when multiple files share one date.
  nonisolated private static func bestTitle(in entries: [RawEntry]) -> String {
    entries
      .map(\.title)
      .filter { !$0.isEmpty }
      .max(by: { $0.count < $1.count }) ?? ""
  }

  // Preserves per-file titles inside merged daily note bodies.
  nonisolated private static func mergedBodySection(for entry: RawEntry) -> String {
    guard !entry.title.isEmpty else {
      return entry.body
    }

    if entry.body.isEmpty {
      return "## \(entry.title)"
    }

    return "## \(entry.title)\n\n\(entry.body)"
  }

  // Keeps tag order stable while removing duplicates across same-day files.
  nonisolated private static func mergedTags(from entries: [RawEntry]) -> [String] {
    uniqueTags(entries.flatMap(\.tags))
  }

  // MARK: - Scalar Helpers

  // Extracts regex capture groups from a string.
  nonisolated private static func captureGroups(in value: String, pattern: String) -> [String]? {
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return nil
    }

    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    guard let match = regex.firstMatch(in: value, range: range) else {
      return nil
    }

    return (1..<match.numberOfRanges).compactMap { index in
      let range = match.range(at: index)
      guard let swiftRange = Range(range, in: value) else {
        return nil
      }

      return String(value[swiftRange])
    }
  }

  // Parses front matter tag values from scalar, inline-array, or block-list entries.
  nonisolated private static func parseTagValue(_ value: String) -> [String] {
    let trimmed = trimmedScalar(value)
    let unwrapped =
      trimmed.hasPrefix("[") && trimmed.hasSuffix("]")
      ? String(trimmed.dropFirst().dropLast())
      : trimmed

    return
      unwrapped
      .split(separator: ",", omittingEmptySubsequences: true)
      .map { trimmedScalar(String($0)).trimmingCharacters(in: CharacterSet(charactersIn: "#")) }
      .filter { !$0.isEmpty }
  }

  // Removes lightweight YAML scalar wrapping without attempting full YAML parsing.
  nonisolated private static func trimmedScalar(_ value: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

    if trimmed.count >= 2,
      let first = trimmed.first,
      let last = trimmed.last,
      (first == "\"" && last == "\"") || (first == "'" && last == "'")
    {
      return String(trimmed.dropFirst().dropLast())
    }

    return trimmed
  }

  // Removes duplicate tags without losing the source order.
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
