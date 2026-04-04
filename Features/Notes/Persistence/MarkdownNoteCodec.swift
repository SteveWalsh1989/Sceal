//
//  MarkdownNoteCodec.swift
//
//

// Encodes and decodes notes as markdown files with JSON front matter for title and tags.

import Foundation
import OSLog

enum MarkdownNoteCodec {
  private static let logger = Logger(subsystem: "com.sceal.app", category: "persistence")
  private static let frontMatterMarker = "---"

  // Serializes a note to markdown with a JSON front-matter header.
  static func encode(_ note: DayNote) throws -> String {
    let titleValue = try jsonEncoded(note.title)
    let tagsValue = try jsonEncoded(note.tags)

    return """
      \(frontMatterMarker)
      date: \(NoteDateFormatters.storageDate.string(from: note.date))
      title: \(titleValue)
      tags: \(tagsValue)
      \(frontMatterMarker)
      \(note.body)
      """
  }

  // Parses markdown file contents into a DayNote, extracting front matter.
  static func decode(contents: String, sourceURL: URL) throws -> DayNote {
    let contents = contents.replacingOccurrences(of: "\r\n", with: "\n")
    let prefix = "\(frontMatterMarker)\n"
    guard contents.hasPrefix(prefix) else {
      logger.error("Missing front matter in \(sourceURL.lastPathComponent)")
      throw MarkdownNoteCodecError.missingFrontMatter(sourceURL)
    }

    let metadataStart = contents.index(contents.startIndex, offsetBy: prefix.count)
    guard let metadataEnd = contents[metadataStart...].range(of: "\n\(frontMatterMarker)\n") else {
      logger.error("Invalid front matter in \(sourceURL.lastPathComponent)")
      throw MarkdownNoteCodecError.invalidFrontMatter(sourceURL)
    }

    let metadataBlock = String(contents[metadataStart..<metadataEnd.lowerBound])
    let body = String(contents[metadataEnd.upperBound...])
    let metadata = try parseMetadataBlock(metadataBlock, sourceURL: sourceURL)

    guard
      let dateValue = metadata["date"],
      let date = NoteDateFormatters.storageDate.date(from: dateValue)
    else {
      logger.error("Invalid date in \(sourceURL.lastPathComponent)")
      throw MarkdownNoteCodecError.invalidDate(sourceURL)
    }

    let title = try decodeJSONString(metadata["title"], sourceURL: sourceURL)
    let tags = try decodeJSONTags(metadata["tags"], sourceURL: sourceURL)

    return DayNote(
      date: date,
      title: title,
      tags: tags,
      body: body
    )
  }

  // Extracts title and tags from the `---` delimited front-matter block.
  private static func parseMetadataBlock(_ block: String, sourceURL: URL) throws -> [String: String]
  {
    var metadata: [String: String] = [:]

    for rawLine in block.split(separator: "\n", omittingEmptySubsequences: false) {
      guard let separatorIndex = rawLine.firstIndex(of: ":") else {
        throw MarkdownNoteCodecError.invalidFrontMatter(sourceURL)
      }

      let key = rawLine[..<separatorIndex].trimmingCharacters(in: .whitespaces)
      let valueStart = rawLine.index(after: separatorIndex)
      let value = rawLine[valueStart...].trimmingCharacters(in: .whitespaces)
      metadata[key] = value
    }

    return metadata
  }

  // JSON-encodes a value for safe embedding in front matter.
  private static func jsonEncoded<T: Encodable>(_ value: T) throws -> String {
    let data = try JSONEncoder().encode(value)
    guard let encodedString = String(data: data, encoding: .utf8) else {
      throw MarkdownNoteCodecError.encodingFailed
    }

    return encodedString
  }

  // Decodes a JSON-encoded string from front matter.
  private static func decodeJSONString(_ value: String?, sourceURL: URL) throws -> String {
    guard let value else {
      throw MarkdownNoteCodecError.missingMetadata("title", sourceURL)
    }

    let data = Data(value.utf8)
    return try JSONDecoder().decode(String.self, from: data)
  }

  // Decodes a JSON-encoded string array of tags from front matter.
  private static func decodeJSONTags(_ value: String?, sourceURL: URL) throws -> [String] {
    guard let value else {
      throw MarkdownNoteCodecError.missingMetadata("tags", sourceURL)
    }

    let data = Data(value.utf8)
    return try JSONDecoder().decode([String].self, from: data)
  }
}

enum MarkdownNoteCodecError: LocalizedError {
  case encodingFailed
  case missingFrontMatter(URL)
  case invalidFrontMatter(URL)
  case invalidDate(URL)
  case missingMetadata(String, URL)

  var errorDescription: String? {
    switch self {
    case .encodingFailed:
      return "Scéal could not encode a markdown note."
    case .missingFrontMatter(let url):
      return "The note file at \(url.lastPathComponent) is missing front matter."
    case .invalidFrontMatter(let url):
      return "The note file at \(url.lastPathComponent) has invalid front matter."
    case .invalidDate(let url):
      return "The note file at \(url.lastPathComponent) has an invalid date."
    case .missingMetadata(let key, let url):
      return "The note file at \(url.lastPathComponent) is missing `\(key)` metadata."
    }
  }
}
