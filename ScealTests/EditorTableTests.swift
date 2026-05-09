import AppKit
import XCTest

@testable import Sceal

@MainActor
final class EditorTableTests: EditorTestCase {
  func testTableRoundTripPreservesRichCellMarkdownAndSurroundingSections() {
    let table = MarkdownEditorTable(
      runtimeID: "test",
      hasHeader: true,
      columnWidths: [160, 220],
      rows: [
        ["**Topic**", "[Docs](https://example.com)"],
        ["- Bullet\n- [ ] Task", "`code` and *italic*"],
        ["", "Plain"],
      ]
    )
    let markdown = """
      <!-- section -->
      \(MarkdownEditorTableMarkdown.serialize(table))
      After
      """

    let display = MarkdownEditorFormatter.formatForDisplay(markdown, appearance: appearance)
    XCTAssertEqual(MarkdownEditorFormatter.convertToMarkdown(from: display), markdown)
  }

  func testTableRoundTripPreservesEmptyCells() {
    let table = MarkdownEditorTable(
      runtimeID: "test",
      hasHeader: false,
      columnWidths: [180, 180],
      rows: [
        ["", ""],
        ["Left", ""],
      ]
    )
    let markdown = MarkdownEditorTableMarkdown.serialize(table)

    let display = MarkdownEditorFormatter.formatForDisplay(markdown, appearance: appearance)
    XCTAssertEqual(MarkdownEditorFormatter.convertToMarkdown(from: display), markdown)
  }

  func testTableRoundTripPreservesFullWidthState() {
    let table = MarkdownEditorTable(
      runtimeID: "test",
      hasHeader: false,
      isFullWidth: true,
      columnWidths: [180, 220],
      rows: [["Left", "Right"]]
    )
    let markdown = MarkdownEditorTableMarkdown.serialize(table)

    let display = MarkdownEditorFormatter.formatForDisplay(markdown, appearance: appearance)
    let converted = MarkdownEditorFormatter.convertToMarkdown(from: display)

    XCTAssertTrue(converted.contains("fullwidth:true"))
  }

  func testDirectTableSlashCommandInsertsDefaultTableAndBlankParagraph() {
    assertTableSlashCommand(command: "/table", primesSlashPopup: false)
  }

  func testPopupTableSlashCommandInsertsDefaultTableAndBlankParagraph() {
    assertTableSlashCommand(command: "/ta", primesSlashPopup: true)
  }

  func testTableActionsMutateOnlyTheTableBlock() {
    let table = MarkdownEditorTable.empty()
    let markdown = """
      <!-- section -->
      \(MarkdownEditorTableMarkdown.serialize(table))
      Body
      """
    let fixture = makeEditorFixture(markdown: markdown)
    let textView = fixture.textView
    let tableID = firstTableID(in: textView)

    textView.applyTableAction(.toggleHeader, tableID: tableID, row: 0, column: 0)
    textView.applyTableAction(.addColumnAfter, tableID: tableID, row: 0, column: 0)
    textView.applyTableAction(.addRowBelow, tableID: tableID, row: 1, column: 0)

    let converted = MarkdownEditorFormatter.convertToMarkdown(from: textView.textStorage!)
    XCTAssertTrue(converted.hasPrefix("<!-- section -->\n<!-- sceal-table"))
    XCTAssertTrue(converted.contains("columns:3 header:true"))
    XCTAssertTrue(converted.hasSuffix("\nBody"))
  }

  func testDeleteRowAndColumnAreDisabledAtMinimumTableSize() {
    let table = MarkdownEditorTable(
      runtimeID: "test",
      hasHeader: false,
      columnWidths: [180],
      rows: [["Only"]]
    )
    let fixture = makeEditorFixture(markdown: MarkdownEditorTableMarkdown.serialize(table))
    let textView = fixture.textView
    let tableID = firstTableID(in: textView)

    textView.applyTableAction(.deleteColumn, tableID: tableID, row: 0, column: 0)
    textView.applyTableAction(.deleteRow, tableID: tableID, row: 0, column: 0)

    let converted = MarkdownEditorFormatter.convertToMarkdown(from: textView.textStorage!)
    XCTAssertTrue(converted.contains("columns:1 header:false"))
    XCTAssertEqual(converted.components(separatedBy: "<!-- cell r:").count - 1, 1)
    XCTAssertTrue(converted.contains("Only"))
  }

