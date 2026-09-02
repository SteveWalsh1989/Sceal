//
//  StructuredNoteDocument.swift
//

// Versioned structured-note domain types for durable sections and one-level groups.

import Foundation

nonisolated struct StructuredNoteDocument: Codable, Equatable, Sendable {
  static let currentSchemaVersion = 1

  var schemaVersion: Int
  var id: String
  var date: Date
  var title: String
  var tags: [String]
  var nodes: [StructuredNoteNode]

  init(
    schemaVersion: Int = Self.currentSchemaVersion,
    id: String,
    date: Date,
    title: String,
    tags: [String],
    nodes: [StructuredNoteNode]
  ) {
    self.schemaVersion = schemaVersion
    self.id = id
    self.date = date
    self.title = title
    self.tags = tags
    self.nodes = nodes
  }

  // Creates a valid document containing one empty root section.
  static func empty(id: String, date: Date) -> StructuredNoteDocument {
    StructuredNoteDocument(
      id: id,
      date: date,
      title: "",
      tags: [],
      nodes: [.section(StructuredNoteSection())]
    )
  }

  // Verifies persisted invariants before a document is accepted or written.
  func validate() throws {
    guard schemaVersion == Self.currentSchemaVersion else {
      throw StructuredNoteDocumentError.unsupportedSchemaVersion(
        found: schemaVersion,
        supported: Self.currentSchemaVersion
      )
    }

    guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw StructuredNoteDocumentError.emptyDocumentID
    }

    guard !nodes.isEmpty else {
      throw StructuredNoteDocumentError.emptyDocument
    }

    var nodeIDs = Set<UUID>()
    var sectionCount = 0

    for node in nodes {
      switch node {
      case .section(let section):
        try insertUniqueID(section.id, into: &nodeIDs)
        sectionCount += 1

      case .group(let group):
        try insertUniqueID(group.id, into: &nodeIDs)
        guard !group.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
          throw StructuredNoteDocumentError.emptyGroupTitle(group.id)
        }
        guard !group.sections.isEmpty else {
          throw StructuredNoteDocumentError.emptyGroup(group.id)
        }

        for section in group.sections {
          try insertUniqueID(section.id, into: &nodeIDs)
          sectionCount += 1
        }
      }
    }

    guard sectionCount > 0 else {
      throw StructuredNoteDocumentError.emptyDocument
    }
  }

  // Rejects UUID reuse across groups and sections in the same document.
  private func insertUniqueID(_ id: UUID, into ids: inout Set<UUID>) throws {
    guard ids.insert(id).inserted else {
      throw StructuredNoteDocumentError.duplicateNodeID(id)
    }
  }
}

nonisolated enum StructuredNoteNode: Equatable, Sendable {
  case section(StructuredNoteSection)
  case group(StructuredSectionGroup)

  var id: UUID {
    switch self {
    case .section(let section):
      return section.id
    case .group(let group):
      return group.id
    }
  }
}

extension StructuredNoteNode: Codable {
  private enum CodingKeys: String, CodingKey {
    case type
    case section
    case group
  }

  private enum NodeType: String, Codable {
    case section
    case group
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(NodeType.self, forKey: .type) {
    case .section:
      self = .section(try container.decode(StructuredNoteSection.self, forKey: .section))
    case .group:
      self = .group(try container.decode(StructuredSectionGroup.self, forKey: .group))
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .section(let section):
      try container.encode(NodeType.section, forKey: .type)
      try container.encode(section, forKey: .section)
    case .group(let group):
      try container.encode(NodeType.group, forKey: .type)
      try container.encode(group, forKey: .group)
    }
  }
}

