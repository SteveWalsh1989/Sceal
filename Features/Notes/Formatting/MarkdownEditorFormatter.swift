//
//  MarkdownEditorFormatter.swift
//
//

// Bidirectional markdown <-> NSAttributedString conversion engine with live formatting.

import AppKit

// MARK: - Styler

enum MarkdownEditorFormatter {

  private struct BodyParagraphStyleKey: Hashable {
    let lineHeight: CGFloat
  }

  private struct ListParagraphStyleKey: Hashable {
    let lineHeight: CGFloat
    let itemSpacing: CGFloat
    let indentLevel: Int
  }

  private struct BlockquoteParagraphStyleKey: Hashable {
    let lineHeight: CGFloat
  }

  static let bulletMarker = "•"
  static let uncheckedMarker = "\u{FFFC}"
  static let checkedMarker = "\u{FFFC}"
  static let attachmentChar = "\u{FFFC}"
  static let sectionDividerSpacingBefore: CGFloat = 10
  static let sectionDividerSpacingAfter: CGFloat = 6
  static let sectionDividerLineHeight: CGFloat = 1
  static let promptBlockStartMarker = MarkdownEditorPromptBlockMarkdown.startMarker
  static let promptBlockEndMarker = MarkdownEditorPromptBlockMarkdown.endMarker
  static let promptBoundaryStartKind = MarkdownEditorPromptBlockMarkdown.startBoundaryKind
  static let promptBoundaryEndKind = MarkdownEditorPromptBlockMarkdown.endBoundaryKind
  static let imageDefaultWidth = MarkdownEditorImageMarkdown.defaultWidth
  static let imageMinimumWidth = MarkdownEditorImageMarkdown.minimumWidth
  static let imageMaximumWidth = MarkdownEditorImageMarkdown.maximumWidth
  static let imageResizeStep = MarkdownEditorImageMarkdown.resizeStep

