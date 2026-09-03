//
//  StructuredNoteDocument+Mutations.swift
//

// Transactional mutations for structured sections and one-level groups.

import Foundation

extension StructuredNoteDocument {
  private struct SectionLocation {
    let parent: StructuredNoteSectionParent
    let index: Int
    let rootNodeIndex: Int
  }

  // Inserts a section at a validated root or group destination.
  mutating func insertSection(
    _ section: StructuredNoteSection,
    at destination: StructuredNoteSectionDestination
  ) throws {
    try applyMutation { document in
      try document.insertSectionWithoutValidation(section, at: destination)
    }
  }

  // Splits a section at a UTF-16 editor offset and returns the new section ID.
  @discardableResult
  mutating func splitSection(id sectionID: UUID, atUTF16Offset offset: Int) throws -> UUID {
    try applyMutation { document in
      guard let location = document.sectionLocation(for: sectionID) else {
        throw StructuredNoteDocumentError.sectionNotFound(sectionID)
      }

      var section = try document.section(at: location)
      guard let splitIndex = document.stringIndex(atUTF16Offset: offset, in: section.markdown)
      else {
        throw StructuredNoteDocumentError.invalidSplitOffset(offset)
      }

      let trailingMarkdown = String(section.markdown[splitIndex...])
      section.markdown = String(section.markdown[..<splitIndex])
      try document.replaceSection(section, at: location)

      let newSection = StructuredNoteSection(markdown: trailingMarkdown)
      let destination = StructuredNoteSectionDestination(
        parent: location.parent,
        index: location.index + 1
      )
      try document.insertSectionWithoutValidation(newSection, at: destination)
      return newSection.id
    }
  }

  // Inserts one blank section while preserving the original style on surrounding content.
  @discardableResult
  mutating func insertBlankSection(id sectionID: UUID, atUTF16Offset offset: Int) throws -> UUID {
    try applyMutation { document in
      guard let location = document.sectionLocation(for: sectionID) else {
        throw StructuredNoteDocumentError.sectionNotFound(sectionID)
      }

      let existingSection = try document.section(at: location)
      guard
        let splitIndex = document.stringIndex(
          atUTF16Offset: offset,
          in: existingSection.markdown
        )
      else {
        throw StructuredNoteDocumentError.invalidSplitOffset(offset)
      }

      let leadingMarkdown = String(existingSection.markdown[..<splitIndex])
      let trailingMarkdown = String(existingSection.markdown[splitIndex...])
      let insertedSection = StructuredNoteSection()
      var replacements: [StructuredNoteSection] = []

      if !leadingMarkdown.isEmpty {
        var leadingSection = existingSection
        leadingSection.markdown = leadingMarkdown
        replacements.append(leadingSection)
      }

      replacements.append(insertedSection)

      if !trailingMarkdown.isEmpty {
        var trailingSection = existingSection
        trailingSection.id = leadingMarkdown.isEmpty ? existingSection.id : UUID()
        trailingSection.markdown = trailingMarkdown
        replacements.append(trailingSection)
      }

      try document.replaceSectionWithoutValidation(at: location, with: replacements)
      return insertedSection.id
    }
  }

  // Replaces one section's Markdown without depending on its root or grouped location.
  mutating func setSectionMarkdown(_ markdown: String, sectionID: UUID) throws {
    try applyMutation { document in
      guard let location = document.sectionLocation(for: sectionID) else {
        throw StructuredNoteDocumentError.sectionNotFound(sectionID)
      }
      var section = try document.section(at: location)
      section.markdown = markdown
      try document.replaceSection(section, at: location)
    }
  }

  // Replaces one section in place with one or more sections while retaining its parent container.
  mutating func replaceSection(
    id sectionID: UUID,
    with replacementSections: [StructuredNoteSection]
  ) throws {
    try applyMutation { document in
      guard !replacementSections.isEmpty else {
        throw StructuredNoteDocumentError.emptySectionReplacement
      }
      guard let location = document.sectionLocation(for: sectionID) else {
        throw StructuredNoteDocumentError.sectionNotFound(sectionID)
      }

      try document.replaceSectionWithoutValidation(at: location, with: replacementSections)
    }
  }

  // Deletes one section while preserving the invariant that every document stays editable.
  mutating func deleteSection(id sectionID: UUID) throws {
    try applyMutation { document in
      guard let location = document.sectionLocation(for: sectionID) else {
        throw StructuredNoteDocumentError.sectionNotFound(sectionID)
      }
      guard document.totalSectionCount > 1 else {
        throw StructuredNoteDocumentError.cannotDeleteOnlySection
      }
      _ = try document.removeSectionWithoutValidation(at: location)
    }
  }

