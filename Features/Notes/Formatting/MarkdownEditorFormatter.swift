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

  // Cached regex patterns to avoid recreation per format pass.
  static let hcolorRegex = try! NSRegularExpression(pattern: #"^<!-- hcolor:(\w+) -->$"#)
  static let sectionDividerRegex = try! NSRegularExpression(
    pattern:
      #"^<!-- section(?:\s+heading:(\w+))?(?:\s+bullet:(\w+))?(?:\s+usesectioncolor:(true|false))? -->$"#
  )
  static let boldRegex = try! NSRegularExpression(pattern: #"\*\*(.+?)\*\*"#)
  static let italicRegex = try! NSRegularExpression(
    pattern: #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#)
  static let strikethroughRegex = try! NSRegularExpression(pattern: #"~~(.+?)~~"#)
  static let inlineCodeRegex = try! NSRegularExpression(pattern: #"`([^`]+)`"#)
  static let linkRegex = try! NSRegularExpression(
    pattern: #"\[([^\]]+)\]\(([^\)]+)\)"#)
  private static let paragraphStyleCacheLock = NSLock()
  private static var bodyParagraphStyles: [BodyParagraphStyleKey: NSParagraphStyle] = [:]
  private static var listParagraphStyles: [ListParagraphStyleKey: NSParagraphStyle] = [:]
  private static var blockquoteParagraphStyles: [BlockquoteParagraphStyleKey: NSParagraphStyle] =
    [:]

  // MARK: - Heading Color Presets (backed by the shared palette)

  static let headingColorPresets: [(name: String, color: NSColor)] =
    ThemePalette.colors.map { ($0.name, $0.color) }

  // Returns the NSColor for a named heading color preset.
  static func headingColor(named name: String) -> NSColor? {
    ThemePalette.color(named: name)
  }

  // Returns the preset name matching an NSColor, or nil.
  static func headingColorName(for color: NSColor) -> String? {
    ThemePalette.name(for: color)
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
    style.firstLineHeadIndent = 20
    style.headIndent = 20
    style.paragraphSpacing = 2
    style.lineHeightMultiple = appearance.lineHeight
    let cachedStyle = style.copy() as! NSParagraphStyle
    blockquoteParagraphStyles[key] = cachedStyle
    return cachedStyle
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
  static func formatForDisplay(_ rawMarkdown: String, appearance: NoteAppearanceSettings)
    -> NSAttributedString
  {
    let result = NSMutableAttributedString()
    let lines = rawMarkdown.split(separator: "\n", omittingEmptySubsequences: false).map(
      String.init)
    var insideCodeBlock = false
    var pendingHeadingColor: NSColor? = nil
    var pendingHeadingColorName: String? = nil
    let hcolorRegex = Self.hcolorRegex
    let sectionRegex = Self.sectionDividerRegex
    // Per-section color state — applies to content after the most recent divider.
    var currentSectionHeadingColorName: String? = nil
    var currentSectionBulletColorName: String? = nil
    var currentSectionUseSectionColor = false
    // Newlines must carry real attributes so NSTextView never inherits bare system defaults.
    let newlineAttrs = baseTypingAttributes(for: appearance)
    // Track when we just emitted a section divider so we can collapse trailing blank lines.
    var justEmittedDivider = false

    for (index, line) in lines.enumerated() {
      // Skip blank lines immediately after a section divider — the divider's own
      // paragraph spacing provides the visual gap, so extra blanks just accumulate.
      if justEmittedDivider && line.trimmingCharacters(in: .whitespaces).isEmpty {
        continue
      }
      justEmittedDivider = false

      if index > 0 {
        result.append(NSAttributedString(string: "\n", attributes: newlineAttrs))
      }

      // Check for heading color comment
      if !insideCodeBlock,
        let match = hcolorRegex.firstMatch(
          in: line, range: NSRange(location: 0, length: line.utf16.count)),
        let nameRange = Range(match.range(at: 1), in: line)
      {
        let colorName = String(line[nameRange])
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
        if let colorName = pendingHeadingColorName {
          result.append(NSAttributedString(string: "<!-- hcolor:\(colorName) -->\n"))
          pendingHeadingColor = nil
          pendingHeadingColorName = nil
        }
        insideCodeBlock.toggle()
        result.append(styledCodeFenceLine(line))
        continue
      }

      if insideCodeBlock {
        result.append(styledCodeBlockLine(line))
        continue
      }

      // Section divider — Sceal-specific card-gap marker with optional per-section colors
      if let sectionMatch = sectionRegex.firstMatch(
        in: line, range: NSRange(location: 0, length: line.utf16.count))
      {
        if let colorName = pendingHeadingColorName {
          result.append(NSAttributedString(string: "<!-- hcolor:\(colorName) -->\n"))
          pendingHeadingColor = nil
          pendingHeadingColorName = nil
        }
        let headingName = extractGroup(sectionMatch, index: 1, in: line)
        let bulletName = extractGroup(sectionMatch, index: 2, in: line)
        let useSCStr = extractGroup(sectionMatch, index: 3, in: line)
        let useSC = useSCStr == "true"

        // Update section tracking state for subsequent lines.
        currentSectionHeadingColorName = headingName
        currentSectionBulletColorName = bulletName
        currentSectionUseSectionColor = useSC

        result.append(
          styledSectionDivider(
            appearance: appearance,
            headingColorName: headingName,
            bulletColorName: bulletName,
            useSectionColor: useSC ? true : nil
          ))
        justEmittedDivider = true
        continue
      }

      // Horizontal rule — standard markdown, renders as a visible line
      if line.range(of: #"^-{3,}$"#, options: .regularExpression) != nil {
        if let colorName = pendingHeadingColorName {
          result.append(NSAttributedString(string: "<!-- hcolor:\(colorName) -->\n"))
          pendingHeadingColor = nil
          pendingHeadingColorName = nil
        }
        result.append(styledHorizontalRule())
        continue
      }

      let displayLine = buildDisplayLine(line, appearance: appearance)

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
        result.append(NSAttributedString(string: "<!-- hcolor:\(colorName) -->\n"))
        pendingHeadingColor = nil
        pendingHeadingColorName = nil
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
      {
        return nil
      }

      // Code block content and fence lines are pre-styled — skip reformatting
      if attrs[.markdownCodeBlock] as? Bool == true
        || attrs[.markdownCodeFence] as? Bool == true
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

}
