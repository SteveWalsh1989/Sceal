//
//  NoteTemplate.swift
//

// User-managed reusable markdown templates that can be inserted from slash commands.

import Foundation

struct NoteTemplate: Identifiable, Codable, Equatable, Sendable {
  var id: String
  var title: String
  var command: String
  var menuDescription: String
  var body: String
  var isEnabled: Bool
  var usesGeneratedCommand: Bool
  var cursorPlacement: NoteTemplateCursorPlacement
  var sectionColorName: String?
  var createsNewSection: Bool

  init(
    id: String = UUID().uuidString,
    title: String,
    command: String,
    menuDescription: String = "",
    body: String = "",
    isEnabled: Bool = true,
    usesGeneratedCommand: Bool = true,
    cursorPlacement: NoteTemplateCursorPlacement = .automatic,
    sectionColorName: String? = nil,
    createsNewSection: Bool = false
  ) {
    self.id = id
    self.title = title
    self.command = command
    self.menuDescription = menuDescription
    self.body = body
    self.isEnabled = isEnabled
    self.usesGeneratedCommand = usesGeneratedCommand
    self.cursorPlacement = cursorPlacement
    self.sectionColorName = sectionColorName
    self.createsNewSection = createsNewSection
  }

  var slashCommand: String {
    "/\(command)"
  }

  var resolvedBodyForInsertion: String {
    NoteTemplateMarkdown.applyingTemplateOptions(
      to: body,
      sectionColorName: sectionColorName,
      createsNewSection: createsNewSection
    )
  }

  func normalizedForCurrentVersion() -> NoteTemplate {
    var template = self
    var foundEdgeDivider = false

    if NoteTemplateMarkdown.hasLeadingSectionDivider(in: template.body) {
      template.body = NoteTemplateMarkdown.removingLeadingSectionDivider(from: template.body)
      foundEdgeDivider = true
    }

    if NoteTemplateMarkdown.hasTrailingSectionDivider(in: template.body) {
      template.body = NoteTemplateMarkdown.removingTrailingSectionDivider(from: template.body)
      foundEdgeDivider = true
    }

    if foundEdgeDivider {
      template.createsNewSection = true
    }

    return template
  }

  static let starterMeeting = NoteTemplate(
    id: "starter-meeting",
    title: "Meeting",
    command: "meeting",
    menuDescription: "Insert meeting note structure",
    body: [
      "# Meeting:",
      "",
      "- ",
      "- ",
    ].joined(separator: "\n"),
    isEnabled: true,
    usesGeneratedCommand: true,
    cursorPlacement: .firstHeadingEnd,
    createsNewSection: true
  )

  private enum CodingKeys: String, CodingKey {
    case id
    case title
    case command
    case menuDescription
    case body
    case isEnabled
    case usesGeneratedCommand
    case cursorPlacement
    case sectionColorName
    case createsNewSection
    case startsWithDivider
    case endsWithDivider
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
    title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Untitled Template"
    command = try container.decodeIfPresent(String.self, forKey: .command) ?? ""
    menuDescription = try container.decodeIfPresent(String.self, forKey: .menuDescription) ?? ""
    body = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
    isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    usesGeneratedCommand =
      try container.decodeIfPresent(Bool.self, forKey: .usesGeneratedCommand) ?? false
    cursorPlacement =
      try container.decodeIfPresent(NoteTemplateCursorPlacement.self, forKey: .cursorPlacement)
      ?? .automatic
    sectionColorName = try container.decodeIfPresent(String.self, forKey: .sectionColorName)
    let legacyStartsWithDivider =
      try container.decodeIfPresent(Bool.self, forKey: .startsWithDivider) ?? false
    let legacyEndsWithDivider =
      try container.decodeIfPresent(Bool.self, forKey: .endsWithDivider) ?? false
    createsNewSection =
      try container.decodeIfPresent(Bool.self, forKey: .createsNewSection)
      ?? legacyStartsWithDivider || legacyEndsWithDivider
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(title, forKey: .title)
    try container.encode(command, forKey: .command)
    try container.encode(menuDescription, forKey: .menuDescription)
    try container.encode(body, forKey: .body)
    try container.encode(isEnabled, forKey: .isEnabled)
    try container.encode(usesGeneratedCommand, forKey: .usesGeneratedCommand)
    try container.encode(cursorPlacement, forKey: .cursorPlacement)
    try container.encodeIfPresent(sectionColorName, forKey: .sectionColorName)
    try container.encode(createsNewSection, forKey: .createsNewSection)
  }
}

