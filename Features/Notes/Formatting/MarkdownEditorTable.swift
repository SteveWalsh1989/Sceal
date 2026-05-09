//
//  MarkdownEditorTable.swift
//

// Rich table model, storage parsing, and import helpers for Sceal table blocks.

import AppKit

struct MarkdownEditorTable: Equatable, Hashable {
  nonisolated static let defaultColumnWidth: CGFloat = 180
  nonisolated static let minimumColumnWidth: CGFloat = 96
  nonisolated static let maximumColumnWidth: CGFloat = 420

  var runtimeID: String
  var hasHeader: Bool
  var columnWidths: [CGFloat]
  var rows: [[String]]

  nonisolated var columnCount: Int {
    max(columnWidths.count, rows.map(\.count).max() ?? 0)
  }

  nonisolated var bodyRowCount: Int {
    hasHeader ? max(rows.count - 1, 0) : rows.count
  }

  static func empty(columns: Int = 2, bodyRows: Int = 3) -> MarkdownEditorTable {
    let safeColumns = max(columns, 1)
    let safeRows = max(bodyRows, 1)
    return MarkdownEditorTable(
      runtimeID: UUID().uuidString,
      hasHeader: false,
      columnWidths: Array(repeating: defaultColumnWidth, count: safeColumns),
      rows: Array(
        repeating: Array(repeating: "", count: safeColumns),
        count: safeRows
      )
    )
  }

  nonisolated func normalized() -> MarkdownEditorTable {
    let safeColumnCount = max(columnCount, 1)
    var safeRows =
      rows.isEmpty
      ? [Array(repeating: "", count: safeColumnCount)]
      : rows.map { row in
        let padded = row + Array(repeating: "", count: max(safeColumnCount - row.count, 0))
        return Array(padded.prefix(safeColumnCount))
      }
    if hasHeader, safeRows.count < 2 {
      safeRows.append(Array(repeating: "", count: safeColumnCount))
    }
    let safeWidths = Self.normalizedWidths(columnWidths, columnCount: safeColumnCount)

    return MarkdownEditorTable(
      runtimeID: runtimeID,
      hasHeader: hasHeader,
      columnWidths: safeWidths,
      rows: safeRows
    )
  }

  nonisolated static func normalizedWidths(_ widths: [CGFloat], columnCount: Int) -> [CGFloat] {
    let safeColumnCount = max(columnCount, 1)
    let padded =
      widths
      + Array(
        repeating: defaultColumnWidth,
        count: max(safeColumnCount - widths.count, 0)
      )
    return Array(padded.prefix(safeColumnCount)).map { clampedColumnWidth($0) }
  }

  nonisolated static func clampedColumnWidth(_ width: CGFloat) -> CGFloat {
    min(max(width, minimumColumnWidth), maximumColumnWidth)
  }
}

struct MarkdownEditorTableCell: Equatable, Hashable {
  var row: Int
  var column: Int
}

enum EditorTableAction: Hashable {
  case toggleHeader
  case addColumnBefore
  case addColumnAfter
  case deleteColumn
  case addRowAbove
  case addRowBelow
  case deleteRow
}

enum MarkdownEditorTableMarkdown {
  static let startPrefix = "<!-- sceal-table"
  static let endMarker = "<!-- /sceal-table -->"