nonisolated struct StructuredSectionGroup: Codable, Equatable, Identifiable, Sendable {
  var id: UUID
  var title: String
  var style: StructuredSectionStyle
  var isCollapsed: Bool
  var showsTypeLabel: Bool?
  var showsSectionCount: Bool?
  var sections: [StructuredNoteSection]

  init(
    id: UUID = UUID(),
    title: String,
    style: StructuredSectionStyle = .themeDefault,
    isCollapsed: Bool = false,
    showsTypeLabel: Bool? = nil,
    showsSectionCount: Bool? = nil,
    sections: [StructuredNoteSection]
  ) {
    self.id = id
    self.title = title
    self.style = style
    self.isCollapsed = isCollapsed
    self.showsTypeLabel = showsTypeLabel
    self.showsSectionCount = showsSectionCount
    self.sections = sections
  }

  var displaysTypeLabel: Bool { showsTypeLabel ?? false }
  var displaysSectionCount: Bool { showsSectionCount ?? false }
}

nonisolated struct StructuredNoteSection: Codable, Equatable, Identifiable, Sendable {
  var id: UUID
  var markdown: String
  var styleOverrides: StructuredSectionStyleOverrides
  var isCollapsed: Bool

  init(
    id: UUID = UUID(),
    markdown: String = "",
    styleOverrides: StructuredSectionStyleOverrides = .inherited,
    isCollapsed: Bool = false
  ) {
    self.id = id
    self.markdown = markdown
    self.styleOverrides = styleOverrides
    self.isCollapsed = isCollapsed
  }

  // Resolves property-level overrides without copying inherited values into storage.
  func resolvedStyle(
    groupStyle: StructuredSectionStyle?,
    themeStyle: StructuredSectionStyle
  ) -> StructuredSectionStyle {
    StructuredSectionStyle(
      backgroundColorName: styleOverrides.backgroundColor.resolvedValue(
        groupValue: groupStyle?.backgroundColorName,
        themeValue: themeStyle.backgroundColorName
      ),
      borderColorName: styleOverrides.effectiveColorOverride(for: .border).resolvedValue(
        groupValue: groupStyle?.borderColorName,
        themeValue: themeStyle.borderColorName
      ),
      headingColorName: styleOverrides.effectiveColorOverride(for: .heading).resolvedValue(
        groupValue: groupStyle?.headingColorName,
        themeValue: themeStyle.headingColorName
      ),
      bulletColorName: styleOverrides.effectiveColorOverride(for: .bullet).resolvedValue(
        groupValue: groupStyle?.bulletColorName,
        themeValue: themeStyle.bulletColorName
      )
    )
  }
}

nonisolated struct StructuredSectionStyle: Codable, Equatable, Sendable {
  var backgroundColorName: String?
  var borderColorName: String?
  var headingColorName: String?
  var bulletColorName: String?

  init(
    backgroundColorName: String? = nil,
    borderColorName: String? = nil,
    headingColorName: String? = nil,
    bulletColorName: String? = nil
  ) {
    self.backgroundColorName = backgroundColorName
    self.borderColorName = borderColorName
    self.headingColorName = headingColorName
    self.bulletColorName = bulletColorName
  }

  static let themeDefault = StructuredSectionStyle()
}