  // Merges a section with an adjacent section in the same root or group container.
  @discardableResult
  mutating func mergeSection(id sectionID: UUID, direction: StructuredNoteMergeDirection) throws
    -> UUID
  {
    try applyMutation { document in
      guard let location = document.sectionLocation(for: sectionID) else {
        throw StructuredNoteDocumentError.sectionNotFound(sectionID)
      }

      switch location.parent {
      case .root:
        return try document.mergeRootSection(at: location, direction: direction)
      case .group:
        return try document.mergeGroupedSection(at: location, direction: direction)
      }
    }
  }

  // Moves a section to a final index after it has been removed from its source container.
  mutating func moveSection(
    id sectionID: UUID,
    to destination: StructuredNoteSectionDestination
  ) throws {
    try applyMutation { document in
      guard let origin = document.sectionLocation(for: sectionID) else {
        throw StructuredNoteDocumentError.sectionNotFound(sectionID)
      }

      if origin.parent == destination.parent {
        try document.moveSectionWithinParent(from: origin, toIndex: destination.index)
        return
      }

      let section = try document.removeSectionWithoutValidation(at: origin)
      try document.insertSectionWithoutValidation(section, at: destination)
    }
  }

  // Wraps one root section in a new group at the same document position.
  @discardableResult
  mutating func createGroup(
    title: String,
    aroundSectionID sectionID: UUID,
    style: StructuredSectionStyle = .themeDefault
  ) throws -> UUID {
    try applyMutation { document in
      guard let location = document.sectionLocation(for: sectionID) else {
        throw StructuredNoteDocumentError.sectionNotFound(sectionID)
      }
      guard location.parent == .root else {
        throw StructuredNoteDocumentError.sectionAlreadyGrouped(sectionID)
      }

      let section = try document.section(at: location)
      let group = StructuredSectionGroup(title: title, style: style, sections: [section])
      document.nodes[location.rootNodeIndex] = .group(group)
      return group.id
    }
  }

  // Moves a grouped section to a root-node position.
  mutating func detachSection(id sectionID: UUID, toRootIndex index: Int) throws {
    guard let location = sectionLocation(for: sectionID) else {
      throw StructuredNoteDocumentError.sectionNotFound(sectionID)
    }
    guard case .group = location.parent else {
      throw StructuredNoteDocumentError.sectionNotGrouped(sectionID)
    }

    try moveSection(
      id: sectionID,
      to: StructuredNoteSectionDestination(parent: .root, index: index)
    )
  }

  // Detaches a section immediately after its group without exposing root-index bookkeeping.
  mutating func detachSection(id sectionID: UUID) throws {
    guard let location = sectionLocation(for: sectionID) else {
      throw StructuredNoteDocumentError.sectionNotFound(sectionID)
    }
    guard case .group = location.parent,
      case .group(let group) = nodes[location.rootNodeIndex]
    else {
      throw StructuredNoteDocumentError.sectionNotGrouped(sectionID)
    }

    let destinationIndex =
      group.sections.count == 1 ? location.rootNodeIndex : location.rootNodeIndex + 1
    try detachSection(id: sectionID, toRootIndex: destinationIndex)
  }

  // Replaces a group with its sections at the group's existing root position.
  mutating func ungroup(id groupID: UUID) throws {
    try applyMutation { document in
      guard let groupIndex = document.groupNodeIndex(for: groupID) else {
        throw StructuredNoteDocumentError.groupNotFound(groupID)
      }
      guard case .group(let group) = document.nodes[groupIndex] else {
        throw StructuredNoteDocumentError.groupNotFound(groupID)
      }

      document.nodes.remove(at: groupIndex)
      document.nodes.insert(
        contentsOf: group.sections.map(StructuredNoteNode.section),
        at: groupIndex
      )
    }
  }

  // Deletes a group and its sections while preserving the document's final editable section.
  mutating func deleteGroup(id groupID: UUID) throws {
    try applyMutation { document in
      guard let groupIndex = document.groupNodeIndex(for: groupID),
        case .group(let group) = document.nodes[groupIndex]
      else {
        throw StructuredNoteDocumentError.groupNotFound(groupID)
      }
      guard document.totalSectionCount > group.sections.count else {
        throw StructuredNoteDocumentError.cannotDeleteOnlySection
      }

      document.nodes.remove(at: groupIndex)
    }
  }

