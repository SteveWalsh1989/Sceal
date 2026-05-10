//
//  EditorTableBlockView.swift
//

// Interactive NSView overlay for one rich table block inside the markdown editor.

import AppKit

@MainActor
protocol EditorTableBlockViewDelegate: AnyObject {
  func tableBlockView(_: EditorTableBlockView, didChange table: MarkdownEditorTable)
  func tableBlockView(
    _: EditorTableBlockView, didFocus _: MarkdownEditorTableCell?)
  func tableBlockView(_: EditorTableBlockView, didChangeHovering isHovering: Bool)
}

@MainActor
final class EditorTableBlockView: NSView, NSTextViewDelegate {
  static let minimumOverlayWidth: CGFloat = 240
  static let toolbarReservedHeight: CGFloat = 36
  static let resizeHandleOutset: CGFloat = 8

  weak var delegate: EditorTableBlockViewDelegate?

  private(set) var table: MarkdownEditorTable
  private let appearanceSettings: NoteAppearanceSettings
  private var cellTextViews: [MarkdownEditorTableCell: EditorTableCellTextView] = [:]
  private var toolbarButtons: [EditorTableAction: NSButton] = [:]
  private let toolbarContainer = NSVisualEffectView()
  private let toolbarActions: [EditorTableAction] = [
    .toggleHeader,
    .toggleFullWidth,
    .addColumnBefore,
    .addColumnAfter,
    .deleteColumn,
    .addRowAbove,
    .addRowBelow,
    .deleteRow,
  ]
  private var activeCell = MarkdownEditorTableCell(row: 0, column: 0)
  private var isApplyingModel = false
  private var isHovering = false
  private var isHoveringCell = false
  private var tableContentOrigin = NSPoint.zero
  private var availableTableWidth: CGFloat?
  private var resizingColumnIndex: Int?
  private var resizeStartX: CGFloat = 0
  private var resizeStartWidths: [CGFloat] = []
  private var trackingArea: NSTrackingArea?