nonisolated struct StructuredSectionStyleOverrides: Codable, Equatable, Sendable {
  var backgroundColor: StructuredColorOverride
  var borderColor: StructuredColorOverride
  var headingColor: StructuredColorOverride
  var bulletColor: StructuredColorOverride
  var primaryColor: StructuredColorOverride?
  var headingFollowsPrimaryColor: Bool?
  var borderFollowsPrimaryColor: Bool?
  var bulletFollowsPrimaryColor: Bool?

  init(
    backgroundColor: StructuredColorOverride = .inherit,
    borderColor: StructuredColorOverride = .inherit,
    headingColor: StructuredColorOverride = .inherit,
    bulletColor: StructuredColorOverride = .inherit,
    primaryColor: StructuredColorOverride? = nil,
    headingFollowsPrimaryColor: Bool? = nil,
    borderFollowsPrimaryColor: Bool? = nil,
    bulletFollowsPrimaryColor: Bool? = nil
  ) {
    self.backgroundColor = backgroundColor
    self.borderColor = borderColor
    self.headingColor = headingColor
    self.bulletColor = bulletColor
    self.primaryColor = primaryColor
    self.headingFollowsPrimaryColor = headingFollowsPrimaryColor
    self.borderFollowsPrimaryColor = borderFollowsPrimaryColor
    self.bulletFollowsPrimaryColor = bulletFollowsPrimaryColor
  }

  static let inherited = StructuredSectionStyleOverrides(
    primaryColor: .inherit,
    headingFollowsPrimaryColor: true,
    borderFollowsPrimaryColor: true,
    bulletFollowsPrimaryColor: true
  )

  // Resolves a linked role to the primary color while preserving its independent fallback.
  func effectiveColorOverride(
    for role: StructuredSectionColorRole
  ) -> StructuredColorOverride {
    guard let primaryColor, followsPrimaryColor(role) else {
      return independentColorOverride(for: role)
    }
    return primaryColor
  }

  // Reports persisted links and infers sensible links for documents written before this field.
  func followsPrimaryColor(_ role: StructuredSectionColorRole) -> Bool {
    if primaryColor != nil {
      return storedFollowValue(for: role) ?? false
    }

    switch role {
    case .heading:
      return true
    case .border:
      return borderColor == headingColor
    case .bullet:
      return bulletColor == headingColor
    }
  }

  // Introduces or changes the primary color without changing which roles currently follow it.
  mutating func setPrimaryColor(_ color: StructuredColorOverride) {
    let headingFollowsPrimaryColor = followsPrimaryColor(.heading)
    let borderFollowsPrimaryColor = followsPrimaryColor(.border)
    let bulletFollowsPrimaryColor = followsPrimaryColor(.bullet)
    primaryColor = color
    self.headingFollowsPrimaryColor = headingFollowsPrimaryColor
    self.borderFollowsPrimaryColor = borderFollowsPrimaryColor
    self.bulletFollowsPrimaryColor = bulletFollowsPrimaryColor
  }

  // Links or unlinks one role while retaining its independent color for later reuse.
  mutating func setFollowsPrimaryColor(
    _ followsPrimaryColor: Bool,
    for role: StructuredSectionColorRole
  ) {
    switch role {
    case .heading:
      headingFollowsPrimaryColor = followsPrimaryColor
    case .border:
      borderFollowsPrimaryColor = followsPrimaryColor
    case .bullet:
      bulletFollowsPrimaryColor = followsPrimaryColor
    }
  }

  // Updates one role's independent color and detaches it from the primary color.
  mutating func setIndependentColorOverride(
    _ color: StructuredColorOverride,
    for role: StructuredSectionColorRole
  ) {
    switch role {
    case .heading:
      headingColor = color
    case .border:
      borderColor = color
    case .bullet:
      bulletColor = color
    }
    setFollowsPrimaryColor(false, for: role)
  }

  func independentColorOverride(
    for role: StructuredSectionColorRole
  ) -> StructuredColorOverride {
    switch role {
    case .heading:
      return headingColor
    case .border:
      return borderColor
    case .bullet:
      return bulletColor
    }
  }

  private func storedFollowValue(for role: StructuredSectionColorRole) -> Bool? {
    switch role {
    case .heading:
      return headingFollowsPrimaryColor
    case .border:
      return borderFollowsPrimaryColor
    case .bullet:
      return bulletFollowsPrimaryColor
    }
  }
}

nonisolated enum StructuredSectionColorRole: CaseIterable, Sendable {
  case heading
  case border
  case bullet
}

nonisolated enum StructuredColorOverride: Equatable, Sendable {
  case inherit
  case themeDefault
  case colorName(String)

  // Applies the section, group, and theme precedence for one color property.
  func resolvedValue(groupValue: String?, themeValue: String?) -> String? {
    switch self {
    case .inherit:
      return groupValue ?? themeValue
    case .themeDefault:
      return themeValue
    case .colorName(let name):
      return name
    }
  }
}

