//
//  MarkdownNoteFile.swift
//
//

import Foundation

enum MarkdownNoteFile {
  private static let frontMatterMarker = "---"

  static func encode(_ note: DayNote) throws -> String {
    let titleValue = try jsonEncoded(note.title)
    let tagsValue = try jsonEncoded(note.tags)

    return """
      \(frontMatterMarker)
      date: \(ScealDateFormatters.storageDate.string(from: note.date))
      title: \(titleValue)
      tags: \(tagsValue)
      \(frontMatterMarker)
      \(note.body)
      """
  }

  static func decode(contents: String, sourceURL: URL) throws -> DayNote {
    let prefix = "\(frontMatterMarker)\n"
    guard contents.hasPrefix(prefix) else {
      throw MarkdownNoteFileError.missingFrontMatter(sourceURL)
    }

    let metadataStart = contents.index(contents.startIndex, offsetBy: prefix.count)
    guard let metadataEnd = contents[metadataStart...].range(of: "\n\(frontMatterMarker)\n") else {
      throw MarkdownNoteFileError.invalidFrontMatter(sourceURL)
    }

    let metadataBlock = String(contents[metadataStart..<metadataEnd.lowerBound])
    let body = String(contents[metadataEnd.upperBound...])
    let metadata = try parseMetadataBlock(metadataBlock, sourceURL: sourceURL)

    guard
      let dateValue = metadata["date"],
      let date = ScealDateFormatters.storageDate.date(from: dateValue)
    else {
      throw MarkdownNoteFileError.invalidDate(sourceURL)
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

  private static func parseMetadataBlock(_ block: String, sourceURL: URL) throws -> [String: String]
  {
    var metadata: [String: String] = [:]

    for rawLine in block.split(separator: "\n", omittingEmptySubsequences: false) {
      guard let separatorIndex = rawLine.firstIndex(of: ":") else {
        throw MarkdownNoteFileError.invalidFrontMatter(sourceURL)
      }

      let key = rawLine[..<separatorIndex].trimmingCharacters(in: .whitespaces)
      let valueStart = rawLine.index(after: separatorIndex)
      let value = rawLine[valueStart...].trimmingCharacters(in: .whitespaces)
      metadata[key] = value
    }

    return metadata
  }

  private static func jsonEncoded<T: Encodable>(_ value: T) throws -> String {
    let data = try JSONEncoder().encode(value)
    guard let encodedString = String(data: data, encoding: .utf8) else {
      throw MarkdownNoteFileError.encodingFailed
    }

    return encodedString
  }

  private static func decodeJSONString(_ value: String?, sourceURL: URL) throws -> String {
    guard let value else {
      throw MarkdownNoteFileError.missingMetadata("title", sourceURL)
    }

    let data = Data(value.utf8)
    return try JSONDecoder().decode(String.self, from: data)
  }

  private static func decodeJSONTags(_ value: String?, sourceURL: URL) throws -> [String] {
    guard let value else {
      throw MarkdownNoteFileError.missingMetadata("tags", sourceURL)
    }

    let data = Data(value.utf8)
    return try JSONDecoder().decode([String].self, from: data)
  }
}

enum MarkdownNoteFileError: LocalizedError {
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
