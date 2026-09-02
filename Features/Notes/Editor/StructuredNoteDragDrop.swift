//
//  StructuredNoteDragDrop.swift
//

// Pure drag payload and drop-target resolution for structured note nodes.

import AppKit
import Foundation
import UniformTypeIdentifiers

nonisolated enum StructuredNoteDragPayload: Equatable, Sendable {
  case section(UUID)
  case group(UUID)

  static let contentType = UTType(
    exportedAs: "com.stevewalsh.sceal.structured-note-node",
    conformingTo: .data
  )
  private static let sectionPrefix = "sceal-structured-section:"
  private static let groupPrefix = "sceal-structured-group:"

  // Encodes a local drag item as a stable value for the private pasteboard type.
  var encodedValue: String {
    switch self {
    case .section(let sectionID):
      return "\(Self.sectionPrefix)\(sectionID.uuidString)"
    case .group(let groupID):
      return "\(Self.groupPrefix)\(groupID.uuidString)"
    }
  }

  // Decodes only payloads produced by the structured editor.
  init?(encodedValue: String) {
    if encodedValue.hasPrefix(Self.sectionPrefix),
      let sectionID = UUID(uuidString: String(encodedValue.dropFirst(Self.sectionPrefix.count)))
    {
      self = .section(sectionID)
      return
    }

    if encodedValue.hasPrefix(Self.groupPrefix),
      let groupID = UUID(uuidString: String(encodedValue.dropFirst(Self.groupPrefix.count)))
    {
      self = .group(groupID)
      return
    }

    return nil
  }

  // Publishes only a dedicated non-text type so an NSTextView cannot insert the payload.
  @MainActor
  func makeItemProvider() -> NSItemProvider {
    let encodedData = Data(encodedValue.utf8)
    let itemProvider = NSItemProvider()
    itemProvider.suggestedName = encodedValue
    itemProvider.registerDataRepresentation(
      forTypeIdentifier: Self.contentType.identifier,
      visibility: .all
    ) { completion in
      completion(encodedData, nil)
      return nil
    }
    return itemProvider
  }
}

nonisolated enum StructuredNoteDropTarget: Equatable, Sendable {
  case root(insertionIndex: Int)
  case group(groupID: UUID, insertionIndex: Int)
}

nonisolated struct StructuredNoteDropResult: Equatable, Sendable {
  let didChange: Bool
  let focusedSectionID: UUID?
}

nonisolated enum StructuredNoteDragDropError: LocalizedError, Equatable {
  case groupsCannotBeNested

  var errorDescription: String? {
    switch self {
    case .groupsCannotBeNested:
      return "Section groups cannot be placed inside another group."
    }
  }
}

enum StructuredNoteDragDrop {
  private struct SectionOrigin {
    let parent: StructuredNoteSectionParent
    let index: Int
    let rootNodeIndex: Int
    let parentSectionCount: Int
  }

  // Checks a proposed drop against a copy so hover validation cannot mutate the document.
  static func canApply(
    _ payload: StructuredNoteDragPayload,
    to target: StructuredNoteDropTarget,
    in document: StructuredNoteDocument
  ) -> Bool {
    var candidate = document
    do {
      return try apply(payload, to: target, in: &candidate).didChange
    } catch {
      return false
    }
  }

  // Applies one visible insertion-gap target as a validated structured document mutation.
  @discardableResult
  static func apply(
    _ payload: StructuredNoteDragPayload,
    to target: StructuredNoteDropTarget,
    in document: inout StructuredNoteDocument
  ) throws -> StructuredNoteDropResult {
    switch payload {
    case .group(let groupID):
      return try moveGroup(groupID, to: target, in: &document)
    case .section(let sectionID):
      return try moveSection(sectionID, to: target, in: &document)
    }
  }

  // Reorders a group only among root nodes and rejects nested-group targets.
  private static func moveGroup(
    _ groupID: UUID,
    to target: StructuredNoteDropTarget,
    in document: inout StructuredNoteDocument
  ) throws -> StructuredNoteDropResult {
    guard
      let sourceIndex = document.nodes.firstIndex(where: { node in
        guard case .group(let group) = node else { return false }
        return group.id == groupID
      }), case .group(let group) = document.nodes[sourceIndex]
    else {
      throw StructuredNoteDocumentError.groupNotFound(groupID)
    }
    guard case .root(let insertionIndex) = target else {
      throw StructuredNoteDragDropError.groupsCannotBeNested
    }
    guard (0...document.nodes.count).contains(insertionIndex) else {
      throw StructuredNoteDocumentError.invalidDestinationIndex(insertionIndex)
    }

    let destinationIndex = normalizedInsertionIndex(
      insertionIndex,
      removingItemAt: sourceIndex
    )
    let focusedSectionID = group.sections.first?.id
    guard destinationIndex != sourceIndex else {
      return StructuredNoteDropResult(
        didChange: false,
        focusedSectionID: focusedSectionID
      )
    }

    try document.moveRootNode(id: groupID, to: destinationIndex)
    return StructuredNoteDropResult(didChange: true, focusedSectionID: focusedSectionID)
  }