  private let cornerRadius: CGFloat = 6
  private let gridLineWidth: CGFloat = 1
  private let resizeHitWidth: CGFloat = 16
  private let toolbarHeight: CGFloat = 30
  private let toolbarButtonSize: CGFloat = 24

  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { true }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  init(table: MarkdownEditorTable, appearanceSettings: NoteAppearanceSettings) {
    self.table = table.normalized()
    self.appearanceSettings = appearanceSettings
    super.init(frame: .zero)
    wantsLayer = true
    buildToolbar()
    rebuildCells()
    updateToolbarVisibility()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  func update(table newTable: MarkdownEditorTable, availableWidth: CGFloat? = nil) {
    availableTableWidth = availableWidth
    let normalized = newTable.constrained(toAvailableWidth: availableWidth)
    let oldShape = (table.rows.count, table.columnCount)
    let newShape = (normalized.rows.count, normalized.columnCount)
    table = normalized

    if oldShape != newShape {
      rebuildCells()
    } else {
      syncCellContentsFromModel()
    }
    updateToolbarState()
    needsDisplay = true
    needsLayout = true
  }

  func focusCell(row: Int, column: Int) {
    let safeCell = clampedCell(row: row, column: column)
    activeCell = safeCell
    updateToolbarVisibility()
    delegate?.tableBlockView(self, didFocus: safeCell)
    window?.makeFirstResponder(cellTextViews[safeCell])
  }

  func textViewForCell(row: Int, column: Int) -> EditorTableCellTextView? {
    cellTextViews[MarkdownEditorTableCell(row: row, column: column)]
  }

  func positionTableContent(topInset: CGFloat, leftInset: CGFloat) {
    tableContentOrigin = NSPoint(x: max(leftInset, 0), y: max(topInset, 0))
    needsDisplay = true
    needsLayout = true
  }

  func apply(_ action: EditorTableAction, relativeTo cell: MarkdownEditorTableCell? = nil) {
    let target = clampedCell(
      row: cell?.row ?? activeCell.row,
      column: cell?.column ?? activeCell.column
    )
    var updated = table.normalized()

    switch action {
    case .toggleHeader:
      updated.hasHeader.toggle()

    case .toggleFullWidth:
      updated.isFullWidth.toggle()

    case .addColumnBefore:
      updated = insertingColumn(in: updated, at: target.column)

    case .addColumnAfter:
      updated = insertingColumn(in: updated, at: target.column + 1)

    case .deleteColumn:
      guard updated.columnCount > 1 else { return }
      updated = deletingColumn(in: updated, at: target.column)
      activeCell = clampedCell(row: target.row, column: min(target.column, updated.columnCount - 1))

    case .addRowAbove:
      updated = insertingRow(in: updated, at: target.row)

    case .addRowBelow:
      updated = insertingRow(in: updated, at: target.row + 1)

    case .deleteRow:
      guard canDeleteRow(target.row, in: updated) else { return }
      updated = deletingRow(in: updated, at: target.row)
      activeCell = clampedCell(row: min(target.row, updated.rows.count - 1), column: target.column)
    }

    table = updated.constrained(toAvailableWidth: availableTableWidth)
    rebuildCells()
    delegate?.tableBlockView(self, didChange: table)
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let trackingArea {
      removeTrackingArea(trackingArea)
    }
    let options: NSTrackingArea.Options = [
      .activeInKeyWindow,
      .mouseEnteredAndExited,
      .mouseMoved,
      .inVisibleRect,
    ]
    let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
    addTrackingArea(area)
    trackingArea = area
  }

  override func layout() {
    super.layout()
    layoutToolbar()
    layoutCells()
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    drawTableBackground()
    drawGridLines()
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    guard bounds.contains(point) else { return nil }
    if !toolbarContainer.isHidden, toolbarContainer.frame.contains(point) {
      let toolbarPoint = convert(point, to: toolbarContainer)
      return toolbarContainer.hitTest(toolbarPoint) ?? toolbarContainer
    }

    if columnResizeIndex(at: point) != nil {
      return self
    }

    guard tableContentRect().contains(point) else { return nil }
    for textView in cellTextViews.values.reversed() where textView.frame.contains(point) {
      let cellPoint = convert(point, to: textView)
      return textView.hitTest(cellPoint) ?? textView
    }
    return self
  }

  override func mouseEntered(with event: NSEvent) {
    isHovering = true
    delegate?.tableBlockView(self, didChangeHovering: true)
    updateToolbarVisibility()
  }

  override func mouseExited(with event: NSEvent) {
    isHovering = false
    delegate?.tableBlockView(self, didChangeHovering: false)
    updateToolbarVisibility()
  }

  override func mouseMoved(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    NSCursor.setHiddenUntilMouseMoves(false)
    if columnResizeIndex(at: point) != nil {
      NSCursor.resizeLeftRight.set()
    } else {
      NSCursor.arrow.set()
    }
  }

  override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    guard let resizeIndex = columnResizeIndex(at: point) else {
      super.mouseDown(with: event)
      return
    }

    resizingColumnIndex = resizeIndex
    resizeStartX = point.x
    resizeStartWidths = table.columnWidths
  }

  override func mouseDragged(with event: NSEvent) {
    guard let resizingColumnIndex else {
      super.mouseDragged(with: event)
      return
    }

    let point = convert(event.locationInWindow, from: nil)
    let delta = point.x - resizeStartX
    var updated = table.normalized()
    updated.isFullWidth = false
    updated.columnWidths = resizeStartWidths
    updated.columnWidths[resizingColumnIndex] = resizedColumnWidth(
      resizeStartWidths[resizingColumnIndex] + delta,
      at: resizingColumnIndex,
      in: resizeStartWidths
    )
    table = updated.normalized()
    layoutCells()
    needsDisplay = true
    delegate?.tableBlockView(self, didChange: table)
  }

