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

  func testTableViewUsesDarkBackgroundInDarkAppearance() {
    let tableView = EditorTableBlockView(
      table: MarkdownEditorTable.empty(),
      appearanceSettings: appearance
    )
    tableView.appearance = NSAppearance(named: .darkAqua)
    tableView.frame = NSRect(x: 0, y: 0, width: 360, height: 160)
    tableView.layoutSubtreeIfNeeded()

    guard let imageRep = tableView.bitmapImageRepForCachingDisplay(in: tableView.bounds) else {
      return XCTFail("Expected a rendered table image.")
    }
    tableView.cacheDisplay(in: tableView.bounds, to: imageRep)

    guard
      let color = imageRep.colorAt(x: 20, y: 20)?.usingColorSpace(.deviceRGB)
    else {
      return XCTFail("Expected a sampled table color.")
    }

    let brightness = max(color.redComponent, color.greenComponent, color.blueComponent)
    XCTAssertLessThan(brightness, 0.35)
  }

  func testTableToolbarButtonsAreIconOnlyAndVisibleOnHover() {
    let tableView = EditorTableBlockView(
      table: MarkdownEditorTable.empty(),
      appearanceSettings: appearance
    )
    tableView.frame = NSRect(x: 0, y: 0, width: 360, height: 160)
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
    XCTAssertEqual(toolbarContainers.first?.isHidden, false)

    let buttons = toolbarButtons(in: tableView)
    XCTAssertEqual(buttons.count, 7)
    XCTAssertTrue(buttons.allSatisfy { $0.title.isEmpty })
    XCTAssertTrue(buttons.allSatisfy { $0.image != nil })
    XCTAssertTrue(buttons.allSatisfy { $0.imagePosition == .imageOnly })
    XCTAssertTrue(buttons.allSatisfy { ($0.toolTip ?? "").isEmpty == false })
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

  private func toolbarButtons(in view: NSView) -> [NSButton] {
    view.subviews.flatMap { subview -> [NSButton] in
      let nestedButtons = toolbarButtons(in: subview)
      if let button = subview as? NSButton {
        return [button] + nestedButtons
      }
      return nestedButtons
    }
  }
}
