//
//  MarkdownStyler.swift
//
//

import AppKit

// MARK: - Custom Attribute Keys

extension NSAttributedString.Key {
  static let markdownHeadingLevel = NSAttributedString.Key("sceal.headingLevel")
  static let markdownListType = NSAttributedString.Key("sceal.listType")
  static let markdownBold = NSAttributedString.Key("sceal.bold")
  static let markdownItalic = NSAttributedString.Key("sceal.italic")
  static let markdownStrikethrough = NSAttributedString.Key("sceal.strikethrough")
  static let markdownLinkURL = NSAttributedString.Key("sceal.linkURL")
  static let markdownCodeFence = NSAttributedString.Key("sceal.codeFence")
  static let markdownCodeBlock = NSAttributedString.Key("sceal.codeBlock")
  static let markdownSectionDivider = NSAttributedString.Key("sceal.sectionDivider")
  static let markdownHorizontalRule = NSAttributedString.Key("sceal.horizontalRule")
  static let markdownInlineCode = NSAttributedString.Key("sceal.inlineCode")
  static let markdownHeadingColor = NSAttributedString.Key("sceal.headingColor")
  static let markdownBlockquote = NSAttributedString.Key("sceal.blockquote")
  static let markdownIndentLevel = NSAttributedString.Key("sceal.indentLevel")
}

enum MarkdownListType: String {
  case bullet
  case numbered
  case checkboxUnchecked
  case checkboxChecked
}

// MARK: - Styler

enum MarkdownStyler {

  static let bulletMarker = "•"
  static let uncheckedMarker = "\u{FFFC}"
  static let checkedMarker = "\u{FFFC}"
  static let attachmentChar = "\u{FFFC}"
  static let sectionDividerSpacingBefore: CGFloat = 10
  static let sectionDividerSpacingAfter: CGFloat = 6
  static let sectionDividerLineHeight: CGFloat = 1