enum NoteTemplateCursorPlacement: String, Codable, CaseIterable, Sendable {
  case automatic
  case firstHeadingEnd
  case firstEmptyBullet
  case end

  var displayName: String {
    switch self {
    case .automatic: return "Automatic"
    case .firstHeadingEnd: return "After first heading"
    case .firstEmptyBullet: return "First empty bullet"
    case .end: return "End of template"
    }
  }
}

enum NoteTemplateCommandRules {
  static let commandPattern = "^[a-z0-9]+(?:-[a-z0-9]+)*$"

  // Generates a lowercase command slug from a user-facing template title.
  static func suggestedCommand(for title: String) -> String {
    let lowercasedTitle = title.lowercased()
    var pieces: [String] = []
    var current = ""

    for scalar in lowercasedTitle.unicodeScalars {
      if isASCIICommandScalar(scalar) {
        current.unicodeScalars.append(scalar)
      } else if !current.isEmpty {
        pieces.append(current)
        current = ""
      }
    }

    if !current.isEmpty {
      pieces.append(current)
    }

    return pieces.isEmpty ? "template" : pieces.joined(separator: "-")
  }

  // Normalizes manual command field input while keeping invalid characters visible for validation.
  static func normalizedManualInput(_ input: String) -> String {
    var value = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if value.hasPrefix("/") {
      value.removeFirst()
    }
    return value
  }

  static func isValidFormat(_ command: String) -> Bool {
    command.range(of: commandPattern, options: .regularExpression) != nil
  }

  private static func isASCIICommandScalar(_ scalar: UnicodeScalar) -> Bool {
    (97...122).contains(Int(scalar.value)) || (48...57).contains(Int(scalar.value))
  }
}

enum NoteTemplateMarkdown {
  // Applies template-level section styling and an optional leading section boundary.
  static func applyingTemplateOptions(
    to markdown: String,
    sectionColorName: String?,
    createsNewSection: Bool = false
  ) -> String {
    var lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

    lines = lines.map { line in
      guard isSectionDivider(line) else { return line }
      return sectionMarker(colorName: sectionColorName)
    }

    if createsNewSection {
      lines = removingLeadingSectionDivider(from: lines)
      lines.insert(sectionMarker(colorName: sectionColorName), at: 0)
    }

    if shouldAddLeadingSectionMarker(to: lines, sectionColorName: sectionColorName) {
      lines.insert(sectionMarker(colorName: sectionColorName), at: 0)
    }

    return lines.joined(separator: "\n")
  }

  static func applyingTemplatePreviewColor(to markdown: String, sectionColorName: String?) -> String
  {
    markdown.split(separator: "\n", omittingEmptySubsequences: false)
      .map(String.init)
      .map { line in
        guard isSectionDivider(line) else { return line }
        return sectionMarker(colorName: sectionColorName)
      }
      .joined(separator: "\n")
  }

  static func removingSectionColorMetadata(from markdown: String) -> String {
    applyingTemplateOptions(to: markdown, sectionColorName: nil)
  }

  static func hasTrailingSectionDivider(in markdown: String) -> Bool {
    hasTrailingSectionDivider(
      in: markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    )
  }

  static func removingTrailingSectionDivider(from markdown: String) -> String {
    let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    return removingTrailingSectionDivider(from: lines).joined(separator: "\n")
  }