extension StructuredColorOverride: Codable {
  private enum CodingKeys: String, CodingKey {
    case type
    case value
  }

  private enum OverrideType: String, Codable {
    case inherit
    case themeDefault
    case colorName
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(OverrideType.self, forKey: .type) {
    case .inherit:
      self = .inherit
    case .themeDefault:
      self = .themeDefault
    case .colorName:
      self = .colorName(try container.decode(String.self, forKey: .value))
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .inherit:
      try container.encode(OverrideType.inherit, forKey: .type)
    case .themeDefault:
      try container.encode(OverrideType.themeDefault, forKey: .type)
    case .colorName(let name):
      try container.encode(OverrideType.colorName, forKey: .type)
      try container.encode(name, forKey: .value)
    }
  }
}

nonisolated enum StructuredNoteSectionParent: Equatable, Sendable {
  case root
  case group(UUID)
}

nonisolated struct StructuredNoteSectionDestination: Equatable, Sendable {
  let parent: StructuredNoteSectionParent
  let index: Int
}

nonisolated enum StructuredNoteMergeDirection: Equatable, Sendable {
  case previous
  case next
}

nonisolated enum StructuredNoteDocumentError: LocalizedError, Equatable {
  case unsupportedSchemaVersion(found: Int, supported: Int)
  case emptyDocumentID
  case emptyDocument
  case emptyGroup(UUID)
  case emptyGroupTitle(UUID)
  case duplicateNodeID(UUID)
  case sectionNotFound(UUID)
  case sectionNotGrouped(UUID)
  case groupNotFound(UUID)
  case sectionAlreadyGrouped(UUID)
  case nodeNotFound(UUID)
  case nodeNotAtRoot(UUID)
  case invalidDestinationIndex(Int)
  case invalidSplitOffset(Int)
  case noAdjacentSection(UUID, StructuredNoteMergeDirection)
  case cannotDeleteOnlySection
  case emptySectionReplacement

  var errorDescription: String? {
    switch self {
    case .unsupportedSchemaVersion(let found, let supported):
      return "Structured note schema version \(found) is unsupported; expected \(supported)."
    case .emptyDocumentID:
      return "A structured note must have a storage ID."
    case .emptyDocument:
      return "A structured note must contain at least one section."
    case .emptyGroup(let id):
      return "Section group \(id.uuidString) must contain at least one section."
    case .emptyGroupTitle(let id):
      return "Section group \(id.uuidString) must have a title."
    case .duplicateNodeID(let id):
      return "Structured note node ID \(id.uuidString) is duplicated."
    case .sectionNotFound(let id):
      return "Section \(id.uuidString) was not found."
    case .sectionNotGrouped(let id):
      return "Section \(id.uuidString) does not belong to a group."
    case .groupNotFound(let id):
      return "Section group \(id.uuidString) was not found."
    case .sectionAlreadyGrouped(let id):
      return "Section \(id.uuidString) already belongs to a group."
    case .nodeNotFound(let id):
      return "Structured note node \(id.uuidString) was not found."
    case .nodeNotAtRoot(let id):
      return "Node \(id.uuidString) is not at the note root."
    case .invalidDestinationIndex(let index):
      return "Structured note destination index \(index) is invalid."
    case .invalidSplitOffset(let offset):
      return "Structured note split offset \(offset) is invalid."
    case .noAdjacentSection(let id, let direction):
      return
        "Section \(id.uuidString) has no \(direction == .previous ? "previous" : "next") section to merge."
    case .cannotDeleteOnlySection:
      return "A structured note must keep at least one section."
    case .emptySectionReplacement:
      return "A structured section replacement must contain at least one section."
    }
  }
}