  override func mouseUp(with event: NSEvent) {
    resizingColumnIndex = nil
  }

  func textDidBeginEditing(_ notification: Notification) {
    guard let textView = notification.object as? EditorTableCellTextView,
      cellForTextView(textView) != nil
    else { return }

    activateCellTextView(textView)
  }

  func textDidChange(_ notification: Notification) {
    guard !isApplyingModel,
      let textView = notification.object as? EditorTableCellTextView,
      let cell = cellForTextView(textView),
      let textStorage = textView.textStorage
    else { return }

    table.rows[cell.row][cell.column] = MarkdownEditorFormatter.convertToMarkdown(
      from: textStorage
    )
    layoutCells()
    needsDisplay = true
    delegate?.tableBlockView(self, didChange: table)
  }

  func textView(
    _ textView: NSTextView,
    doCommandBy commandSelector: Selector
  ) -> Bool {
    guard commandSelector == #selector(NSResponder.insertNewline(_:)),
      let textStorage = textView.textStorage
    else { return false }

    let cursorLocation = textView.selectedRange().location
    let nsString = textStorage.string as NSString
    let fullLineRange = nsString.lineRange(for: NSRange(location: cursorLocation, length: 0))
    var lineRange = fullLineRange
    if lineRange.length > 0,
      nsString.character(at: lineRange.location + lineRange.length - 1) == 0x0A
    {
      lineRange.length -= 1
    }

    let lineText = nsString.substring(with: lineRange)
    if isEmptyListItem(lineText) {
      return textView.performEditorEdit(
        affectedRange: lineRange,
        replacementString: "",
        actionName: "Remove List Marker"
      ) { textStorage in
        textStorage.replaceCharacters(in: lineRange, with: "")
        return NSRange(location: lineRange.location, length: 0)
      }
    }

    var continuedListType: MarkdownListType?
    let currentIndentLevel =
      lineRange.length > 0
      ? textStorage.attribute(.markdownIndentLevel, at: lineRange.location, effectiveRange: nil)
        as? Int ?? 0
      : 0

    return textView.performEditorEdit(
      affectedRange: lineRange,
      replacementString: "\n",
      actionName: "Insert Newline"
    ) { textStorage in
      continuedListType = MarkdownEditorFormatter.formatCurrentLine(
        in: textStorage,
        lineRange: lineRange,
        appearance: appearanceSettings
      )
      let updatedString = textStorage.string as NSString
      let updatedLine = updatedString.lineRange(
        for: NSRange(location: min(lineRange.location, max(updatedString.length - 1, 0)), length: 0)
      )
      var insertionLocation = NSMaxRange(updatedLine)
      if insertionLocation > 0,
        updatedString.character(at: insertionLocation - 1) == 0x0A
      {
        insertionLocation -= 1
      }

      textStorage.insert(
        NSAttributedString(
          string: "\n",
          attributes: MarkdownEditorFormatter.baseTypingAttributes(for: appearanceSettings)
        ),
        at: insertionLocation
      )
      var nextInsertionLocation = insertionLocation + 1

      if let listType = continuedListType {
        let marker = continuationAttributedMarker(
          for: listType,
          previousLineText: lineText,
          indentLevel: currentIndentLevel
        )
        textStorage.insert(marker, at: nextInsertionLocation)
        nextInsertionLocation += marker.length
      }

      return NSRange(location: nextInsertionLocation, length: 0)
    }
  }