  // Moves or detaches one section while preserving its stable state and identity.
  private static func moveSection(
    _ sectionID: UUID,
    to target: StructuredNoteDropTarget,
    in document: inout StructuredNoteDocument
  ) throws -> StructuredNoteDropResult {
    guard let origin = sectionOrigin(sectionID, in: document) else {
      throw StructuredNoteDocumentError.sectionNotFound(sectionID)
    }

    switch target {
    case .root(let insertionIndex):
      guard (0...document.nodes.count).contains(insertionIndex) else {
        throw StructuredNoteDocumentError.invalidDestinationIndex(insertionIndex)
      }

      switch origin.parent {
      case .root:
        let destinationIndex = normalizedInsertionIndex(
          insertionIndex,
          removingItemAt: origin.rootNodeIndex
        )
        guard destinationIndex != origin.rootNodeIndex else {
          return StructuredNoteDropResult(didChange: false, focusedSectionID: sectionID)
        }
        try document.moveRootNode(id: sectionID, to: destinationIndex)

      case .group:
        let removesSourceGroup = origin.parentSectionCount == 1
        let destinationIndex =
          removesSourceGroup && origin.rootNodeIndex < insertionIndex
          ? insertionIndex - 1
          : insertionIndex
        try document.moveSection(
          id: sectionID,
          to: StructuredNoteSectionDestination(
            parent: .root,
            index: destinationIndex
          )
        )
      }

    case .group(let groupID, let insertionIndex):
      guard let group = group(groupID, in: document) else {
        throw StructuredNoteDocumentError.groupNotFound(groupID)
      }
      guard (0...group.sections.count).contains(insertionIndex) else {
        throw StructuredNoteDocumentError.invalidDestinationIndex(insertionIndex)
      }

      let destinationIndex: Int
      if origin.parent == .group(groupID) {
        destinationIndex = normalizedInsertionIndex(insertionIndex, removingItemAt: origin.index)
        guard destinationIndex != origin.index else {
          return StructuredNoteDropResult(didChange: false, focusedSectionID: sectionID)
        }
      } else {
        destinationIndex = insertionIndex
      }

      try document.moveSection(
        id: sectionID,
        to: StructuredNoteSectionDestination(
          parent: .group(groupID),
          index: destinationIndex
        )
      )
    }

    return StructuredNoteDropResult(didChange: true, focusedSectionID: sectionID)
  }

  // Converts a gap index from the original collection into an index after source removal.
  private static func normalizedInsertionIndex(
    _ insertionIndex: Int,
    removingItemAt sourceIndex: Int
  ) -> Int {
    sourceIndex < insertionIndex ? insertionIndex - 1 : insertionIndex
  }

  // Finds a section and the root/group counts needed to normalize a drop target.
  private static func sectionOrigin(
    _ sectionID: UUID,
    in document: StructuredNoteDocument
  ) -> SectionOrigin? {
    for (rootNodeIndex, node) in document.nodes.enumerated() {
      switch node {
      case .section(let section) where section.id == sectionID:
        return SectionOrigin(
          parent: .root,
          index: rootNodeIndex,
          rootNodeIndex: rootNodeIndex,
          parentSectionCount: document.nodes.count
        )

      case .group(let group):
        guard let sectionIndex = group.sections.firstIndex(where: { $0.id == sectionID })
        else { continue }
        return SectionOrigin(
          parent: .group(group.id),
          index: sectionIndex,
          rootNodeIndex: rootNodeIndex,
          parentSectionCount: group.sections.count
        )

      default:
        continue
      }
    }
    return nil
  }

  // Finds one group without exposing storage traversal to the SwiftUI drop layer.
  private static func group(
    _ groupID: UUID,
    in document: StructuredNoteDocument
  ) -> StructuredSectionGroup? {
    for node in document.nodes {
      guard case .group(let group) = node, group.id == groupID else { continue }
      return group
    }
    return nil
  }
}