  // Cached regex patterns to avoid recreation per format pass.
  static let boldRegex = try! NSRegularExpression(pattern: #"\*\*(.+?)\*\*"#)
  static let italicRegex = try! NSRegularExpression(
    pattern: #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#)
  static let strikethroughRegex = try! NSRegularExpression(pattern: #"~~(.+?)~~"#)
  static let inlineCodeRegex = try! NSRegularExpression(pattern: #"`([^`]+)`"#)
  static let linkRegex = try! NSRegularExpression(
    pattern: #"\[([^\]]+)\]\(([^\)]+)\)"#)
  static let urlDetector = try? NSDataDetector(
    types: NSTextCheckingResult.CheckingType.link.rawValue)
  private static let paragraphStyleCacheLock = NSLock()
  private static var bodyParagraphStyles: [BodyParagraphStyleKey: NSParagraphStyle] = [:]
  private static var listParagraphStyles: [ListParagraphStyleKey: NSParagraphStyle] = [:]
  private static var blockquoteParagraphStyles: [BlockquoteParagraphStyleKey: NSParagraphStyle] =
    [:]

  // Returns the NSColor for a named heading color preset.
  static func headingColor(named name: String) -> NSColor? {
    ThemePalette.color(named: name)
  }

  // Resolves the accent NSColor from appearance settings.
  static func accentColor(for appearance: NoteAppearanceSettings) -> NSColor {
    appearance.accentColor
  }

  // Accent color used for checked checkbox attachments.
  static func checkboxCheckedColor(for appearance: NoteAppearanceSettings) -> NSColor {
    accentColor(for: appearance)
  }

  // Dimmed color used for unchecked checkbox attachments.
  static func checkboxUncheckedColor(for appearance: NoteAppearanceSettings) -> NSColor {
    accentColor(for: appearance)
  }

  // Accent color used for bullet markers.
  static func bulletColor(for appearance: NoteAppearanceSettings) -> NSColor {
    accentColor(for: appearance)
  }

  // Paragraph style for regular body text with configurable line height.
  static func bodyParagraphStyle(for appearance: NoteAppearanceSettings) -> NSParagraphStyle {
    let key = BodyParagraphStyleKey(lineHeight: appearance.lineHeight)
    paragraphStyleCacheLock.lock()
    defer { paragraphStyleCacheLock.unlock() }
    if let cachedStyle = bodyParagraphStyles[key] {
      return cachedStyle
    }

    let style = NSMutableParagraphStyle()
    style.baseWritingDirection = .leftToRight
    style.lineHeightMultiple = appearance.lineHeight
    let cachedStyle = style.copy() as! NSParagraphStyle
    bodyParagraphStyles[key] = cachedStyle
    return cachedStyle
  }

  // Paragraph style for list items with indent-based leading margin.
  static func listParagraphStyle(for appearance: NoteAppearanceSettings, indentLevel: Int = 0)
    -> NSParagraphStyle
  {
    let key = ListParagraphStyleKey(
      lineHeight: appearance.lineHeight,
      itemSpacing: appearance.listItemSpacing,
      indentLevel: indentLevel
    )
    paragraphStyleCacheLock.lock()
    defer { paragraphStyleCacheLock.unlock() }
    if let cachedStyle = listParagraphStyles[key] {
      return cachedStyle
    }

    let style = NSMutableParagraphStyle()
    let indent = CGFloat(indentLevel) * 20
    style.baseWritingDirection = .leftToRight
    style.firstLineHeadIndent = 8 + indent
    style.headIndent = 28 + indent
    style.paragraphSpacing = appearance.listItemSpacing
    style.lineHeightMultiple = appearance.lineHeight
    let cachedStyle = style.copy() as! NSParagraphStyle
    listParagraphStyles[key] = cachedStyle
    return cachedStyle
  }

  // Indented style for blockquote lines with a left border feel.
  static func blockquoteParagraphStyle(for appearance: NoteAppearanceSettings)
    -> NSParagraphStyle
  {
    let key = BlockquoteParagraphStyleKey(lineHeight: appearance.lineHeight)
    paragraphStyleCacheLock.lock()
    defer { paragraphStyleCacheLock.unlock() }
    if let cachedStyle = blockquoteParagraphStyles[key] {
      return cachedStyle
    }

    let style = NSMutableParagraphStyle()
    style.baseWritingDirection = .leftToRight
    style.firstLineHeadIndent = 20
    style.headIndent = 20
    style.paragraphSpacing = 2
    style.lineHeightMultiple = appearance.lineHeight
    let cachedStyle = style.copy() as! NSParagraphStyle
    blockquoteParagraphStyles[key] = cachedStyle
    return cachedStyle
  }

  // Paragraph style for prompt blocks; the trailing inset leaves room for the copy button.
  static func promptBlockParagraphStyle(for appearance: NoteAppearanceSettings)
    -> NSParagraphStyle
  {
    let style = NSMutableParagraphStyle()
    style.baseWritingDirection = .leftToRight
    style.firstLineHeadIndent = 18
    style.headIndent = 18
    style.tailIndent = -114
    style.paragraphSpacing = 2
    style.lineHeightMultiple = appearance.lineHeight
    return style.copy() as! NSParagraphStyle
  }

  // Default typing attributes applied to new text in the editor.
  static func baseTypingAttributes(for appearance: NoteAppearanceSettings)
    -> [NSAttributedString.Key: Any]
  {
    [
      .font: appearance.bodyFont,
      .foregroundColor: NSColor.labelColor,
      .paragraphStyle: bodyParagraphStyle(for: appearance),
    ]
  }

  // MARK: - Checkbox Attachments

  // Creates an SF Symbol checkbox attachment using the accent color.
  static func checkboxAttachment(checked: Bool, appearance: NoteAppearanceSettings)
    -> NSTextAttachment
  {
    let symbolName = checked ? "checkmark.circle.fill" : "circle"
    let color =
      checked ? checkboxCheckedColor(for: appearance) : checkboxUncheckedColor(for: appearance)
    let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
      .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
    let attachment = NSTextAttachment()
    attachment.image = NSImage(
      systemSymbolName: symbolName, accessibilityDescription: checked ? "Done" : "To do")?
      .withSymbolConfiguration(config)
    return attachment
  }

  // Wraps a checkbox attachment in an attributed string with list attributes.
  static func checkboxAttributedString(checked: Bool, appearance: NoteAppearanceSettings)
    -> NSAttributedString
  {
    NSAttributedString(attachment: checkboxAttachment(checked: checked, appearance: appearance))
  }

  // Section-color variant — uses a specific color instead of the global accent.
  static func checkboxAttachment(checked: Bool, color: NSColor) -> NSTextAttachment {
    let symbolName = checked ? "checkmark.circle.fill" : "circle"
    let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
      .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
    let attachment = NSTextAttachment()
    attachment.image = NSImage(
      systemSymbolName: symbolName, accessibilityDescription: checked ? "Done" : "To do")?
      .withSymbolConfiguration(config)
    return attachment
  }

  // MARK: - Raw Markdown → Display Attributed String

  // Converts raw markdown to a display-ready NSAttributedString with hidden delimiters.
  static func formatForDisplay(
    _ rawMarkdown: String,
    appearance: NoteAppearanceSettings,
    initialSectionHeadingColorName: String? = nil,
    initialSectionBulletColorName: String? = nil,
    initialSectionUseSectionColor: Bool = false,
    libraryRootURL: URL? = nil
  )
    -> NSAttributedString
  {
    let result = NSMutableAttributedString()
    let lines = rawMarkdown.split(separator: "\n", omittingEmptySubsequences: false).map(
      String.init)
    var insideCodeBlock = false
    var insidePromptBlock = false
    var pendingHeadingColor: NSColor? = nil
    var pendingHeadingColorName: String? = nil
    let tableBlocks = tableBlocks(in: lines)
    var skippingTableUntilIndex: Int? = nil
    // Per-section color state — applies to content after the most recent divider.
    var currentSectionHeadingColorName = initialSectionHeadingColorName
    var currentSectionBulletColorName = initialSectionBulletColorName
    var currentSectionUseSectionColor = initialSectionUseSectionColor
    // Newlines must carry real attributes so NSTextView never inherits bare system defaults.
    let newlineAttrs = baseTypingAttributes(for: appearance)
    // Track when we just emitted a section divider so we can collapse trailing blank lines.
    var justEmittedDivider = false
    var pendingImageWidth: CGFloat? = nil
    var skippedPreviousImageWidthMarker = false

    func flushPendingHeadingColorMarker() {
      guard let colorName = pendingHeadingColorName else { return }
      result.append(
        NSAttributedString(
          string: "\(MarkdownEditorHeadingColorMarkdown.marker(colorName: colorName))\n"
        ))
      pendingHeadingColor = nil
      pendingHeadingColorName = nil
    }

    for (index, line) in lines.enumerated() {
      if let skipEndIndex = skippingTableUntilIndex {
        if index <= skipEndIndex {
          if index == skipEndIndex {
            skippingTableUntilIndex = nil
          }
          continue
        }
        skippingTableUntilIndex = nil
      }

      // Skip blank lines immediately after a section divider — the divider's own
      // paragraph spacing provides the visual gap, so extra blanks just accumulate.
      if justEmittedDivider && line.trimmingCharacters(in: .whitespaces).isEmpty {
        continue
      }
      justEmittedDivider = false

      if let tableBlock = tableBlocks[index], !insideCodeBlock, !insidePromptBlock {
        if index > 0, !skippedPreviousImageWidthMarker {
          result.append(NSAttributedString(string: "\n", attributes: newlineAttrs))
        }
        skippedPreviousImageWidthMarker = false
        skippingTableUntilIndex = tableBlock.endIndex

        flushPendingHeadingColorMarker()
        result.append(styledTableBlock(tableBlock.table, appearance: appearance))
        continue
      }

      if index > 0, !skippedPreviousImageWidthMarker {
        result.append(NSAttributedString(string: "\n", attributes: newlineAttrs))
      }
      skippedPreviousImageWidthMarker = false

      if !insideCodeBlock,
        MarkdownEditorPromptBlockMarkdown.boundaryKind(for: line) == promptBoundaryStartKind
      {
        flushPendingHeadingColorMarker()
        insidePromptBlock = true
        result.append(
          styledPromptBoundaryLine(kind: promptBoundaryStartKind, appearance: appearance))
        continue
      }

      if !insideCodeBlock, insidePromptBlock,
        MarkdownEditorPromptBlockMarkdown.boundaryKind(for: line) == promptBoundaryEndKind
      {
        insidePromptBlock = false
        result.append(
          styledPromptBoundaryLine(kind: promptBoundaryEndKind, appearance: appearance))
        continue
      }

      if insidePromptBlock {
        result.append(styledPromptBlockLine(line, appearance: appearance))
        continue
      }

      // Check for heading color comment
      if !insideCodeBlock,
        let colorName = MarkdownEditorHeadingColorMarkdown.parseColorName(line)
      {
        if let color = headingColor(named: colorName) {
          pendingHeadingColor = color
          pendingHeadingColorName = colorName
          continue
        }
      }

      // Allow blank lines between a heading color comment and its heading
      if line.trimmingCharacters(in: .whitespaces).isEmpty, pendingHeadingColor != nil {
        result.append(NSAttributedString(string: "", attributes: newlineAttrs))
        continue
      }

      if line.hasPrefix("```") {
        // Flush pending color as-is if next line is a code fence
        flushPendingHeadingColorMarker()
        insideCodeBlock.toggle()
        result.append(styledCodeFenceLine(line))
        continue
      }

      if insideCodeBlock {
        result.append(styledCodeBlockLine(line))
        continue
      }

      if let imageWidth = parseImageWidthMarker(line),
        lines.indices.contains(index + 1),
        parseMarkdownImage(lines[index + 1]) != nil
      {
        pendingImageWidth = imageWidth
        skippedPreviousImageWidthMarker = true
        continue
      }

      // Section divider — Sceal-specific card-gap marker with optional per-section colors
      if let section = MarkdownEditorSectionDirectiveMarkdown.parse(line) {
        flushPendingHeadingColorMarker()

        // Update section tracking state for subsequent lines.
        currentSectionHeadingColorName = section.headingColorName
        currentSectionBulletColorName = section.bulletColorName
        currentSectionUseSectionColor = section.usesSectionColor

        result.append(
          styledSectionDivider(
            appearance: appearance,
            headingColorName: section.headingColorName,
            bulletColorName: section.bulletColorName,
            useSectionColor: section.usesSectionColor ? true : nil
          ))
        justEmittedDivider = true
        continue
      }

      // Horizontal rule — standard markdown, renders as a visible line
      if line.range(of: #"^-{3,}$"#, options: .regularExpression) != nil {
        flushPendingHeadingColorMarker()
        result.append(styledHorizontalRule())
        continue
      }

      let displayLine = buildDisplayLine(
        line,
        appearance: appearance,
        imageWidth: pendingImageWidth,
        libraryRootURL: libraryRootURL
      )
      if parseMarkdownImage(line) != nil {
        pendingImageWidth = nil
      }

      // Apply pending heading color if this line is a heading
      if let color = pendingHeadingColor, let colorName = pendingHeadingColorName {
        let mutable = NSMutableAttributedString(attributedString: displayLine)
        if mutable.length > 0 {
          let attrs = mutable.attributes(at: 0, effectiveRange: nil)
          if attrs[.markdownHeadingLevel] != nil {
            let fullRange = NSRange(location: 0, length: mutable.length)
            mutable.addAttribute(.foregroundColor, value: color, range: fullRange)
            mutable.addAttribute(.markdownHeadingColor, value: colorName, range: fullRange)
            result.append(mutable)
            pendingHeadingColor = nil
            pendingHeadingColorName = nil
            continue
          }
        }
        // Not a heading — flush the color comment back
        flushPendingHeadingColorMarker()
      }

      // Apply section-level color defaults to headings without an explicit hcolor
      // and to bullets/checkboxes when the section's useSectionColor flag is on.
      if let colored = applySectionColors(
        to: displayLine,
        headingColorName: currentSectionHeadingColorName,
        bulletColorName: currentSectionBulletColorName,
        useSectionColor: currentSectionUseSectionColor,
        appearance: appearance
      ) {
        result.append(colored)
        continue
      }

      result.append(displayLine)
    }

    return result
  }

  private static func tableBlocks(
    in lines: [String]
  ) -> [Int: (endIndex: Int, table: MarkdownEditorTable)] {
    var blocks: [Int: (endIndex: Int, table: MarkdownEditorTable)] = [:]
    var index = 0

    while index < lines.count {
      guard MarkdownEditorTableMarkdown.isStartLine(lines[index]) else {
        index += 1
        continue
      }

      var endIndex = index
      while endIndex < lines.count {
        if MarkdownEditorTableMarkdown.isEndLine(lines[endIndex]) {
          break
        }
        endIndex += 1
      }

      guard endIndex < lines.count,
        let table = MarkdownEditorTableMarkdown.parseBlock(lines[index...endIndex])
      else {
        index += 1
        continue
      }

      blocks[index] = (endIndex, table)
      index = endIndex + 1
    }

    return blocks
  }

  // MARK: - Live Line Formatting (called on Enter)

  // Re-formats a single line in-place after Enter, returning the detected list type.
  @discardableResult
  static func formatCurrentLine(
    in textStorage: NSTextStorage, lineRange: NSRange, appearance: NoteAppearanceSettings
  ) -> MarkdownListType? {
    let nsString = textStorage.string as NSString
    let lineText = nsString.substring(with: lineRange)

    // Check if line already has formatting attributes (was formatted before)
    if lineRange.length > 0 {
      let attrs = textStorage.attributes(at: lineRange.location, effectiveRange: nil)
      // Section dividers and horizontal rules are fully styled — no further processing needed
      if attrs[.markdownSectionDivider] as? Bool == true
        || attrs[.markdownHorizontalRule] as? Bool == true
        || attrs[.markdownPromptBoundary] as? Bool == true
        || attrs[.markdownImageBlock] as? Bool == true
        || attrs[.markdownTableBlock] as? Bool == true
      {
        return nil
      }

      // Code and prompt block content is pre-styled — skip reformatting.
      if attrs[.markdownCodeBlock] as? Bool == true
        || attrs[.markdownCodeFence] as? Bool == true
        || attrs[.markdownPromptBlock] as? Bool == true
      {
        return nil
      }

      let alreadyFormatted =
        attrs[.markdownHeadingLevel] != nil || attrs[.markdownListType] != nil
        || attrs[.markdownBlockquote] as? Bool == true

      if alreadyFormatted {
        // Only process inline formatting on existing formatted lines
        textStorage.beginEditing()
        applyInlineFormatting(
          in: textStorage, range: lineRange, defaultFont: appearance.bodyFont)
        textStorage.endEditing()
        if let rawType = attrs[.markdownListType] as? String {
          return MarkdownListType(rawValue: rawType)
        }
        return nil
      }

      if lineContainsInlineFormatting(in: textStorage, range: lineRange) {
        let rawMarkdownLine = convertToMarkdown(
          from: textStorage.attributedSubstring(from: lineRange))
        let displayLine = buildDisplayLine(rawMarkdownLine, appearance: appearance)

        textStorage.beginEditing()
        textStorage.replaceCharacters(in: lineRange, with: displayLine)
        textStorage.endEditing()

        if displayLine.length > 0 {
          let displayAttrs = displayLine.attributes(at: 0, effectiveRange: nil)
          if let rawType = displayAttrs[.markdownListType] as? String {
            return MarkdownListType(rawValue: rawType)
          }
        }

        return nil
      }
    }

    // Build formatted version of this raw markdown line
    let displayLine = buildDisplayLine(lineText, appearance: appearance)

    textStorage.beginEditing()
    textStorage.replaceCharacters(in: lineRange, with: displayLine)
    textStorage.endEditing()

    // Determine list type from the formatted line
    if displayLine.length > 0 {
      let attrs = displayLine.attributes(at: 0, effectiveRange: nil)
      if let rawType = attrs[.markdownListType] as? String {
        return MarkdownListType(rawValue: rawType)
      }
    }

    return nil
  }

  // Detects inline markdown semantics so line reformatting can rebuild from markdown instead of display text.
  private static func lineContainsInlineFormatting(in textStorage: NSTextStorage, range: NSRange)
    -> Bool
  {
    var containsInlineFormatting = false

    textStorage.enumerateAttributes(in: range, options: []) { attrs, _, stop in
      let hasInlineFormatting =
        attrs[.markdownBold] as? Bool == true
        || attrs[.markdownItalic] as? Bool == true
        || attrs[.markdownStrikethrough] as? Bool == true
        || attrs[.markdownInlineCode] as? Bool == true
        || attrs[.markdownLinkURL] != nil
        || attrs[.link] != nil

      if hasInlineFormatting {
        containsInlineFormatting = true
        stop.pointee = true
      }
    }

    return containsInlineFormatting
  }

}
