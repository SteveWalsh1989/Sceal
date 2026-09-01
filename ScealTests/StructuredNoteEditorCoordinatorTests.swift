import XCTest

@testable import Sceal

@MainActor
final class StructuredNoteEditorCoordinatorTests: XCTestCase {
  // Retains focus state for redraws and resets it when a different document becomes active.
  func testActivateScopesFocusStateToDocument() throws {
    let coordinator = StructuredNoteEditorCoordinator()
    let firstSectionID = UUID()
    let secondSectionID = UUID()

    coordinator.activate(documentID: "2026-06-08", initialSectionID: firstSectionID)
    let firstRequest = try XCTUnwrap(coordinator.focusRequest)
    coordinator.activate(documentID: "2026-06-08", initialSectionID: secondSectionID)

    XCTAssertEqual(coordinator.focusedSectionID, firstSectionID)
    XCTAssertEqual(coordinator.focusRequest, firstRequest)

    coordinator.activate(documentID: "2026-06-09", initialSectionID: secondSectionID)

    XCTAssertEqual(coordinator.activeDocumentID, "2026-06-09")
    XCTAssertEqual(coordinator.focusedSectionID, secondSectionID)
    XCTAssertEqual(coordinator.focusRequest?.sectionID, secondSectionID)
    XCTAssertNotEqual(coordinator.focusRequest?.id, firstRequest.id)
  }

  // Restores complete structural snapshots in both undo and redo directions.
  func testStructuralChangeSupportsUndoAndRedo() {
    let coordinator = StructuredNoteEditorCoordinator()
    let section = StructuredNoteSection(markdown: "Before")
    let previousDocument = StructuredNoteDocument(
      id: "2026-06-10",
      date: Date(timeIntervalSince1970: 1_781_049_600),
      title: "Before",
      tags: [],
      nodes: [.section(section)]
    )
    var updatedDocument = previousDocument
    updatedDocument.title = "After"
    var appliedDocument = previousDocument

    coordinator.commitStructuralChange(
      from: previousDocument,
      to: updatedDocument,
      actionName: "Edit Structure",
      undoFocusTarget: .init(sectionID: section.id, caretPlacement: .start),
      redoFocusTarget: .init(sectionID: section.id, caretPlacement: .end)
    ) { document in
      appliedDocument = document
    }

    XCTAssertEqual(appliedDocument, updatedDocument)
    XCTAssertTrue(coordinator.structuralUndoManager.canUndo)

    coordinator.structuralUndoManager.undo()
    XCTAssertEqual(appliedDocument, previousDocument)
    XCTAssertTrue(coordinator.structuralUndoManager.canRedo)
    XCTAssertEqual(coordinator.focusRequest?.caretPlacement, .start)

    coordinator.structuralUndoManager.redo()
    XCTAssertEqual(appliedDocument, updatedDocument)
    XCTAssertEqual(coordinator.focusRequest?.caretPlacement, .end)
  }

  // Restores a drag mutation exactly, including group ownership and section state.
  func testDragSnapshotSupportsUndoAndRedo() throws {
    let coordinator = StructuredNoteEditorCoordinator()
    let rootSection = StructuredNoteSection(markdown: "Root")
    let groupedSection = StructuredNoteSection(
      markdown: "Grouped",
      styleOverrides: StructuredSectionStyleOverrides(
        backgroundColor: .colorName("purple")
      ),
      isCollapsed: true
    )
    let group = StructuredSectionGroup(
      title: "Feature",
      style: StructuredSectionStyle(borderColorName: "blue"),
      sections: [groupedSection]
    )
    let previousDocument = StructuredNoteDocument(
      id: "2026-06-13",
      date: Date(timeIntervalSince1970: 1_781_308_800),
      title: "Drag undo",
      tags: [],
      nodes: [.section(rootSection), .group(group)]
    )
    var updatedDocument = previousDocument
    let dragResult = try StructuredNoteDragDrop.apply(
      .section(rootSection.id),
      to: .group(groupID: group.id, insertionIndex: 1),
      in: &updatedDocument
    )
    var appliedDocument = previousDocument

    coordinator.commitStructuralChange(
      from: previousDocument,
      to: updatedDocument,
      actionName: "Move Section",
      undoFocusTarget: .init(sectionID: rootSection.id, caretPlacement: .end),
      redoFocusTarget: dragResult.focusedSectionID.map {
        .init(sectionID: $0, caretPlacement: .start)
      }
    ) { appliedDocument = $0 }

    XCTAssertEqual(appliedDocument, updatedDocument)

    coordinator.structuralUndoManager.undo()
    XCTAssertEqual(appliedDocument, previousDocument)
    XCTAssertEqual(coordinator.focusRequest?.sectionID, rootSection.id)

    coordinator.structuralUndoManager.redo()
    XCTAssertEqual(appliedDocument, updatedDocument)
    XCTAssertEqual(coordinator.focusRequest?.sectionID, rootSection.id)
  }

  // Traverses the flattened section order and requests the correct caret edge.
  func testBoundaryNavigationTargetsAdjacentSectionEdges() throws {
    let coordinator = StructuredNoteEditorCoordinator()
    let firstSectionID = UUID()
    let secondSectionID = UUID()
    let thirdSectionID = UUID()
    coordinator.activate(documentID: "2026-06-11", initialSectionID: firstSectionID)
    coordinator.updateSectionOrder([firstSectionID, secondSectionID, thirdSectionID])

    XCTAssertTrue(
      coordinator.navigate(from: secondSectionID, direction: .previousSectionEnd)
    )
    XCTAssertEqual(coordinator.focusRequest?.sectionID, firstSectionID)
    XCTAssertEqual(coordinator.focusRequest?.caretPlacement, .end)

    XCTAssertTrue(coordinator.navigate(from: secondSectionID, direction: .nextSectionStart))
    XCTAssertEqual(coordinator.focusRequest?.sectionID, thirdSectionID)
    XCTAssertEqual(coordinator.focusRequest?.caretPlacement, .start)
    XCTAssertFalse(coordinator.navigate(from: firstSectionID, direction: .previousSectionEnd))
    XCTAssertFalse(coordinator.navigate(from: thirdSectionID, direction: .nextSectionStart))
  }

  // Keeps structural Command-Z priority until the user resumes ordinary text editing.
  func testStructuralUndoPriorityEndsAfterTextEdit() {
    let coordinator = StructuredNoteEditorCoordinator()
    let previousDocument = StructuredNoteDocument.empty(
      id: "2026-06-12",
      date: Date(timeIntervalSince1970: 1_781_222_400)
    )
    var updatedDocument = previousDocument
    updatedDocument.title = "Updated"
    var appliedDocument = previousDocument

    coordinator.commitStructuralChange(
      from: previousDocument,
      to: updatedDocument,
      actionName: "Edit Structure"
    ) { appliedDocument = $0 }

    XCTAssertTrue(coordinator.undoStructuralChangeIfPreferred())
    XCTAssertEqual(appliedDocument, previousDocument)
    XCTAssertTrue(coordinator.redoStructuralChangeIfPreferred())
    XCTAssertEqual(appliedDocument, updatedDocument)

    coordinator.didEditText()
    XCTAssertFalse(coordinator.undoStructuralChangeIfPreferred())
    XCTAssertFalse(coordinator.structuralUndoManager.canUndo)
    XCTAssertEqual(appliedDocument, updatedDocument)
  }
}