  // Reorders a root section or group as one top-level item.
  mutating func moveRootNode(id nodeID: UUID, to index: Int) throws {
    try applyMutation { document in
      guard let sourceIndex = document.nodes.firstIndex(where: { $0.id == nodeID }) else {
        if document.sectionLocation(for: nodeID) != nil {
          throw StructuredNoteDocumentError.nodeNotAtRoot(nodeID)
        }
        throw StructuredNoteDocumentError.nodeNotFound(nodeID)
      }

      let node = document.nodes.remove(at: sourceIndex)
      guard (0...document.nodes.count).contains(index) else {
        throw StructuredNoteDocumentError.invalidDestinationIndex(index)
      }
      document.nodes.insert(node, at: index)
    }
  }

  // Persists the collapsed state for one section.
  mutating func setSectionCollapsed(_ isCollapsed: Bool, sectionID: UUID) throws {
    try applyMutation { document in
      guard let location = document.sectionLocation(for: sectionID) else {
        throw StructuredNoteDocumentError.sectionNotFound(sectionID)
      }
      var section = try document.section(at: location)
      section.isCollapsed = isCollapsed
      try document.replaceSection(section, at: location)
    }
  }

  // Persists the collapsed state for one group.
  mutating func setGroupCollapsed(_ isCollapsed: Bool, groupID: UUID) throws {
    try applyMutation { document in
      guard let groupIndex = document.groupNodeIndex(for: groupID),
        case .group(var group) = document.nodes[groupIndex]
      else {
        throw StructuredNoteDocumentError.groupNotFound(groupID)
      }
      group.isCollapsed = isCollapsed
      document.nodes[groupIndex] = .group(group)
    }
  }

  // Replaces one group's semantic title while preserving its identity and children.
  mutating func setGroupTitle(_ title: String, groupID: UUID) throws {
    try applyMutation { document in
      guard let groupIndex = document.groupNodeIndex(for: groupID),
        case .group(var group) = document.nodes[groupIndex]
      else {
        throw StructuredNoteDocumentError.groupNotFound(groupID)
      }
      group.title = title
      document.nodes[groupIndex] = .group(group)
    }
  }

  // Replaces the property-level appearance overrides for one section.
  mutating func setStyleOverrides(
    _ styleOverrides: StructuredSectionStyleOverrides,
    sectionID: UUID
  ) throws {
    try applyMutation { document in
      guard let location = document.sectionLocation(for: sectionID) else {
        throw StructuredNoteDocumentError.sectionNotFound(sectionID)
      }
      var section = try document.section(at: location)
      section.styleOverrides = styleOverrides
      try document.replaceSection(section, at: location)
    }
  }

  // Replaces the inherited appearance values for one group.
  mutating func setGroupStyle(_ style: StructuredSectionStyle, groupID: UUID) throws {
    try applyMutation { document in
      guard let groupIndex = document.groupNodeIndex(for: groupID),
        case .group(var group) = document.nodes[groupIndex]
      else {
        throw StructuredNoteDocumentError.groupNotFound(groupID)
      }
      group.style = style
      document.nodes[groupIndex] = .group(group)
    }
  }

  // Updates optional group-header metadata without changing its semantic title or children.
  mutating func setGroupHeaderVisibility(
    showsTypeLabel: Bool,
    showsSectionCount: Bool,
    groupID: UUID
  ) throws {
    try applyMutation { document in
      guard let groupIndex = document.groupNodeIndex(for: groupID),
        case .group(var group) = document.nodes[groupIndex]
      else {
        throw StructuredNoteDocumentError.groupNotFound(groupID)
      }
      group.showsTypeLabel = showsTypeLabel
      group.showsSectionCount = showsSectionCount
      document.nodes[groupIndex] = .group(group)
    }
  }

  // Commits a mutation only after the complete updated document validates.
  private mutating func applyMutation<Result>(
    _ mutation: (inout StructuredNoteDocument) throws -> Result
  ) throws -> Result {
    var updatedDocument = self
    let result = try mutation(&updatedDocument)
    try updatedDocument.validate()
    self = updatedDocument
    return result
  }