  private func buildToolbar() {
    toolbarContainer.material = .popover
    toolbarContainer.blendingMode = .withinWindow
    toolbarContainer.state = .active
    toolbarContainer.wantsLayer = true
    toolbarContainer.layer?.cornerRadius = 7
    toolbarContainer.layer?.masksToBounds = true
    addSubview(toolbarContainer)

    let buttons: [(EditorTableAction, String, String)] = [
      (.toggleHeader, "tablecells.badge.ellipsis", "Add table header"),
      (.toggleFullWidth, "arrow.left.and.right", "Toggle full width"),
      (.addColumnBefore, "sidebar.left", "Add column before"),
      (.addColumnAfter, "sidebar.right", "Add column after"),
      (.deleteColumn, "rectangle.badge.minus", "Delete column"),
      (.addRowAbove, "arrow.up.to.line", "Add row above"),
      (.addRowBelow, "arrow.down.to.line", "Add row below"),
      (.deleteRow, "trash", "Delete row"),
    ]

    for (action, symbolName, tooltip) in buttons {
      let button = EditorTableToolbarButton(action: action)
      button.title = ""
      button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: tooltip)
      button.imagePosition = .imageOnly
      button.toolTip = tooltip
      button.bezelStyle = .texturedRounded
      button.isBordered = false
      button.target = self
      button.action = #selector(toolbarButtonPressed(_:))
      button.contentTintColor = .secondaryLabelColor
      toolbarContainer.addSubview(button)
      toolbarButtons[action] = button
    }
  }

  private func rebuildCells() {
    isApplyingModel = true
    for view in cellTextViews.values {
      view.removeFromSuperview()
    }
    cellTextViews.removeAll()

    let normalized = table.normalized()
    table = normalized
    for rowIndex in normalized.rows.indices {
      for columnIndex in 0..<normalized.columnCount {
        let cell = MarkdownEditorTableCell(row: rowIndex, column: columnIndex)
        let textView = EditorTableCellTextView(usingTextLayoutManager: true)
        configureCellTextView(textView, isHeader: normalized.hasHeader && rowIndex == 0)
        textView.textStorage?.setAttributedString(
          MarkdownEditorFormatter.formatForDisplay(
            normalized.rows[rowIndex][columnIndex],
            appearance: appearanceSettings
          )
        )
        addSubview(textView)
        cellTextViews[cell] = textView
      }
    }

    isApplyingModel = false
    bringToolbarToFront()
    updateToolbarState()
    needsLayout = true
  }

  private func syncCellContentsFromModel() {
    isApplyingModel = true
    for (cell, textView) in cellTextViews {
      let modelMarkdown = table.rows[cell.row][cell.column]
      let currentMarkdown =
        textView.textStorage.map {
          MarkdownEditorFormatter.convertToMarkdown(from: $0)
        } ?? ""
      if currentMarkdown != modelMarkdown, window?.firstResponder !== textView {
        textView.textStorage?.setAttributedString(
          MarkdownEditorFormatter.formatForDisplay(
            modelMarkdown,
            appearance: appearanceSettings
          )
        )
      }
      configureCellTextView(textView, isHeader: table.hasHeader && cell.row == 0)
    }
    isApplyingModel = false
  }

  private func configureCellTextView(_ textView: EditorTableCellTextView, isHeader: Bool) {
    textView.tableBlockView = self
    textView.appearanceSettings = appearanceSettings
    textView.isRichText = true
    textView.isEditable = true
    textView.isSelectable = true
    textView.drawsBackground = false
    textView.allowsUndo = true
    textView.delegate = self
    textView.textContainerInset = NSSize(
      width: MarkdownEditorTableMetrics.cellHorizontalPadding,
      height: MarkdownEditorTableMetrics.cellVerticalPadding
    )
    textView.textContainer?.widthTracksTextView = true
    textView.textContainer?.heightTracksTextView = false
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.autoresizingMask = []
    textView.typingAttributes =
      isHeader
      ? [
        .font: appearanceSettings.boldBodyFont(ofSize: appearanceSettings.bodyFont.pointSize),
        .foregroundColor: NSColor.labelColor,
        .paragraphStyle: MarkdownEditorFormatter.bodyParagraphStyle(for: appearanceSettings),
      ]
      : MarkdownEditorFormatter.baseTypingAttributes(for: appearanceSettings)
  }

  private func layoutToolbar() {
    let visibleButtons = toolbarActions.compactMap { toolbarButtons[$0] }
    guard !visibleButtons.isEmpty else { return }

    let spacing: CGFloat = 4
    let padding: CGFloat = 4
    let totalWidth =
      CGFloat(visibleButtons.count) * toolbarButtonSize
      + CGFloat(max(visibleButtons.count - 1, 0)) * spacing
      + padding * 2
    let toolbarX = min(
      max(tableContentOrigin.x, 0),
      max(bounds.width - totalWidth, 0)
    )
    toolbarContainer.frame = NSRect(
      x: toolbarX,
      y: max(tableContentOrigin.y - toolbarHeight - 4, 0),
      width: totalWidth,
      height: toolbarHeight
    )

    var x = padding
    for button in visibleButtons {
      button.frame = NSRect(
        x: x,
        y: (toolbarHeight - toolbarButtonSize) / 2,
        width: toolbarButtonSize,
        height: toolbarButtonSize
      )
      x += toolbarButtonSize + spacing
    }
  }

  private func layoutCells() {
    let rowHeights = MarkdownEditorTableMetrics.rowHeights(
      for: table,
      appearance: appearanceSettings
    )
    var y = tableContentOrigin.y
    for (rowIndex, rowHeight) in rowHeights.enumerated() {
      var x = tableContentOrigin.x
      for columnIndex in 0..<table.columnCount {
        let cell = MarkdownEditorTableCell(row: rowIndex, column: columnIndex)
        let width = table.columnWidths[columnIndex]
        if let textView = cellTextViews[cell] {
          textView.frame = NSRect(
            x: x + gridLineWidth,
            y: y + gridLineWidth,
            width: max(width - gridLineWidth * 2, 1),
            height: max(rowHeight - gridLineWidth * 2, 1)
          )
        }
        x += width
      }
      y += rowHeight
    }
  }

  private func drawTableBackground() {
    let contentRect = tableContentRect()
    if table.hasHeader {
      let headerHeight =
        MarkdownEditorTableMetrics.rowHeights(
          for: table,
          appearance: appearanceSettings
        ).first ?? 0
      headerFillColor.setFill()
      NSBezierPath(
        roundedRect: NSRect(
          x: contentRect.minX,
          y: contentRect.minY,
          width: contentRect.width,
          height: headerHeight
        ),
        xRadius: cornerRadius,
        yRadius: cornerRadius
      ).fill()
    }
  }

  private func drawGridLines() {
    let contentRect = tableContentRect()
    gridColor.setStroke()
    let path = NSBezierPath()
    var x = contentRect.minX
    for width in table.columnWidths.dropLast() {
      x += width
      path.move(to: NSPoint(x: x, y: contentRect.minY))
      path.line(to: NSPoint(x: x, y: contentRect.maxY))
    }

    var y = contentRect.minY
    for height in MarkdownEditorTableMetrics.rowHeights(
      for: table,
      appearance: appearanceSettings
    ).dropLast() {
      y += height
      path.move(to: NSPoint(x: contentRect.minX, y: y))
      path.line(to: NSPoint(x: contentRect.maxX, y: y))
    }
    path.lineWidth = gridLineWidth
    path.stroke()

    let border = NSBezierPath(
      roundedRect: contentRect,
      xRadius: cornerRadius,
      yRadius: cornerRadius
    )
    border.lineWidth = gridLineWidth
    border.stroke()
  }

  private var headerFillColor: NSColor {
    isDarkAppearance
      ? NSColor.white.withAlphaComponent(0.06)
      : NSColor.black.withAlphaComponent(0.04)
  }

  private var gridColor: NSColor {
    NSColor.separatorColor.withAlphaComponent(
      isDarkAppearance ? 0.5 : 0.78
    )
  }

  private var isDarkAppearance: Bool {
    effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
  }

  private func updateToolbarVisibility() {
    let shouldShow =
      isHovering || isHoveringCell || window?.firstResponder.map(isCellTextView) == true
    toolbarContainer.isHidden = !shouldShow
    updateToolbarState()
    needsLayout = true
  }

  private func bringToolbarToFront() {
    toolbarContainer.removeFromSuperview()
    addSubview(toolbarContainer)
  }

  fileprivate func setCellHovering(_ isHovering: Bool) {
    isHoveringCell = isHovering
    if isHovering {
      delegate?.tableBlockView(self, didChangeHovering: true)
    } else if !self.isHovering {
      delegate?.tableBlockView(self, didChangeHovering: false)
    }
    updateToolbarVisibility()
  }

  fileprivate func activateCellTextView(_ textView: EditorTableCellTextView) {
    guard let cell = cellForTextView(textView) else { return }
    activeCell = cell
    updateToolbarVisibility()
    delegate?.tableBlockView(self, didFocus: cell)
  }

  private func updateToolbarState() {
    if let fullWidthButton = toolbarButtons[.toggleFullWidth] {
      fullWidthButton.state = table.isFullWidth ? .on : .off
      fullWidthButton.contentTintColor =
        table.isFullWidth ? appearanceSettings.accentColor : .secondaryLabelColor
    }
    toolbarButtons[.deleteColumn]?.isEnabled = table.columnCount > 1
    toolbarButtons[.deleteRow]?.isEnabled = canDeleteRow(activeCell.row, in: table)
  }

  @objc private func toolbarButtonPressed(_ sender: EditorTableToolbarButton) {
    apply(sender.tableAction)
  }

  private func columnResizeIndex(at point: NSPoint) -> Int? {
    let contentRect = tableContentRect()
    guard point.y >= contentRect.minY, point.y <= contentRect.maxY else { return nil }
    var x = contentRect.minX
    for (index, width) in table.columnWidths.enumerated() {
      x += width
      if abs(point.x - x) <= resizeHitWidth / 2 {
        return index
      }
    }
    return nil
  }

  private func resizedColumnWidth(
    _ proposedWidth: CGFloat,
    at columnIndex: Int,
    in widths: [CGFloat]
  ) -> CGFloat {
    let minimumWidth =
      availableTableWidth.map { min(MarkdownEditorTable.minimumColumnWidth, $0) }
      ?? MarkdownEditorTable.minimumColumnWidth
    let minimumClampedWidth = max(proposedWidth, minimumWidth)
    guard let availableTableWidth else {
      return MarkdownEditorTable.clampedColumnWidth(minimumClampedWidth)
    }

    let otherColumnsWidth = widths.enumerated().reduce(CGFloat(0)) { total, entry in
      entry.offset == columnIndex ? total : total + entry.element
    }
    let availableColumnWidth = max(availableTableWidth - otherColumnsWidth, 1)
    return max(min(minimumClampedWidth, availableColumnWidth), 1)
  }

  private func tableContentRect() -> NSRect {
    let rowHeights = MarkdownEditorTableMetrics.rowHeights(
      for: table,
      appearance: appearanceSettings
    )
    return NSRect(
      x: tableContentOrigin.x,
      y: tableContentOrigin.y,
      width: table.columnWidths.reduce(0, +),
      height: rowHeights.reduce(0, +)
    )
  }

  private func cellForTextView(_ textView: EditorTableCellTextView) -> MarkdownEditorTableCell? {
    cellTextViews.first { $0.value === textView }?.key
  }

  private func isCellTextView(_ responder: NSResponder) -> Bool {
    guard let textView = responder as? EditorTableCellTextView else { return false }
    return cellTextViews.values.contains { $0 === textView }
  }

  private func clampedCell(row: Int, column: Int) -> MarkdownEditorTableCell {
    MarkdownEditorTableCell(
      row: min(max(row, 0), max(table.rows.count - 1, 0)),
      column: min(max(column, 0), max(table.columnCount - 1, 0))
    )
  }

  private func insertingColumn(
    in table: MarkdownEditorTable,
    at columnIndex: Int
  ) -> MarkdownEditorTable {
    var updated = table.normalized()
    let safeIndex = min(max(columnIndex, 0), updated.columnCount)
    updated.columnWidths.insert(MarkdownEditorTable.defaultColumnWidth, at: safeIndex)
    for rowIndex in updated.rows.indices {
      updated.rows[rowIndex].insert("", at: safeIndex)
    }
    activeCell = MarkdownEditorTableCell(row: activeCell.row, column: safeIndex)
    return updated
  }

  private func deletingColumn(
    in table: MarkdownEditorTable,
    at columnIndex: Int
  ) -> MarkdownEditorTable {
    var updated = table.normalized()
    let safeIndex = min(max(columnIndex, 0), updated.columnCount - 1)
    updated.columnWidths.remove(at: safeIndex)
    for rowIndex in updated.rows.indices {
      updated.rows[rowIndex].remove(at: safeIndex)
    }
    return updated
  }

  private func insertingRow(
    in table: MarkdownEditorTable,
    at rowIndex: Int
  ) -> MarkdownEditorTable {
    var updated = table.normalized()
    let safeIndex = min(max(rowIndex, 0), updated.rows.count)
    updated.rows.insert(Array(repeating: "", count: updated.columnCount), at: safeIndex)
    activeCell = MarkdownEditorTableCell(row: safeIndex, column: activeCell.column)
    return updated
  }

  private func deletingRow(
    in table: MarkdownEditorTable,
    at rowIndex: Int
  ) -> MarkdownEditorTable {
    var updated = table.normalized()
    let safeIndex = min(max(rowIndex, 0), updated.rows.count - 1)
    updated.rows.remove(at: safeIndex)
    return updated
  }

  private func canDeleteRow(_ rowIndex: Int, in table: MarkdownEditorTable) -> Bool {
    let normalized = table.normalized()
    guard normalized.rows.indices.contains(rowIndex) else { return false }
    let rowCountAfterDelete = normalized.rows.count - 1
    let bodyRowsAfterDelete =
      normalized.hasHeader
      ? max(rowCountAfterDelete - 1, 0)
      : rowCountAfterDelete
    return bodyRowsAfterDelete >= 1
  }

  private func isEmptyListItem(_ lineText: String) -> Bool {
    let trimmed = lineText.trimmingCharacters(in: .whitespaces)
    let emptyMarkers = [
      "\(MarkdownEditorFormatter.bulletMarker) ",
      "\(MarkdownEditorFormatter.bulletMarker)",
      "\(MarkdownEditorFormatter.attachmentChar) ",
      "\(MarkdownEditorFormatter.attachmentChar)",
      "- ",
      "-",
    ]
    if emptyMarkers.contains(trimmed) { return true }
    return trimmed.range(of: #"^\d+\.\s*$"#, options: .regularExpression) != nil
  }

  private func continuationAttributedMarker(
    for listType: MarkdownListType,
    previousLineText: String,
    indentLevel: Int
  ) -> NSAttributedString {
    let marker: String
    switch listType {
    case .bullet:
      marker = "\(MarkdownEditorFormatter.bulletMarker) "
    case .checkboxUnchecked, .checkboxChecked:
      marker = "\(MarkdownEditorFormatter.uncheckedMarker) "
    case .numbered:
      if let match = previousLineText.range(of: #"^(\d+)\."#, options: .regularExpression),
        let number = Int(previousLineText[match].dropLast())
      {
        marker = "\(number + 1). "
      } else {
        marker = "1. "
      }
    }

    let listStyle = MarkdownEditorFormatter.listParagraphStyle(
      for: appearanceSettings,
      indentLevel: indentLevel
    )
    if listType == .checkboxUnchecked || listType == .checkboxChecked {
      let result = NSMutableAttributedString()
      result.append(
        MarkdownEditorFormatter.checkboxAttributedString(
          checked: false,
          appearance: appearanceSettings
        ))
      result.append(
        NSAttributedString(
          string: " ",
          attributes: MarkdownEditorFormatter.baseTypingAttributes(for: appearanceSettings)
        ))
      result.addAttributes(
        [
          .markdownListType: MarkdownListType.checkboxUnchecked.rawValue,
          .paragraphStyle: listStyle,
          .markdownIndentLevel: indentLevel,
        ],
        range: NSRange(location: 0, length: result.length)
      )
      return result
    }

    let result = NSMutableAttributedString(
      string: marker,
      attributes: [
        .font: appearanceSettings.bodyFont,
        .foregroundColor: NSColor.labelColor,
        .markdownListType: listType.rawValue,
        .paragraphStyle: listStyle,
        .markdownIndentLevel: indentLevel,
      ]
    )
    if listType == .bullet {
      result.addAttributes(
        [
          .foregroundColor: MarkdownEditorFormatter.bulletColor(for: appearanceSettings),
          .font: NSFont.systemFont(ofSize: appearanceSettings.bulletSize, weight: .bold),
        ],
        range: NSRange(location: 0, length: 1)
      )
    }
    return result
  }
}

@MainActor
private final class EditorTableToolbarButton: NSButton {
  let tableAction: EditorTableAction

  init(action: EditorTableAction) {
    self.tableAction = action
    super.init(frame: .zero)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }
}

@MainActor
final class EditorTableCellTextView: NSTextView {
  var appearanceSettings = NoteAppearanceSettings.default
  fileprivate weak var tableBlockView: EditorTableBlockView?
  private var tableTrackingArea: NSTrackingArea?

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let tableTrackingArea {
      removeTrackingArea(tableTrackingArea)
    }
    let area = NSTrackingArea(
      rect: bounds,
      options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect],
      owner: self,
      userInfo: nil
    )
    addTrackingArea(area)
    tableTrackingArea = area
  }

  override func mouseEntered(with event: NSEvent) {
    tableBlockView?.setCellHovering(true)
    super.mouseEntered(with: event)
  }

  override func mouseExited(with event: NSEvent) {
    tableBlockView?.setCellHovering(false)
    super.mouseExited(with: event)
  }

  override func becomeFirstResponder() -> Bool {
    tableBlockView?.activateCellTextView(self)
    return super.becomeFirstResponder()
  }

  override func mouseDown(with event: NSEvent) {
    tableBlockView?.activateCellTextView(self)
    if window?.firstResponder !== self {
      window?.makeFirstResponder(self)
    }

    guard let textStorage else {
      super.mouseDown(with: event)
      return
    }

    let point = convert(event.locationInWindow, from: nil)
    guard let charIndex = editorCharacterIndex(forViewPoint: point),
      charIndex < textStorage.length
    else {
      super.mouseDown(with: event)
      return
    }

    let nsString = string as NSString
    let lineRange = nsString.lineRange(for: NSRange(location: charIndex, length: 0))
    guard charIndex <= lineRange.location + 1 else {
      super.mouseDown(with: event)
      return
    }

    let attrs = textStorage.attributes(at: lineRange.location, effectiveRange: nil)
    guard let rawType = attrs[.markdownListType] as? String,
      rawType == MarkdownListType.checkboxUnchecked.rawValue
        || rawType == MarkdownListType.checkboxChecked.rawValue
    else {
      super.mouseDown(with: event)
      return
    }

    if editorToggleCheckbox(at: lineRange.location, appearanceSettings: appearanceSettings) {
      return
    }

    super.mouseDown(with: event)
  }
}
