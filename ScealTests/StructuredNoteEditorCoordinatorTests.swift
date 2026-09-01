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
      actionName: "Edit Structure"
    ) { document in
      appliedDocument = document
    }

    XCTAssertEqual(appliedDocument, updatedDocument)
    XCTAssertTrue(coordinator.structuralUndoManager.canUndo)

    coordinator.structuralUndoManager.undo()
    XCTAssertEqual(appliedDocument, previousDocument)
    XCTAssertTrue(coordinator.structuralUndoManager.canRedo)

    coordinator.structuralUndoManager.redo()
    XCTAssertEqual(appliedDocument, updatedDocument)
  }
}
