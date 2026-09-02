//
//  StructuredNoteEditorCoordinator.swift
//

// Shared focus and structural undo state for the multi-section structured editor.

import Combine
import Foundation

enum StructuredEditorCaretPlacement: Equatable {
  case preserve
  case start
  case end
}

enum StructuredEditorBoundaryNavigation: Equatable {
  case previousSectionEnd
  case nextSectionStart
}

@MainActor
final class StructuredNoteEditorCoordinator: ObservableObject {
  struct FocusRequest: Equatable {
    let id = UUID()
    let sectionID: UUID
    let caretPlacement: StructuredEditorCaretPlacement
  }

  struct FocusTarget: Equatable {
    let sectionID: UUID
    let caretPlacement: StructuredEditorCaretPlacement

    init(
      sectionID: UUID,
      caretPlacement: StructuredEditorCaretPlacement = .preserve
    ) {
      self.sectionID = sectionID
      self.caretPlacement = caretPlacement
    }
  }

  @Published private(set) var focusedSectionID: UUID?
  @Published private(set) var focusRequest: FocusRequest?
  private(set) var activeDocumentID: String?
  let structuralUndoManager = UndoManager()
  private var orderedSectionIDs: [UUID] = []
  private var prioritizesStructuralUndo = false

  // Resets document-scoped undo state and focuses the first editable section once.
  func activate(documentID: String, initialSectionID: UUID?) {
    guard activeDocumentID != documentID else { return }
    activeDocumentID = documentID
    focusedSectionID = nil
    focusRequest = nil
    orderedSectionIDs = []
    prioritizesStructuralUndo = false
    structuralUndoManager.removeAllActions()

    if let initialSectionID {
      requestFocus(sectionID: initialSectionID)
    }
  }

  // Publishes a new token so the requested AppKit section editor becomes first responder.
  func requestFocus(
    sectionID: UUID,
    caretPlacement: StructuredEditorCaretPlacement = .preserve
  ) {
    focusedSectionID = sectionID
    focusRequest = FocusRequest(sectionID: sectionID, caretPlacement: caretPlacement)
  }

  // Tracks direct mouse or keyboard focus changes reported by a section editor.
  func didFocus(sectionID: UUID) {
    focusedSectionID = sectionID
  }

  // Keeps boundary navigation aligned with the currently visible document order.
  func updateSectionOrder(_ sectionIDs: [UUID]) {
    orderedSectionIDs = sectionIDs
    guard let focusedSectionID, !sectionIDs.contains(focusedSectionID) else { return }
    self.focusedSectionID = nil
    focusRequest = nil
  }

  // Moves focus across a section boundary and places the caret at the matching edge.
  func navigate(
    from sectionID: UUID,
    direction: StructuredEditorBoundaryNavigation
  ) -> Bool {
    guard let sectionIndex = orderedSectionIDs.firstIndex(of: sectionID) else { return false }

    switch direction {
    case .previousSectionEnd:
      guard sectionIndex > orderedSectionIDs.startIndex else { return false }
      requestFocus(
        sectionID: orderedSectionIDs[sectionIndex - 1],
        caretPlacement: .end
      )
    case .nextSectionStart:
      guard orderedSectionIDs.indices.contains(sectionIndex + 1) else { return false }
      requestFocus(
        sectionID: orderedSectionIDs[sectionIndex + 1],
        caretPlacement: .start
      )
    }
    return true
  }

  // Drops stale structural snapshots once later text could be overwritten by restoring them.
  func didEditText() {
    structuralUndoManager.removeAllActions()
    prioritizesStructuralUndo = false
  }

  // Invalidates structural history after non-section document metadata changes.
  func invalidateStructuralUndo() {
    structuralUndoManager.removeAllActions()
    prioritizesStructuralUndo = false
  }

  // Handles Command-Z only while a structural action is the most recent editor change.
  func undoStructuralChangeIfPreferred() -> Bool {
    guard prioritizesStructuralUndo, structuralUndoManager.canUndo else { return false }
    structuralUndoManager.undo()
    return true
  }

  // Handles Command-Shift-Z after a structural undo without stealing normal text redo.
  func redoStructuralChangeIfPreferred() -> Bool {
    guard prioritizesStructuralUndo, structuralUndoManager.canRedo else { return false }
    structuralUndoManager.redo()
    return true
  }

  // Exposes structural undo to the section options menu.
  func undoStructuralChange() {
    guard structuralUndoManager.canUndo else { return }
    prioritizesStructuralUndo = true
    structuralUndoManager.undo()
  }

  // Exposes structural redo to the section options menu.
  func redoStructuralChange() {
    guard structuralUndoManager.canRedo else { return }
    prioritizesStructuralUndo = true
    structuralUndoManager.redo()
  }

  // Applies a structural snapshot and registers its inverse with the shared undo manager.
  func commitStructuralChange(
    from previousDocument: StructuredNoteDocument,
    to updatedDocument: StructuredNoteDocument,
    actionName: String,
    undoFocusTarget: FocusTarget? = nil,
    redoFocusTarget: FocusTarget? = nil,
    apply: @escaping (StructuredNoteDocument) -> Void
  ) {
    guard previousDocument != updatedDocument else { return }
    apply(updatedDocument)
    prioritizesStructuralUndo = true
    registerStructuralUndo(
      restoring: previousDocument,
      replacing: updatedDocument,
      actionName: actionName,
      restoringFocusTarget: undoFocusTarget,
      replacingFocusTarget: redoFocusTarget,
      apply: apply
    )
  }

  // Registers alternating document snapshots so UndoManager automatically supports redo.
  private func registerStructuralUndo(
    restoring document: StructuredNoteDocument,
    replacing currentDocument: StructuredNoteDocument,
    actionName: String,
    restoringFocusTarget: FocusTarget?,
    replacingFocusTarget: FocusTarget?,
    apply: @escaping (StructuredNoteDocument) -> Void
  ) {
    structuralUndoManager.registerUndo(withTarget: self) { coordinator in
      coordinator.registerStructuralUndo(
        restoring: currentDocument,
        replacing: document,
        actionName: actionName,
        restoringFocusTarget: replacingFocusTarget,
        replacingFocusTarget: restoringFocusTarget,
        apply: apply
      )
      apply(document)
      if let restoringFocusTarget {
        coordinator.requestFocus(
          sectionID: restoringFocusTarget.sectionID,
          caretPlacement: restoringFocusTarget.caretPlacement
        )
      }
    }
    structuralUndoManager.setActionName(actionName)
  }
}