  static func hasLeadingSectionDivider(in markdown: String) -> Bool {
    hasLeadingSectionDivider(
      in: markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    )
  }

  static func removingLeadingSectionDivider(from markdown: String) -> String {
    let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    return removingLeadingSectionDivider(from: lines).joined(separator: "\n")
  }

  private static func hasTrailingSectionDivider(in lines: [String]) -> Bool {
    for line in lines.reversed() {
      if line.trimmingCharacters(in: .whitespaces).isEmpty {
        continue
      }
      return isSectionDivider(line)
    }
    return false
  }

  private static func hasLeadingSectionDivider(in lines: [String]) -> Bool {
    for line in lines {
      if line.trimmingCharacters(in: .whitespaces).isEmpty {
        continue
      }
      return isSectionDivider(line)
    }
    return false
  }

  private static func removingLeadingSectionDivider(from lines: [String]) -> [String] {
    var lines = lines
    while let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty {
      lines.removeFirst()
    }

    if let first = lines.first, isSectionDivider(first) {
      lines.removeFirst()
    }

    while let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty {
      lines.removeFirst()
    }

    return lines
  }

  private static func removingTrailingSectionDivider(from lines: [String]) -> [String] {
    var lines = lines
    while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
      lines.removeLast()
    }

    if let last = lines.last, isSectionDivider(last) {
      lines.removeLast()
    }

    while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
      lines.removeLast()
    }

    return lines
  }

  private static func shouldAddLeadingSectionMarker(
    to lines: [String],
    sectionColorName: String?
  ) -> Bool {
    guard let sectionColorName, !sectionColorName.isEmpty else { return false }

    for line in lines {
      if line.trimmingCharacters(in: .whitespaces).isEmpty {
        continue
      }
      return !isSectionDivider(line)
    }

    return false
  }

  private static func isSectionDivider(_ line: String) -> Bool {
    MarkdownEditorSectionDirectiveMarkdown.parse(line) != nil
  }

  private static func sectionMarker(colorName: String?) -> String {
    guard let colorName, !colorName.isEmpty else {
      return MarkdownEditorSectionDirectiveMarkdown.marker(
        for: MarkdownEditorSectionDirective()
      )
    }
    return MarkdownEditorSectionDirectiveMarkdown.marker(
      headingColorName: colorName,
      bulletColorName: colorName,
      usesSectionColor: true
    )
  }
}

nonisolated enum NoteTemplateArchive {
  static let folderName = "Templates"
  static let fileName = "templates.json"

  // Writes templates into the archive metadata folder when there is at least one template.
  static func write(_ templates: [NoteTemplate], to rootURL: URL) throws {
    guard !templates.isEmpty else { return }
    let directoryURL = rootURL.appendingPathComponent(folderName, isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let fileURL = directoryURL.appendingPathComponent(fileName)
    try encoder.encode(templates).write(to: fileURL, options: .atomic)
  }

  // Reads templates from an archive root, returning an empty list when the payload is absent.
  static func read(from rootURL: URL) throws -> [NoteTemplate] {
    let fileURL = rootURL.appendingPathComponent(folderName, isDirectory: true)
      .appendingPathComponent(fileName)
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
    return try JSONDecoder().decode([NoteTemplate].self, from: Data(contentsOf: fileURL))
  }

  // Finds a templates payload in either the selected folder or a nested exported root folder.
  static func findTemplatesFile(in folderURL: URL, fileManager: FileManager = .default) -> URL? {
    let directURL = folderURL.appendingPathComponent(folderName, isDirectory: true)
      .appendingPathComponent(fileName)
    if fileManager.fileExists(atPath: directURL.path) {
      return directURL
    }

    guard
      let enumerator = fileManager.enumerator(
        at: folderURL,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
      )
    else {
      return nil
    }

    for case let fileURL as URL in enumerator
    where fileURL.lastPathComponent == fileName
      && fileURL.deletingLastPathComponent().lastPathComponent == folderName
    {
      return fileURL
    }

    return nil
  }
}