  func testHeaderTableDeleteRowIsDisabledWhenItWouldRemoveLastBodyRow() {
    let table = MarkdownEditorTable(
      runtimeID: "test",
      hasHeader: true,
      columnWidths: [180],
      rows: [["Head"], ["Body"]]
    )
    let fixture = makeEditorFixture(markdown: MarkdownEditorTableMarkdown.serialize(table))
    let textView = fixture.textView
    let tableID = firstTableID(in: textView)

    textView.applyTableAction(.deleteRow, tableID: tableID, row: 0, column: 0)
    textView.applyTableAction(.deleteRow, tableID: tableID, row: 1, column: 0)

    let converted = MarkdownEditorFormatter.convertToMarkdown(from: textView.textStorage!)
    XCTAssertTrue(converted.contains("columns:1 header:true"))
    XCTAssertEqual(converted.components(separatedBy: "<!-- cell r:").count - 1, 2)
    XCTAssertTrue(converted.contains("Head"))
    XCTAssertTrue(converted.contains("Body"))
  }

  func testTableCellEnterContinuesBulletList() {
    let table = MarkdownEditorTable(
      runtimeID: "test",
      hasHeader: false,
      columnWidths: [180, 180],
      rows: [["- Item", ""]]
    )
    let tableView = EditorTableBlockView(table: table, appearanceSettings: appearance)
    guard let cellTextView = tableView.textViewForCell(row: 0, column: 0) else {
      return XCTFail("Expected table cell text view.")
    }

    cellTextView.setSelectedRange(NSRange(location: cellTextView.string.utf16.count, length: 0))
    XCTAssertTrue(
      tableView.textView(cellTextView, doCommandBy: #selector(NSResponder.insertNewline(_:)))
    )

    XCTAssertEqual(
      MarkdownEditorFormatter.convertToMarkdown(from: cellTextView.textStorage!),
      "- Item\n- "
    )
  }

  func testTableRowHeightFitsChecklistContent() {
    let singleItemTable = MarkdownEditorTable(
      runtimeID: "test",
      hasHeader: false,
      columnWidths: [180, 180],
      rows: [["- [ ] First", ""]]
    )
    let multiItemTable = MarkdownEditorTable(
      runtimeID: "test",
      hasHeader: false,
      columnWidths: [180, 180],
      rows: [["- [ ] First\n- [ ] Second\n- [ ] Third", ""]]
    )

    let singleItemHeight = MarkdownEditorTableMetrics.rowHeights(
      for: singleItemTable,
      appearance: appearance
    )[0]
    let multiItemHeight = MarkdownEditorTableMetrics.rowHeights(
      for: multiItemTable,
      appearance: appearance
    )[0]

    XCTAssertGreaterThan(multiItemHeight, singleItemHeight + 20)
  }

  func testTableRowHeightExpandsForWrappedFormattedCellContent() {
    let table = MarkdownEditorTable(
      runtimeID: "test",
      hasHeader: false,
      columnWidths: [120],
      rows: [["- [ ] A long checklist item that should wrap inside a narrow table column"]]
    )

    let rowHeight = MarkdownEditorTableMetrics.rowHeights(
      for: table,
      appearance: appearance
    )[0]

    XCTAssertGreaterThan(rowHeight, MarkdownEditorTableMetrics.minimumRowHeight)
  }

  func testTableBodyCellsKeepTransparentBackground() {
    let tableView = EditorTableBlockView(
      table: MarkdownEditorTable.empty(),
      appearanceSettings: appearance
    )

    guard let bodyCell = tableView.textViewForCell(row: 1, column: 0) else {
      return XCTFail("Expected a body cell text view.")
    }

    XCTAssertFalse(bodyCell.drawsBackground)
  }

  func testTableToolbarButtonsAreIconOnlyAndVisibleOnHover() {
    let tableView = EditorTableBlockView(
      table: MarkdownEditorTable.empty(),
      appearanceSettings: appearance
    )
    tableView.frame = NSRect(
      x: 0,
      y: 0,
      width: EditorTableBlockView.minimumOverlayWidth,
      height: 196
    )
    tableView.positionTableContent(
      topInset: EditorTableBlockView.toolbarReservedHeight,
      leftInset: 0
    )
    tableView.layoutSubtreeIfNeeded()

    guard
      let hoverEvent = NSEvent.mouseEvent(
        with: .mouseMoved,
        location: NSPoint(x: 20, y: 20),
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        eventNumber: 0,
        clickCount: 0,
        pressure: 0
      )
    else {
      return XCTFail("Expected a hover event.")
    }
    tableView.mouseEntered(with: hoverEvent)
    tableView.layoutSubtreeIfNeeded()

    let toolbarContainers = tableView.subviews.compactMap { $0 as? NSVisualEffectView }
    XCTAssertEqual(toolbarContainers.count, 1)
    guard let toolbarContainer = toolbarContainers.first else {
      return XCTFail("Expected one toolbar container.")
    }
    XCTAssertEqual(toolbarContainer.isHidden, false)
    XCTAssertLessThanOrEqual(
      toolbarContainer.frame.maxY,
      tableView.textViewForCell(row: 0, column: 0)?.frame.minY ?? 0
    )

    let buttons = toolbarButtons(in: tableView)
    XCTAssertEqual(buttons.count, 8)
    XCTAssertTrue(buttons.allSatisfy { $0.title.isEmpty })
    XCTAssertTrue(buttons.allSatisfy { $0.image != nil })
    XCTAssertTrue(buttons.allSatisfy { $0.imagePosition == .imageOnly })
    XCTAssertTrue(buttons.allSatisfy { ($0.toolTip ?? "").isEmpty == false })
  }

  func testToolbarInsetKeepsCellsClickable() {
    let tableView = EditorTableBlockView(
      table: MarkdownEditorTable.empty(),
      appearanceSettings: appearance
    )
    tableView.frame = NSRect(
      x: 0,
      y: 0,
      width: 360,
      height: 196
    )
    tableView.positionTableContent(
      topInset: EditorTableBlockView.toolbarReservedHeight,
      leftInset: 0
    )
    tableView.layoutSubtreeIfNeeded()

    guard let cellTextView = tableView.textViewForCell(row: 0, column: 0) else {
      return XCTFail("Expected a table cell text view.")
    }

    let hitPoint = NSPoint(x: cellTextView.frame.midX, y: cellTextView.frame.midY)
    let hitView = tableView.hitTest(hitPoint)
    XCTAssertTrue(hitView === cellTextView || hitView?.isDescendant(of: cellTextView) == true)
  }

  func testColumnResizeHitTargetIsComfortableNearBorder() {
    let table = MarkdownEditorTable(
      runtimeID: "test",
      hasHeader: false,
      columnWidths: [180, 180],
      rows: [["A", "B"]]
    )
    let tableView = EditorTableBlockView(table: table, appearanceSettings: appearance)
    tableView.frame = NSRect(x: 0, y: 0, width: 420, height: 88)
    tableView.layoutSubtreeIfNeeded()

    XCTAssertTrue(tableView.hitTest(NSPoint(x: 187, y: 20)) === tableView)
    XCTAssertTrue(tableView.hitTest(NSPoint(x: 367, y: 20)) === tableView)
  }

  func testRightTableBorderResizesLastColumnWithoutMaximumCap() {
    let table = MarkdownEditorTable(
      runtimeID: "test",
      hasHeader: false,
      columnWidths: [180, 180],
      rows: [["A", "B"]]
    )
    let tableView = EditorTableBlockView(table: table, appearanceSettings: appearance)
    tableView.frame = NSRect(x: 0, y: 0, width: 1_000, height: 88)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1_000, height: 120),
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )
    window.contentView?.addSubview(tableView)
    tableView.layoutSubtreeIfNeeded()