  private static let cellStartRegex = try! NSRegularExpression(
    pattern: #"^<!-- cell r:([0-9]+) c:([0-9]+) -->$"#
  )
  private static let cellEndRegex = try! NSRegularExpression(pattern: #"^<!-- /cell -->$"#)

  static func isStartLine(_ line: String) -> Bool {
    line.hasPrefix(startPrefix) && line.hasSuffix("-->")
  }

  static func isEndLine(_ line: String) -> Bool {
    line.trimmingCharacters(in: .whitespacesAndNewlines) == endMarker
  }

  static func parseBlock(_ lines: ArraySlice<String>) -> MarkdownEditorTable? {
    guard let firstLine = lines.first,
      let header = parseHeader(firstLine)
    else { return nil }

    var cellContents: [MarkdownEditorTableCell: [String]] = [:]
    var activeCell: MarkdownEditorTableCell?

    for line in lines.dropFirst() {
      if isEndLine(line) { break }

      if let cell = parseCellStart(line) {
        activeCell = cell
        cellContents[cell] = []
        continue
      }

      if cellEndRegex.firstMatch(
        in: line,
        range: NSRange(location: 0, length: line.utf16.count)
      ) != nil {
        activeCell = nil
        continue
      }

      if let activeCell {
        cellContents[activeCell, default: []].append(line)
      }
    }

    let maxRow = cellContents.keys.map(\.row).max() ?? 0
    let maxColumn = cellContents.keys.map(\.column).max() ?? 0
    let columnCount = max(header.columns, maxColumn + 1, 1)
    let rowCount = max(maxRow + 1, header.hasHeader ? 2 : 1)
    var rows = Array(
      repeating: Array(repeating: "", count: columnCount),
      count: rowCount
    )

    for (cell, lines) in cellContents where cell.row < rowCount && cell.column < columnCount {
      rows[cell.row][cell.column] = lines.joined(separator: "\n")
    }

    return MarkdownEditorTable(
      runtimeID: UUID().uuidString,
      hasHeader: header.hasHeader,
      columnWidths: MarkdownEditorTable.normalizedWidths(
        header.widths,
        columnCount: columnCount
      ),
      rows: rows
    ).normalized()
  }

  static func serialize(_ table: MarkdownEditorTable) -> String {
    let normalized = table.normalized()
    let widths = normalized.columnWidths
      .map { String(Int($0.rounded())) }
      .joined(separator: ",")
    var lines: [String] = [
      "<!-- sceal-table v:1 columns:\(normalized.columnCount) header:\(normalized.hasHeader) widths:\(widths) -->"
    ]

    for (rowIndex, row) in normalized.rows.enumerated() {
      for columnIndex in 0..<normalized.columnCount {
        lines.append("<!-- cell r:\(rowIndex) c:\(columnIndex) -->")
        let cellMarkdown = row[columnIndex]
        if !cellMarkdown.isEmpty {
          lines.append(
            contentsOf: cellMarkdown.split(
              separator: "\n",
              omittingEmptySubsequences: false
            ).map(String.init))
        }
        lines.append("<!-- /cell -->")
      }
    }

    lines.append(endMarker)
    return lines.joined(separator: "\n")
  }

  private static func parseHeader(_ line: String) -> (
    columns: Int, hasHeader: Bool, widths: [CGFloat]
  )? {
    guard isStartLine(line) else { return nil }

    let body =
      line
      .replacingOccurrences(of: "<!--", with: "")
      .replacingOccurrences(of: "-->", with: "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let tokens = body.split(separator: " ").map(String.init)
    guard tokens.first == "sceal-table" else { return nil }

    var columns = 0
    var hasHeader = false
    var widths: [CGFloat] = []

    for token in tokens.dropFirst() {
      if token.hasPrefix("columns:") {
        columns = Int(token.dropFirst("columns:".count)) ?? columns
      } else if token.hasPrefix("header:") {
        hasHeader = token.dropFirst("header:".count) == "true"
      } else if token.hasPrefix("widths:") {
        let widthToken = String(token.dropFirst("widths:".count))
        widths =
          widthToken
          .split(separator: ",")
          .compactMap { Double($0).map { CGFloat($0) } }
      }
    }

    guard columns > 0 else { return nil }
    return (columns, hasHeader, widths)
  }

  private static func parseCellStart(_ line: String) -> MarkdownEditorTableCell? {
    guard
      let match = cellStartRegex.firstMatch(
        in: line,
        range: NSRange(location: 0, length: line.utf16.count)
      ),
      let rowRange = Range(match.range(at: 1), in: line),
      let columnRange = Range(match.range(at: 2), in: line),
      let row = Int(line[rowRange]),
      let column = Int(line[columnRange])
    else { return nil }

    return MarkdownEditorTableCell(row: row, column: column)
  }
}

enum MarkdownEditorTableMetrics {
  static let cellHorizontalPadding: CGFloat = 10
  static let cellVerticalPadding: CGFloat = 8
  static let minimumRowHeight: CGFloat = 42

  static func tableSize(
    for table: MarkdownEditorTable,
    appearance: NoteAppearanceSettings
  ) -> NSSize {
    let normalized = table.normalized()
    return NSSize(
      width: normalized.columnWidths.reduce(0, +),
      height: rowHeights(for: normalized, appearance: appearance).reduce(0, +)
    )
  }

  static func rowHeights(
    for table: MarkdownEditorTable,
    appearance: NoteAppearanceSettings
  ) -> [CGFloat] {
    let normalized = table.normalized()
    return normalized.rows.enumerated().map { rowIndex, row in
      let contentHeight =
        row.map { cellMarkdown in
          heightForCellMarkdown(
            cellMarkdown,
            isHeader: normalized.hasHeader && rowIndex == 0,
            appearance: appearance
          )
        }.max() ?? minimumRowHeight
      return max(minimumRowHeight, ceil(contentHeight))
    }
  }

  private static func heightForCellMarkdown(
    _ markdown: String,
    isHeader: Bool,
    appearance: NoteAppearanceSettings
  ) -> CGFloat {
    let lineCount = max(markdown.split(separator: "\n", omittingEmptySubsequences: false).count, 1)
    let font =
      isHeader
      ? appearance.boldBodyFont(ofSize: appearance.bodyFont.pointSize) : appearance.bodyFont
    let lineHeight = ceil(font.pointSize * appearance.lineHeight + 4)
    return CGFloat(lineCount) * lineHeight + cellVerticalPadding * 2
  }
}

enum MarkdownEditorTableImport {
  static func table(from pasteboard: NSPasteboard) -> MarkdownEditorTable? {
    if let html = pasteboard.string(forType: .html),
      let table = tableFromHTML(html)
    {
      return table
    }

    guard let plainText = pasteboard.string(forType: .string) else { return nil }
    return tableFromPipeMarkdown(plainText) ?? tableFromTSV(plainText)
  }

  static func tableFromPipeMarkdown(_ text: String) -> MarkdownEditorTable? {
    let lines =
      text
      .split(separator: "\n", omittingEmptySubsequences: false)
      .map { String($0).trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
    guard lines.count >= 2,
      let header = pipeCells(from: lines[0]),
      let separator = pipeCells(from: lines[1]),
      header.count >= 2,
      separator.count == header.count,
      separator.allSatisfy({ isPipeSeparatorCell($0) })
    else { return nil }

    let bodyRows = lines.dropFirst(2).compactMap { pipeCells(from: $0) }
    guard !bodyRows.isEmpty else { return nil }

    let columnCount = header.count
    let rows = ([header] + bodyRows).map { normalizedRow($0, columnCount: columnCount) }
    return MarkdownEditorTable(
      runtimeID: UUID().uuidString,
      hasHeader: true,
      columnWidths: Array(repeating: MarkdownEditorTable.defaultColumnWidth, count: columnCount),
      rows: rows
    ).normalized()
  }

  static func tableFromTSV(_ text: String) -> MarkdownEditorTable? {
    let rows =
      text
      .split(separator: "\n", omittingEmptySubsequences: false)
      .map { String($0).split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
      .filter { $0.count >= 2 }
    guard rows.count >= 2 else { return nil }

    let columnCount = rows.map(\.count).max() ?? 0
    guard columnCount >= 2 else { return nil }

    return MarkdownEditorTable(
      runtimeID: UUID().uuidString,
      hasHeader: false,
      columnWidths: Array(repeating: MarkdownEditorTable.defaultColumnWidth, count: columnCount),
      rows: rows.map { normalizedRow($0, columnCount: columnCount) }
    ).normalized()
  }

  static func tableFromHTML(_ html: String) -> MarkdownEditorTable? {
    guard html.range(of: "<table", options: .caseInsensitive) != nil else { return nil }

    let rowPattern = #"<tr\b[^>]*>(.*?)</tr>"#
    let cellPattern = #"<t([hd])\b[^>]*>(.*?)</t[hd]>"#
    guard
      let rowRegex = try? NSRegularExpression(
        pattern: rowPattern,
        options: [.caseInsensitive, .dotMatchesLineSeparators]
      ),
      let cellRegex = try? NSRegularExpression(
        pattern: cellPattern,
        options: [.caseInsensitive, .dotMatchesLineSeparators]
      )
    else { return nil }

    let htmlNSString = html as NSString
    let rowMatches = rowRegex.matches(
      in: html,
      range: NSRange(location: 0, length: htmlNSString.length)
    )
    var rows: [[String]] = []
    var firstRowHasHeaderCells = false

    for rowMatch in rowMatches {
      let rowHTML = htmlNSString.substring(with: rowMatch.range(at: 1))
      let rowNSString = rowHTML as NSString
      let cellMatches = cellRegex.matches(
        in: rowHTML,
        range: NSRange(location: 0, length: rowNSString.length)
      )
      guard !cellMatches.isEmpty else { continue }

      if rows.isEmpty {
        firstRowHasHeaderCells = cellMatches.contains {
          rowNSString.substring(with: $0.range(at: 1)).lowercased() == "h"
        }
      }

      rows.append(
        cellMatches.map {
          let fragment = rowNSString.substring(with: $0.range(at: 2))
          return plainTextFromHTMLFragment(fragment)
        }
      )
    }

    let columnCount = rows.map(\.count).max() ?? 0
    guard rows.count >= 1, columnCount >= 2 else { return nil }

    return MarkdownEditorTable(
      runtimeID: UUID().uuidString,
      hasHeader: firstRowHasHeaderCells,
      columnWidths: Array(repeating: MarkdownEditorTable.defaultColumnWidth, count: columnCount),
      rows: rows.map { normalizedRow($0, columnCount: columnCount) }
    ).normalized()
  }

  private static func pipeCells(from line: String) -> [String]? {
    guard line.contains("|") else { return nil }
    var trimmed = line.trimmingCharacters(in: .whitespaces)
    if trimmed.hasPrefix("|") { trimmed.removeFirst() }
    if trimmed.hasSuffix("|") { trimmed.removeLast() }

    var cells: [String] = []
    var current = ""
    var isEscaped = false
    for character in trimmed {
      if isEscaped {
        current.append(character)
        isEscaped = false
      } else if character == "\\" {
        isEscaped = true
      } else if character == "|" {
        cells.append(current.trimmingCharacters(in: .whitespaces))
        current = ""
      } else {
        current.append(character)
      }
    }
    cells.append(current.trimmingCharacters(in: .whitespaces))
    return cells
  }

  private static func isPipeSeparatorCell(_ cell: String) -> Bool {
    cell.range(of: #"^:?-{3,}:?$"#, options: .regularExpression) != nil
  }

  private static func normalizedRow(_ row: [String], columnCount: Int) -> [String] {
    let padded = row + Array(repeating: "", count: max(columnCount - row.count, 0))
    return Array(padded.prefix(columnCount))
  }

  private static func plainTextFromHTMLFragment(_ fragment: String) -> String {
    let withLineBreaks =
      fragment
      .replacingOccurrences(
        of: #"<br\s*/?>"#,
        with: "\n",
        options: [.regularExpression, .caseInsensitive]
      )
      .replacingOccurrences(
        of: #"</p\s*>"#,
        with: "\n",
        options: [.regularExpression, .caseInsensitive]
      )
    let wrapped = "<html><body>\(withLineBreaks)</body></html>"
    if let data = wrapped.data(using: .utf8),
      let attributed = try? NSAttributedString(
        data: data,
        options: [.documentType: NSAttributedString.DocumentType.html],
        documentAttributes: nil
      )
    {
      return attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    return
      withLineBreaks
      .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