  // Locates a section and its one permitted parent container.
  private func sectionLocation(for sectionID: UUID) -> SectionLocation? {
    for (rootNodeIndex, node) in nodes.enumerated() {
      switch node {
      case .section(let section) where section.id == sectionID:
        return SectionLocation(parent: .root, index: rootNodeIndex, rootNodeIndex: rootNodeIndex)

      case .group(let group):
        if let sectionIndex = group.sections.firstIndex(where: { $0.id == sectionID }) {
          return SectionLocation(
            parent: .group(group.id),
            index: sectionIndex,
            rootNodeIndex: rootNodeIndex
          )
        }

      default:
        continue
      }
    }
    return nil
  }

  // Locates a group among the document's root nodes.
  private func groupNodeIndex(for groupID: UUID) -> Int? {
    nodes.firstIndex { node in
      guard case .group(let group) = node else { return false }
      return group.id == groupID
    }
  }

  // Counts root and grouped sections without exposing the private location model.
  private var totalSectionCount: Int {
    nodes.reduce(into: 0) { count, node in
      switch node {
      case .section:
        count += 1
      case .group(let group):
        count += group.sections.count
      }
    }
  }

  // Reads the section represented by a previously resolved location.
  private func section(at location: SectionLocation) throws -> StructuredNoteSection {
    switch location.parent {
    case .root:
      guard case .section(let section) = nodes[location.rootNodeIndex] else {
        throw StructuredNoteDocumentError.invalidDestinationIndex(location.rootNodeIndex)
      }
      return section

    case .group:
      guard case .group(let group) = nodes[location.rootNodeIndex],
        group.sections.indices.contains(location.index)
      else {
        throw StructuredNoteDocumentError.invalidDestinationIndex(location.index)
      }
      return group.sections[location.index]
    }
  }

  // Replaces a section without changing its position or parent.
  private mutating func replaceSection(
    _ section: StructuredNoteSection,
    at location: SectionLocation
  ) throws {
    switch location.parent {
    case .root:
      nodes[location.rootNodeIndex] = .section(section)

    case .group:
      guard case .group(var group) = nodes[location.rootNodeIndex] else {
        throw StructuredNoteDocumentError.invalidDestinationIndex(location.rootNodeIndex)
      }
      group.sections[location.index] = section
      nodes[location.rootNodeIndex] = .group(group)
    }
  }

  // Replaces one section with ordered siblings inside its existing parent container.
  private mutating func replaceSectionWithoutValidation(
    at location: SectionLocation,
    with replacementSections: [StructuredNoteSection]
  ) throws {
    switch location.parent {
    case .root:
      nodes.replaceSubrange(
        location.rootNodeIndex...location.rootNodeIndex,
        with: replacementSections.map(StructuredNoteNode.section)
      )

    case .group:
      guard case .group(var group) = nodes[location.rootNodeIndex] else {
        throw StructuredNoteDocumentError.invalidDestinationIndex(location.rootNodeIndex)
      }
      group.sections.replaceSubrange(
        location.index...location.index,
        with: replacementSections
      )
      nodes[location.rootNodeIndex] = .group(group)
    }
  }

  // Inserts into a root or group while the surrounding transaction is in progress.
  private mutating func insertSectionWithoutValidation(
    _ section: StructuredNoteSection,
    at destination: StructuredNoteSectionDestination
  ) throws {
    switch destination.parent {
    case .root:
      guard (0...nodes.count).contains(destination.index) else {
        throw StructuredNoteDocumentError.invalidDestinationIndex(destination.index)
      }
      nodes.insert(.section(section), at: destination.index)

    case .group(let groupID):
      guard let groupIndex = groupNodeIndex(for: groupID),
        case .group(var group) = nodes[groupIndex]
      else {
        throw StructuredNoteDocumentError.groupNotFound(groupID)
      }
      guard (0...group.sections.count).contains(destination.index) else {
        throw StructuredNoteDocumentError.invalidDestinationIndex(destination.index)
      }
      group.sections.insert(section, at: destination.index)
      nodes[groupIndex] = .group(group)
    }
  }

  // Removes a section and discards its group if that group becomes empty.
  private mutating func removeSectionWithoutValidation(at location: SectionLocation) throws
    -> StructuredNoteSection
  {
    switch location.parent {
    case .root:
      guard case .section(let section) = nodes.remove(at: location.rootNodeIndex) else {
        throw StructuredNoteDocumentError.invalidDestinationIndex(location.rootNodeIndex)
      }
      return section

    case .group:
      guard case .group(var group) = nodes[location.rootNodeIndex] else {
        throw StructuredNoteDocumentError.invalidDestinationIndex(location.rootNodeIndex)
      }
      let section = group.sections.remove(at: location.index)
      if group.sections.isEmpty {
        nodes.remove(at: location.rootNodeIndex)
      } else {
        nodes[location.rootNodeIndex] = .group(group)
      }
      return section
    }
  }

