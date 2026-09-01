//
//  StructuredNoteEditorCoordinator.swift
//

// Shared focus and structural undo state for the multi-section structured editor.

import Combine
import Foundation

@MainActor
final class StructuredNoteEditorCoordinator: ObservableObject {
  struct FocusRequest: Equatable {
    let id = UUID()
    let sectionID: UUID
  }

  @Published private(set) var focusedSectionID: UUID?
  @Published private(set) var focusRequest: FocusRequest?
  private(set) var activeDocumentID: String?
  let structuralUndoManager = UndoManager()

  // Resets document-scoped undo state and focuses the first editable section once.
  func activate(documentID: String, initialSectionID: UUID?) {
    guard activeDocumentID != documentID else { return }
    activeDocumentID = documentID
    focusedSectionID = nil
    focusRequest = nil
    structuralUndoManager.removeAllActions()

    if let initialSectionID {
      requestFocus(sectionID: initialSectionID)
    }
  }

  // Publishes a new token so the requested AppKit section editor becomes first responder.
  func requestFocus(sectionID: UUID) {
    focusedSectionID = sectionID
    focusRequest = FocusRequest(sectionID: sectionID)
  }

  // Tracks direct mouse or keyboard focus changes reported by a section editor.
  func didFocus(sectionID: UUID) {
    focusedSectionID = sectionID
  }

  // Applies a structural snapshot and registers its inverse with the shared undo manager.
  func commitStructuralChange(
    from previousDocument: StructuredNoteDocument,
    to updatedDocument: StructuredNoteDocument,
    actionName: String,
    apply: @escaping (StructuredNoteDocument) -> Void
  ) {
    guard previousDocument != updatedDocument else { return }
    apply(updatedDocument)
    registerStructuralUndo(
      restoring: previousDocument,
      replacing: updatedDocument,
      actionName: actionName,
      apply: apply
    )
  }

  // Registers alternating document snapshots so UndoManager automatically supports redo.
  private func registerStructuralUndo(
    restoring document: StructuredNoteDocument,
    replacing currentDocument: StructuredNoteDocument,
    actionName: String,
    apply: @escaping (StructuredNoteDocument) -> Void
  ) {
    structuralUndoManager.registerUndo(withTarget: self) { coordinator in
      coordinator.registerStructuralUndo(
        restoring: currentDocument,
        replacing: document,
        actionName: actionName,
        apply: apply
      )
      apply(document)
    }
    structuralUndoManager.setActionName(actionName)
  }
}