    tableView.mouseDown(
      with: tableMouseEvent(
        type: .leftMouseDown,
        location: tableView.convert(NSPoint(x: 360, y: 20), to: nil)
      )
    )
    tableView.mouseDragged(
      with: tableMouseEvent(
        type: .leftMouseDragged,
        location: tableView.convert(NSPoint(x: 900, y: 20), to: nil)
      )
    )
    tableView.mouseUp(
      with: tableMouseEvent(
        type: .leftMouseUp,
        location: tableView.convert(NSPoint(x: 900, y: 20), to: nil)
      )
    )

    XCTAssertEqual(tableView.table.columnWidths, [180, 720])
    XCTAssertEqual(MarkdownEditorTable.clampedColumnWidth(1_200), 1_200)
  }

  func testRightTableBorderResizeIsLimitedToAvailableEditorWidth() {
    let table = MarkdownEditorTable(
      runtimeID: "test",
      hasHeader: false,
      columnWidths: [180, 180],
      rows: [["A", "B"]]
    )
    let tableView = EditorTableBlockView(table: table, appearanceSettings: appearance)
    tableView.frame = NSRect(x: 0, y: 0, width: 500, height: 88)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 500, height: 120),
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )
    window.contentView?.addSubview(tableView)
    tableView.update(table: table, availableWidth: 420)
    tableView.layoutSubtreeIfNeeded()

    tableView.mouseDown(
      with: tableMouseEvent(
        type: .leftMouseDown,
        location: tableView.convert(NSPoint(x: 360, y: 20), to: nil)
      )
    )
    tableView.mouseDragged(
      with: tableMouseEvent(
        type: .leftMouseDragged,
        location: tableView.convert(NSPoint(x: 900, y: 20), to: nil)
      )
    )
    tableView.mouseUp(
      with: tableMouseEvent(
        type: .leftMouseUp,
        location: tableView.convert(NSPoint(x: 900, y: 20), to: nil)
      )
    )

    XCTAssertEqual(tableView.table.columnWidths.reduce(0, +), 420)
    XCTAssertEqual(tableView.table.columnWidths, [180, 240])
  }

  func testFullWidthTableActionFillsAvailableEditorWidth() {
    let table = MarkdownEditorTable(
      runtimeID: "test",
      hasHeader: false,
      columnWidths: [120, 180],
      rows: [["A", "B"]]
    )
    let tableView = EditorTableBlockView(table: table, appearanceSettings: appearance)
    tableView.update(table: table, availableWidth: 480)

    tableView.apply(.toggleFullWidth)

    XCTAssertTrue(tableView.table.isFullWidth)
    XCTAssertEqual(tableView.table.columnWidths.reduce(0, +), 480, accuracy: 0.01)
  }

  func testTableConstrainedToAvailableWidthShrinksProportionally() {
    let table = MarkdownEditorTable(
      runtimeID: "test",
      hasHeader: false,
      columnWidths: [300, 300],
      rows: [["A", "B"]]
    )

    let constrained = table.constrained(toAvailableWidth: 420)

    XCTAssertEqual(constrained.columnWidths.reduce(0, +), 420, accuracy: 0.01)
    XCTAssertEqual(constrained.columnWidths, [210, 210])
  }

  func testEditorSyncConstrainsTableToEditorWidth() {
    let table = MarkdownEditorTable(
      runtimeID: "test",
      hasHeader: false,
      columnWidths: [600, 600],
      rows: [["A", "B"]]
    )
    let fixture = makeEditorFixture(markdown: MarkdownEditorTableMarkdown.serialize(table))
    let textView = fixture.textView

    textView.syncTableBlockViews()

    XCTAssertLessThanOrEqual(
      firstTableModel(in: textView).columnWidths.reduce(0, +),
      textView.bounds.width
    )
  }

  func testEditorHitTestRoutesTableCellClicksToCellTextView() {
    let table = MarkdownEditorTable(
      runtimeID: "test",
      hasHeader: false,
      columnWidths: [180, 180],
      rows: [["A", "B"]]
    )
    let fixture = makeEditorFixture(markdown: MarkdownEditorTableMarkdown.serialize(table))
    let textView = fixture.textView
    textView.syncTableBlockViews()

    guard let tableView = textView.subviews.compactMap({ $0 as? EditorTableBlockView }).first,
      let secondCell = tableView.textViewForCell(row: 0, column: 1)
    else {
      return XCTFail("Expected a rendered table cell.")
    }

    let cellPoint = NSPoint(x: secondCell.frame.midX, y: secondCell.frame.midY)
    let editorPoint = textView.convert(cellPoint, from: tableView)
    let hitView = textView.hitTest(editorPoint)

    XCTAssertTrue(hitView === secondCell || hitView?.isDescendant(of: secondCell) == true)
  }

  func testFocusedTableCellUpdatesActionContext() {
    let table = MarkdownEditorTable(
      runtimeID: "test",
      hasHeader: false,
      columnWidths: [180, 180],
      rows: [["A", "B"]]
    )
    let tableView = EditorTableBlockView(table: table, appearanceSettings: appearance)
    tableView.frame = NSRect(x: 0, y: 0, width: 360, height: 88)
    tableView.layoutSubtreeIfNeeded()

    tableView.focusCell(row: 0, column: 1)
    tableView.apply(.addColumnAfter)

    XCTAssertEqual(tableView.table.rows[0], ["A", "B", ""])
  }

  func testDeleteTableBlockRemovesOnlyTable() {
    let table = MarkdownEditorTable.empty()
    let markdown = """
      Before
      \(MarkdownEditorTableMarkdown.serialize(table))
      After
      """
    let fixture = makeEditorFixture(markdown: markdown)
    let textView = fixture.textView
    let tableID = firstTableID(in: textView)

    guard let textStorage = textView.textStorage else {
      return XCTFail("Expected text storage.")
    }
    var tableRange: NSRange?
    textStorage.enumerateAttribute(
      .markdownTableID,
      in: NSRange(location: 0, length: textStorage.length),
      options: []
    ) { value, range, stop in
      guard value as? String == tableID else { return }
      tableRange = range
      stop.pointee = true
    }

    guard let tableRange else {
      return XCTFail("Expected a table range.")
    }
    let tableRect = textView.editorRectInViewCoordinates(forCharacterRange: tableRange) ?? .zero
    let clickPoint = NSPoint(x: tableRect.maxX + 12, y: tableRect.midY)
    guard
      let event = NSEvent.mouseEvent(
        with: .leftMouseDown,
        location: textView.convert(clickPoint, to: nil),
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        eventNumber: 0,
        clickCount: 1,
        pressure: 0
      )
    else {
      return XCTFail("Expected a mouse event.")
    }

    textView.mouseDown(with: event)

    let converted = MarkdownEditorFormatter.convertToMarkdown(from: textView.textStorage!)
    XCTAssertFalse(converted.contains("<!-- sceal-table"))
    XCTAssertTrue(converted.contains("Before"))
    XCTAssertTrue(converted.contains("After"))
  }

  func testPastingMarkdownPipeTableInsertsScealTable() {
    let fixture = makeRawEditorFixture(string: "")
    let textView = fixture.textView
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(
      """
      | Name | Status |
      | --- | --- |
      | Alpha | Done |
      """,
      forType: .string
    )

    textView.paste(nil)

    let converted = MarkdownEditorFormatter.convertToMarkdown(from: textView.textStorage!)
    XCTAssertTrue(converted.contains("<!-- sceal-table v:1 columns:2 header:true"))
    XCTAssertTrue(converted.contains("Alpha"))
    XCTAssertFalse(converted.contains("| --- |"))
  }

  func testPastingTSVInsertsScealTable() {
    let fixture = makeRawEditorFixture(string: "")
    let textView = fixture.textView
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString("A\tB\n1\t2", forType: .string)

    textView.paste(nil)

    let converted = MarkdownEditorFormatter.convertToMarkdown(from: textView.textStorage!)
    XCTAssertTrue(converted.contains("<!-- sceal-table v:1 columns:2 header:false"))
    XCTAssertTrue(converted.contains("<!-- cell r:1 c:1 -->\n2"))
  }

  func testPastingHTMLTableInsertsScealTable() {
    let fixture = makeRawEditorFixture(string: "")
    let textView = fixture.textView
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(
      "<table><tr><th>Name</th><th>Status</th></tr><tr><td>Alpha</td><td>Done</td></tr></table>",
      forType: .html
    )
    NSPasteboard.general.setString("Name Status", forType: .string)

    textView.paste(nil)

    let converted = MarkdownEditorFormatter.convertToMarkdown(from: textView.textStorage!)
    XCTAssertTrue(converted.contains("<!-- sceal-table v:1 columns:2 header:true"))
    XCTAssertTrue(converted.contains("Alpha"))
    XCTAssertTrue(converted.contains("Done"))
  }

  private func assertTableSlashCommand(
    command: String,
    primesSlashPopup: Bool,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let markdown = MarkdownBox(command)
    let coordinator = makeCoordinator(markdown: markdown)
    let fixture = makeRawEditorFixture(string: command)
    let textView = fixture.textView

    textView.delegate = coordinator
    textView.setSelectedRange(NSRange(location: command.utf16.count, length: 0))

    if primesSlashPopup {
      coordinator.textDidChange(
        Notification(name: NSText.didChangeNotification, object: textView)
      )
    }

    let handled = coordinator.textView(
      textView,
      doCommandBy: #selector(NSResponder.insertNewline(_:))
    )

    XCTAssertTrue(handled, file: file, line: line)
    XCTAssertFalse(textView.string.contains(command), file: file, line: line)
    XCTAssertTrue(markdown.value.contains("<!-- sceal-table v:1 columns:2 header:false"))
    XCTAssertEqual(markdown.value.components(separatedBy: "<!-- cell r:").count - 1, 6)
    XCTAssertTrue(markdown.value.hasSuffix("\n"))
    XCTAssertFalse(firstTableID(in: textView).isEmpty, file: file, line: line)
  }

  private func firstTableID(
    in textView: MarkdownEditorTextView,
    file: StaticString = #filePath,
    line: UInt = #line
  ) -> String {
    guard let textStorage = textView.textStorage else {
      XCTFail("Expected editor text storage.", file: file, line: line)
      return ""
    }

    var tableID: String?
    textStorage.enumerateAttribute(
      .markdownTableID,
      in: NSRange(location: 0, length: textStorage.length),
      options: []
    ) { value, _, stop in
      guard let value = value as? String else { return }
      tableID = value
      stop.pointee = true
    }

    guard let tableID else {
      XCTFail("Expected rendered table.", file: file, line: line)
      return ""
    }
    return tableID
  }

  private func firstTableModel(
    in textView: MarkdownEditorTextView,
    file: StaticString = #filePath,
    line: UInt = #line
  ) -> MarkdownEditorTable {
    guard let textStorage = textView.textStorage else {
      XCTFail("Expected editor text storage.", file: file, line: line)
      return MarkdownEditorTable.empty()
    }

    var table: MarkdownEditorTable?
    textStorage.enumerateAttribute(
      .markdownTableModel,
      in: NSRange(location: 0, length: textStorage.length),
      options: []
    ) { value, _, stop in
      guard let value = value as? MarkdownEditorTable else { return }
      table = value
      stop.pointee = true
    }

    guard let table else {
      XCTFail("Expected rendered table model.", file: file, line: line)
      return MarkdownEditorTable.empty()
    }
    return table
  }

  private func toolbarButtons(in view: NSView) -> [NSButton] {
    view.subviews.flatMap { subview -> [NSButton] in
      let nestedButtons = toolbarButtons(in: subview)
      if let button = subview as? NSButton {
        return [button] + nestedButtons
      }
      return nestedButtons
    }
  }

  private func tableMouseEvent(type: NSEvent.EventType, location: NSPoint) -> NSEvent {
    guard
      let event = NSEvent.mouseEvent(
        with: type,
        location: location,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        eventNumber: 0,
        clickCount: 1,
        pressure: 0
      )
    else {
      fatalError("Expected table mouse event.")
    }
    return event
  }
}