  // Reorders a section using an index in the collection after removal.
  private mutating func moveSectionWithinParent(from origin: SectionLocation, toIndex index: Int)
    throws
  {
    switch origin.parent {
    case .root:
      let section = try removeSectionWithoutValidation(at: origin)
      try insertSectionWithoutValidation(
        section,
        at: StructuredNoteSectionDestination(parent: .root, index: index)
      )

    case .group:
      guard case .group(var group) = nodes[origin.rootNodeIndex] else {
        throw StructuredNoteDocumentError.invalidDestinationIndex(origin.rootNodeIndex)
      }
      let section = group.sections.remove(at: origin.index)
      guard (0...group.sections.count).contains(index) else {
        throw StructuredNoteDocumentError.invalidDestinationIndex(index)
      }
      group.sections.insert(section, at: index)
      nodes[origin.rootNodeIndex] = .group(group)
    }
  }

  // Merges root sections while treating groups as hard adjacency boundaries.
  private mutating func mergeRootSection(
    at location: SectionLocation,
    direction: StructuredNoteMergeDirection
  ) throws -> UUID {
    let currentSection = try section(at: location)
    let adjacentIndex =
      direction == .previous ? location.rootNodeIndex - 1 : location.rootNodeIndex + 1
    guard nodes.indices.contains(adjacentIndex),
      case .section(let adjacentSection) = nodes[adjacentIndex]
    else {
      throw StructuredNoteDocumentError.noAdjacentSection(currentSection.id, direction)
    }

    if direction == .previous {
      var retainedSection = adjacentSection
      retainedSection.markdown = joinedMarkdown(adjacentSection.markdown, currentSection.markdown)
      nodes[adjacentIndex] = .section(retainedSection)
      nodes.remove(at: location.rootNodeIndex)
      return retainedSection.id
    }

    var retainedSection = currentSection
    retainedSection.markdown = joinedMarkdown(currentSection.markdown, adjacentSection.markdown)
    nodes[location.rootNodeIndex] = .section(retainedSection)
    nodes.remove(at: adjacentIndex)
    return retainedSection.id
  }

  // Merges only sections that are adjacent within the same group.
  private mutating func mergeGroupedSection(
    at location: SectionLocation,
    direction: StructuredNoteMergeDirection
  ) throws -> UUID {
    guard case .group(var group) = nodes[location.rootNodeIndex] else {
      throw StructuredNoteDocumentError.invalidDestinationIndex(location.rootNodeIndex)
    }
    let adjacentIndex = direction == .previous ? location.index - 1 : location.index + 1
    guard group.sections.indices.contains(adjacentIndex) else {
      throw StructuredNoteDocumentError.noAdjacentSection(
        group.sections[location.index].id,
        direction
      )
    }

    if direction == .previous {
      var retainedSection = group.sections[adjacentIndex]
      retainedSection.markdown = joinedMarkdown(
        retainedSection.markdown,
        group.sections[location.index].markdown
      )
      group.sections[adjacentIndex] = retainedSection
      group.sections.remove(at: location.index)
      nodes[location.rootNodeIndex] = .group(group)
      return retainedSection.id
    }

    var retainedSection = group.sections[location.index]
    retainedSection.markdown = joinedMarkdown(
      retainedSection.markdown,
      group.sections[adjacentIndex].markdown
    )
    group.sections[location.index] = retainedSection
    group.sections.remove(at: adjacentIndex)
    nodes[location.rootNodeIndex] = .group(group)
    return retainedSection.id
  }

  // Converts an AppKit UTF-16 caret offset into a valid Swift string boundary.
  private func stringIndex(atUTF16Offset offset: Int, in string: String) -> String.Index? {
    guard offset >= 0,
      let utf16Index = string.utf16.index(
        string.utf16.startIndex,
        offsetBy: offset,
        limitedBy: string.utf16.endIndex
      )
    else { return nil }

    return utf16Index.samePosition(in: string)
  }

  // Joins two non-empty section bodies with a stable Markdown paragraph boundary.
  private func joinedMarkdown(_ leading: String, _ trailing: String) -> String {
    if leading.isEmpty { return trailing }
    if trailing.isEmpty { return leading }
    return "\(leading)\n\n\(trailing)"
  }
}