  // Cached regex patterns to avoid recreation per format pass.
  private static let hcolorRegex = try! NSRegularExpression(pattern: #"^<!-- hcolor:(\w+) -->$"#)
  private static let boldRegex = try! NSRegularExpression(pattern: #"\*\*(.+?)\*\*"#)
  private static let italicRegex = try! NSRegularExpression(
    pattern: #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#)
  private static let strikethroughRegex = try! NSRegularExpression(pattern: #"~~(.+?)~~"#)
  private static let inlineCodeRegex = try! NSRegularExpression(pattern: #"`([^`]+)`"#)
  private static let linkRegex = try! NSRegularExpression(
    pattern: #"\[([^\]]+)\]\(([^\)]+)\)"#)

  // MARK: - Heading Color Presets (backed by the shared palette)

  static let headingColorPresets: [(name: String, color: NSColor)] =
    ScealPalette.colors.map { ($0.name, $0.color) }

  static func headingColor(named name: String) -> NSColor? {
    ScealPalette.color(named: name)
  }

  static func headingColorName(for color: NSColor) -> String? {
    ScealPalette.name(for: color)
  }

  static func accentColor(for appearance: NoteAppearanceSettings) -> NSColor {
    appearance.accentColor
  }

  static func checkboxCheckedColor(for appearance: NoteAppearanceSettings) -> NSColor {
    accentColor(for: appearance)
  }

  static func checkboxUncheckedColor(for appearance: NoteAppearanceSettings) -> NSColor {
    accentColor(for: appearance)
  }

  static func bulletColor(for appearance: NoteAppearanceSettings) -> NSColor {
    accentColor(for: appearance)
  }

  static func bodyParagraphStyle(for appearance: NoteAppearanceSettings) -> NSMutableParagraphStyle
  {
    let style = NSMutableParagraphStyle()
    style.lineHeightMultiple = appearance.lineHeight
    return style
  }

  static func listParagraphStyle(for appearance: NoteAppearanceSettings, indentLevel: Int = 0)
    -> NSMutableParagraphStyle
  {
    let style = NSMutableParagraphStyle()
    let indent = CGFloat(indentLevel) * 20
    style.firstLineHeadIndent = 8 + indent
    style.headIndent = 28 + indent
    style.paragraphSpacing = appearance.listItemSpacing
    style.lineHeightMultiple = appearance.lineHeight
    return style
  }

  // Indented style for blockquote lines with a left border feel.
  static func blockquoteParagraphStyle(for appearance: NoteAppearanceSettings)
    -> NSMutableParagraphStyle
  {
    let style = NSMutableParagraphStyle()
    style.firstLineHeadIndent = 20
    style.headIndent = 20
    style.paragraphSpacing = 2
    style.lineHeightMultiple = appearance.lineHeight
    return style
  }

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

  static func checkboxAttributedString(checked: Bool, appearance: NoteAppearanceSettings)
    -> NSAttributedString
  {
    NSAttributedString(attachment: checkboxAttachment(checked: checked, appearance: appearance))
  }

  // MARK: - Raw Markdown → Display Attributed String

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
    // Newlines must carry real attributes so NSTextView never inherits bare system defaults.
    let newlineAttrs = baseTypingAttributes(for: appearance)

    for (index, line) in lines.enumerated() {
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

      // Section divider — Sceal-specific card-gap marker
      if line == "<!-- section -->" {
        if let colorName = pendingHeadingColorName {
          result.append(NSAttributedString(string: "<!-- hcolor:\(colorName) -->\n"))
          pendingHeadingColor = nil
          pendingHeadingColorName = nil
        }
        result.append(styledSectionDivider())
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

      result.append(displayLine)
    }

    return result
  }

  // MARK: - Display → Raw Markdown

  static func convertToMarkdown(from attributedString: NSAttributedString) -> String {
    let nsString = attributedString.string as NSString
    guard nsString.length > 0 else { return "" }

    var markdownLines: [String] = []
    var lineStart = 0

    while lineStart <= nsString.length {
      if lineStart == nsString.length {
        break
      }

      let lineRange = nsString.lineRange(for: NSRange(location: lineStart, length: 0))
      var textRange = lineRange

      // Trim trailing newline from the text range
      if textRange.length > 0
        && nsString.character(at: textRange.location + textRange.length - 1) == 0x0A
      {
        textRange.length -= 1
      }

      let markdownLine = reconstructLine(from: attributedString, textRange: textRange)
      markdownLines.append(markdownLine)
      lineStart = NSMaxRange(lineRange)
    }

    return markdownLines.joined(separator: "\n")
  }

  // MARK: - Live Line Formatting (called on Enter)

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

  // MARK: - Build Display Line (single raw markdown line → attributed string)

  private static func buildDisplayLine(_ rawLine: String, appearance: NoteAppearanceSettings)
    -> NSAttributedString
  {
    // Detect and strip leading whitespace for list indentation (2 spaces = 1 indent level)
    let leadingSpaces = rawLine.prefix(while: { $0 == " " }).count
    let indentLevel = min(leadingSpaces / 2, 3)
    let trimmedLine = indentLevel > 0 ? String(rawLine.dropFirst(indentLevel * 2)) : rawLine

    let baseAttrs: [NSAttributedString.Key: Any] = [
      .font: appearance.bodyFont,
      .foregroundColor: NSColor.labelColor,
      .paragraphStyle: bodyParagraphStyle(for: appearance),
    ]

    // Section divider — Sceal card-gap marker
    if trimmedLine == "<!-- section -->" {
      return styledSectionDivider()
    }

    // Horizontal rule — standard markdown visible line
    if trimmedLine.range(of: #"^-{3,}$"#, options: .regularExpression) != nil {
      return styledHorizontalRule()
    }

    // Heading
    if let match = trimmedLine.range(of: #"^(#{1,3})\s+"#, options: .regularExpression) {
      let level = trimmedLine[match].filter { $0 == "#" }.count
      let content = String(trimmedLine[match.upperBound...])
      let fontSize = headingFontSize(for: level)
      let result = NSMutableAttributedString(
        string: content,
        attributes: [
          .font: appearance.boldBodyFont(ofSize: fontSize),
          .foregroundColor: NSColor.labelColor,
          .markdownHeadingLevel: level,
          .paragraphStyle: bodyParagraphStyle(for: appearance),
        ])
      applyInlineFormatting(in: result, defaultFont: appearance.boldBodyFont(ofSize: fontSize))
      return result
    }

    // Checkbox checked
    if trimmedLine.hasPrefix("- [x] ") {
      let content = String(trimmedLine.dropFirst(6))
      let checkAttr = checkboxAttributedString(checked: true, appearance: appearance)
      let contentAttr = NSMutableAttributedString(string: " \(content)", attributes: baseAttrs)
      applyInlineFormatting(in: contentAttr, defaultFont: appearance.bodyFont)
      let result = NSMutableAttributedString()
      result.append(checkAttr)
      result.append(contentAttr)
      let fullRange = NSRange(location: 0, length: result.length)
      result.addAttributes(
        [
          .markdownListType: MarkdownListType.checkboxChecked.rawValue,
          .strikethroughStyle: NSUnderlineStyle.single.rawValue,
          .paragraphStyle: listParagraphStyle(for: appearance, indentLevel: indentLevel),
          .markdownIndentLevel: indentLevel,
        ], range: fullRange)
      // Remove strikethrough from the checkbox character itself
      result.removeAttribute(.strikethroughStyle, range: NSRange(location: 0, length: 1))
      return result
    }

    // Checkbox unchecked
    if trimmedLine.hasPrefix("- [ ] ") {
      let content = String(trimmedLine.dropFirst(6))
      let checkAttr = checkboxAttributedString(checked: false, appearance: appearance)
      let contentAttr = NSMutableAttributedString(string: " \(content)", attributes: baseAttrs)
      applyInlineFormatting(in: contentAttr, defaultFont: appearance.bodyFont)
      let result = NSMutableAttributedString()
      result.append(checkAttr)
      result.append(contentAttr)
      let fullRange = NSRange(location: 0, length: result.length)
      result.addAttributes(
        [
          .markdownListType: MarkdownListType.checkboxUnchecked.rawValue,
          .paragraphStyle: listParagraphStyle(for: appearance, indentLevel: indentLevel),
          .markdownIndentLevel: indentLevel,
        ], range: fullRange)
      return result
    }

    // Bullet list
    if let prefixMatch = trimmedLine.range(of: #"^(?:-|•)\s+"#, options: .regularExpression) {
      let content = String(trimmedLine[prefixMatch.upperBound...])
      let displayText = "\(bulletMarker) \(content)"
      let result = NSMutableAttributedString(string: displayText, attributes: baseAttrs)
      let fullRange = NSRange(location: 0, length: result.length)
      result.addAttributes(
        [
          .markdownListType: MarkdownListType.bullet.rawValue,
          .paragraphStyle: listParagraphStyle(for: appearance, indentLevel: indentLevel),
          .markdownIndentLevel: indentLevel,
        ], range: fullRange)
      result.addAttributes(
        [
          .foregroundColor: bulletColor(for: appearance),
          .font: NSFont.systemFont(ofSize: appearance.bulletSize, weight: .bold),
        ], range: NSRange(location: 0, length: 1))
      applyInlineFormatting(in: result, defaultFont: appearance.bodyFont)
      return result
    }

    // Numbered list
    if trimmedLine.range(of: #"^\d+\.\s+"#, options: .regularExpression) != nil {
      let result = NSMutableAttributedString(string: trimmedLine, attributes: baseAttrs)
      let fullRange = NSRange(location: 0, length: result.length)
      result.addAttributes(
        [
          .markdownListType: MarkdownListType.numbered.rawValue,
          .paragraphStyle: listParagraphStyle(for: appearance, indentLevel: indentLevel),
          .markdownIndentLevel: indentLevel,
        ], range: fullRange)
      if let numMatch = trimmedLine.range(of: #"^\d+\."#, options: .regularExpression) {
        let numLength = trimmedLine.distance(from: numMatch.lowerBound, to: numMatch.upperBound)
        result.addAttribute(
          .foregroundColor, value: NSColor.secondaryLabelColor,
          range: NSRange(location: 0, length: numLength))
      }
      applyInlineFormatting(in: result, defaultFont: appearance.bodyFont)
      return result
    }

    // Blockquote (single-level only)
    if trimmedLine.hasPrefix("> ") {
      let content = String(trimmedLine.dropFirst(2))
      let quoteStyle = blockquoteParagraphStyle(for: appearance)
      let result = NSMutableAttributedString(
        string: content,
        attributes: [
          .font: appearance.bodyFont,
          .foregroundColor: NSColor.secondaryLabelColor,
          .markdownBlockquote: true,
          .paragraphStyle: quoteStyle,
        ])
      applyInlineFormatting(in: result, defaultFont: appearance.bodyFont)
      return result
    }

    // Plain line — inline formatting only
    let result = NSMutableAttributedString(string: rawLine, attributes: baseAttrs)
    applyInlineFormatting(in: result, defaultFont: appearance.bodyFont)
    return result
  }

  // MARK: - Inline Formatting

  // Strips markdown delimiters and applies display attributes for all inline patterns
  // (bold, italic, strikethrough, code, links) within the given range. Works on both
  // standalone NSMutableAttributedString and NSTextStorage (which inherits from it).
  private static func applyInlineFormatting(
    in attrStr: NSMutableAttributedString,
    range inputRange: NSRange,
    defaultFont: NSFont
  ) {
    var range = inputRange

    // Bold (**text**)
    while true {
      let currentEnd = min(range.location + range.length, attrStr.length)
      let searchRange = NSRange(location: range.location, length: currentEnd - range.location)
      let text = (attrStr.string as NSString).substring(with: searchRange)
      guard
        let match = boldRegex.firstMatch(
          in: text, range: NSRange(location: 0, length: text.utf16.count))
      else { break }

      let innerText = (text as NSString).substring(with: match.range(at: 1))
      let absRange = NSRange(
        location: searchRange.location + match.range(at: 0).location,
        length: match.range(at: 0).length)

      let currentFont =
        attrStr.attribute(.font, at: absRange.location, effectiveRange: nil) as? NSFont
        ?? defaultFont
      let boldFont = NSFontManager.shared.convert(currentFont, toHaveTrait: .boldFontMask)

      attrStr.replaceCharacters(in: absRange, with: innerText)
      let newRange = NSRange(location: absRange.location, length: innerText.utf16.count)
      range.length -= absRange.length - newRange.length
      attrStr.addAttributes([.font: boldFont, .markdownBold: true], range: newRange)
    }

    // Italic (*text*)
    while true {
      let currentEnd = min(range.location + range.length, attrStr.length)
      let searchRange = NSRange(location: range.location, length: currentEnd - range.location)
      let text = (attrStr.string as NSString).substring(with: searchRange)
      guard
        let match = italicRegex.firstMatch(
          in: text, range: NSRange(location: 0, length: text.utf16.count))
      else { break }

      let innerText = (text as NSString).substring(with: match.range(at: 1))
      let absRange = NSRange(
        location: searchRange.location + match.range(at: 0).location,
        length: match.range(at: 0).length)

      let currentFont =
        attrStr.attribute(.font, at: absRange.location, effectiveRange: nil) as? NSFont
        ?? defaultFont
      let italicFont = NSFontManager.shared.convert(currentFont, toHaveTrait: .italicFontMask)

      attrStr.replaceCharacters(in: absRange, with: innerText)
      let newRange = NSRange(location: absRange.location, length: innerText.utf16.count)
      range.length -= absRange.length - newRange.length
      attrStr.addAttributes([.font: italicFont, .markdownItalic: true], range: newRange)
    }

    // Strikethrough (~~text~~)
    while true {
      let currentEnd = min(range.location + range.length, attrStr.length)
      let searchRange = NSRange(location: range.location, length: currentEnd - range.location)
      let text = (attrStr.string as NSString).substring(with: searchRange)
      guard
        let match = strikethroughRegex.firstMatch(
          in: text, range: NSRange(location: 0, length: text.utf16.count))
      else { break }

      let innerText = (text as NSString).substring(with: match.range(at: 1))
      let absRange = NSRange(
        location: searchRange.location + match.range(at: 0).location,
        length: match.range(at: 0).length)

      attrStr.replaceCharacters(in: absRange, with: innerText)
      let newRange = NSRange(location: absRange.location, length: innerText.utf16.count)
      range.length -= absRange.length - newRange.length
      attrStr.addAttributes(
        [
          .strikethroughStyle: NSUnderlineStyle.single.rawValue,
          .markdownStrikethrough: true,
        ], range: newRange)
    }

    // Inline code (`text`)
    while true {
      let currentEnd = min(range.location + range.length, attrStr.length)
      let searchRange = NSRange(location: range.location, length: currentEnd - range.location)
      let text = (attrStr.string as NSString).substring(with: searchRange)
      guard
        let match = inlineCodeRegex.firstMatch(
          in: text, range: NSRange(location: 0, length: text.utf16.count))
      else { break }

      let innerText = (text as NSString).substring(with: match.range(at: 1))
      let absRange = NSRange(
        location: searchRange.location + match.range(at: 0).location,
        length: match.range(at: 0).length)

      attrStr.replaceCharacters(in: absRange, with: innerText)
      let newRange = NSRange(location: absRange.location, length: innerText.utf16.count)
      range.length -= absRange.length - newRange.length
      attrStr.addAttributes(
        [
          .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
          .backgroundColor: NSColor.quaternaryLabelColor,
          .markdownInlineCode: true,
        ], range: newRange)
    }

    // Links ([text](url))
    while true {
      let currentEnd = min(range.location + range.length, attrStr.length)
      let searchRange = NSRange(location: range.location, length: currentEnd - range.location)
      let text = (attrStr.string as NSString).substring(with: searchRange)
      guard
        let match = linkRegex.firstMatch(
          in: text, range: NSRange(location: 0, length: text.utf16.count))
      else { break }

      let linkText = (text as NSString).substring(with: match.range(at: 1))
      let urlString = (text as NSString).substring(with: match.range(at: 2))
      let absRange = NSRange(
        location: searchRange.location + match.range(at: 0).location,
        length: match.range(at: 0).length)

      attrStr.replaceCharacters(in: absRange, with: linkText)
      let newRange = NSRange(location: absRange.location, length: linkText.utf16.count)
      range.length -= absRange.length - newRange.length

      var attrs: [NSAttributedString.Key: Any] = [
        .foregroundColor: NSColor.linkColor,
        .markdownLinkURL: urlString,
      ]
      if let url = URL(string: urlString) { attrs[.link] = url }
      attrStr.addAttributes(attrs, range: newRange)
    }
  }

  // Convenience for applying all inline formatting to a standalone attributed string.
  private static func applyInlineFormatting(
    in attrStr: NSMutableAttributedString, defaultFont: NSFont
  ) {
    applyInlineFormatting(
      in: attrStr, range: NSRange(location: 0, length: attrStr.length), defaultFont: defaultFont)
  }

  // MARK: - Reconstruct Markdown from Display Line

  private static func reconstructLine(
    from attributedString: NSAttributedString, textRange: NSRange
  ) -> String {
    guard textRange.length > 0 else { return "" }

    let nsString = attributedString.string as NSString
    let lineText = nsString.substring(with: textRange)
    let attrs = attributedString.attributes(at: textRange.location, effectiveRange: nil)

    // Code fence — pass through
    if attrs[.markdownCodeFence] as? Bool == true {
      return lineText
    }

    // Code block — pass through
    if attrs[.markdownCodeBlock] as? Bool == true {
      return lineText
    }

    // Section divider — Sceal-specific card-gap marker
    if attrs[.markdownSectionDivider] as? Bool == true {
      return "<!-- section -->"
    }

    // Horizontal rule — standard markdown
    if attrs[.markdownHorizontalRule] as? Bool == true {
      return "---"
    }

    // Determine line prefix from attributes
    var prefix = ""
    var contentStart = 0

    if let level = attrs[.markdownHeadingLevel] as? Int {
      prefix = String(repeating: "#", count: level) + " "
      contentStart = 0

      // Heading color comment
      if let colorName = attrs[.markdownHeadingColor] as? String {
        let contentRange = NSRange(
          location: textRange.location + contentStart,
          length: textRange.length - contentStart
        )
        let inlineMarkdown = reconstructInlineMarkdown(from: attributedString, range: contentRange)
        return "<!-- hcolor:\(colorName) -->\n" + prefix + inlineMarkdown
      }
    } else if attrs[.markdownBlockquote] as? Bool == true {
      prefix = "> "
      contentStart = 0
    } else if let rawType = attrs[.markdownListType] as? String,
      let listType = MarkdownListType(rawValue: rawType)
    {
      let indentLevel = attrs[.markdownIndentLevel] as? Int ?? 0
      let indentPrefix = indentLevel > 0 ? String(repeating: " ", count: indentLevel * 2) : ""
      switch listType {
      case .bullet:
        prefix = indentPrefix + "- "
        contentStart = lineText.hasPrefix("\(bulletMarker) ") ? 2 : 0
      case .checkboxUnchecked:
        prefix = indentPrefix + "- [ ] "
        contentStart = lineText.hasPrefix("\(uncheckedMarker) ") ? 2 : 0
      case .checkboxChecked:
        prefix = indentPrefix + "- [x] "
        contentStart = lineText.hasPrefix("\(checkedMarker) ") ? 2 : 0
      case .numbered:
        // Number text is already in the display, pass through
        let inlineMarkdown = reconstructInlineMarkdown(
          from: attributedString,
          range: textRange
        )
        return indentPrefix + inlineMarkdown
      }
    }

    // Get the content portion (after display marker)
    let contentRange = NSRange(
      location: textRange.location + contentStart,
      length: textRange.length - contentStart
    )

    let inlineMarkdown = reconstructInlineMarkdown(from: attributedString, range: contentRange)
    return prefix + inlineMarkdown
  }

  private static func reconstructInlineMarkdown(
    from attributedString: NSAttributedString, range: NSRange
  ) -> String {
    guard range.length > 0 else { return "" }

    var result = ""
    let nsString = attributedString.string as NSString

    attributedString.enumerateAttributes(in: range, options: []) { attrs, spanRange, _ in
      let text = nsString.substring(with: spanRange)
      let isBold = attrs[.markdownBold] as? Bool == true
      let isItalic = attrs[.markdownItalic] as? Bool == true
      let isStrike = attrs[.markdownStrikethrough] as? Bool == true
      let isCode = attrs[.markdownInlineCode] as? Bool == true
      let linkURL = attrs[.markdownLinkURL] as? String

      // Build the inner content with bold/italic/link wrapping
      var inner: String
      if isCode {
        inner = "`\(text)`"
      } else if isBold && isItalic, let url = linkURL {
        inner = "***[\(text)](\(url))***"
      } else if isBold && isItalic {
        inner = "***\(text)***"
      } else if isBold, let url = linkURL {
        inner = "**[\(text)](\(url))**"
      } else if isBold {
        inner = "**\(text)**"
      } else if isItalic, let url = linkURL {
        inner = "*[\(text)](\(url))*"
      } else if isItalic {
        inner = "*\(text)*"
      } else if let url = linkURL {
        inner = "[\(text)](\(url))"
      } else {
        inner = text
      }

      // Wrap with strikethrough delimiters if needed
      if isStrike {
        result += "~~\(inner)~~"
      } else {
        result += inner
      }
    }

    return result
  }

  // MARK: - Styled Special Lines (kept as raw text, just styled)

  private static func styledCodeFenceLine(_ line: String) -> NSAttributedString {
    NSAttributedString(
      string: line,
      attributes: [
        .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
        .foregroundColor: NSColor.tertiaryLabelColor,
        .markdownCodeFence: true,
      ])
  }

  private static func styledCodeBlockLine(_ line: String) -> NSAttributedString {
    NSAttributedString(
      string: line,
      attributes: [
        .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
        .backgroundColor: NSColor.quaternaryLabelColor,
        .foregroundColor: NSColor.labelColor,
        .markdownCodeBlock: true,
      ])
  }

  private static func styledSectionDivider() -> NSAttributedString {
    // Invisible marker — the visual split comes from ScealTextView drawing
    // separate card backgrounds for each section. This character occupies
    // a single line that becomes the gap between cards.
    let gapStyle = NSMutableParagraphStyle()
    gapStyle.paragraphSpacingBefore = sectionDividerSpacingBefore
    gapStyle.paragraphSpacing = sectionDividerSpacingAfter
    gapStyle.minimumLineHeight = sectionDividerLineHeight
    gapStyle.maximumLineHeight = sectionDividerLineHeight

    return NSAttributedString(
      string: " ",
      attributes: [
        .font: NSFont.systemFont(ofSize: 1),
        .foregroundColor: NSColor.clear,
        .paragraphStyle: gapStyle,
        .markdownSectionDivider: true,
      ])
  }

  // Exposes the final divider display form for editor insertions that must avoid raw markdown text.
  static func sectionDividerDisplayString() -> NSAttributedString {
    styledSectionDivider()
  }

  // Visible thin line for standard markdown horizontal rules (e.g. imported `---`).
  // The actual line is drawn by ScealTextView; this marker reserves the vertical space.
  private static func styledHorizontalRule() -> NSAttributedString {
    let style = NSMutableParagraphStyle()
    style.paragraphSpacingBefore = 8
    style.paragraphSpacing = 8
    style.maximumLineHeight = 1

    return NSAttributedString(
      string: " ",
      attributes: [
        .font: NSFont.systemFont(ofSize: 1),
        .foregroundColor: NSColor.clear,
        .paragraphStyle: style,
        .markdownHorizontalRule: true,
      ])
  }

  // MARK: - Helpers

  static func headingFontSize(for level: Int) -> CGFloat {
    switch level {
    case 1:
      return 22
    case 2:
      return 19
    default:
      return 17
    }
  }
}
