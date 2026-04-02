//
//  MarkdownStyler.swift
//  dayra
//
//

import AppKit

// MARK: - Custom Attribute Keys

extension NSAttributedString.Key {
  static let markdownHeadingLevel = NSAttributedString.Key("dayra.headingLevel")
  static let markdownListType = NSAttributedString.Key("dayra.listType")
  static let markdownBold = NSAttributedString.Key("dayra.bold")
  static let markdownItalic = NSAttributedString.Key("dayra.italic")
  static let markdownStrikethrough = NSAttributedString.Key("dayra.strikethrough")
  static let markdownLinkURL = NSAttributedString.Key("dayra.linkURL")
  static let markdownCodeFence = NSAttributedString.Key("dayra.codeFence")
  static let markdownCodeBlock = NSAttributedString.Key("dayra.codeBlock")
  static let markdownSectionDivider = NSAttributedString.Key("dayra.sectionDivider")
  static let markdownHorizontalRule = NSAttributedString.Key("dayra.horizontalRule")
  static let markdownInlineCode = NSAttributedString.Key("dayra.inlineCode")
  static let markdownHeadingColor = NSAttributedString.Key("dayra.headingColor")
  static let markdownBlockquote = NSAttributedString.Key("dayra.blockquote")
}

enum MarkdownListType: String {
  case bullet
  case numbered
  case checkboxUnchecked
  case checkboxChecked
}

// MARK: - Shared Color Palette

/// Muted flat palette shared across headings, bullets, checkboxes, and future appearance settings.
enum DayraPalette {

  struct Entry {
    let name: String
    let color: NSColor
  }

  static let colors: [Entry] = [
    Entry(name: "blue", color: NSColor(red: 0.35, green: 0.55, blue: 0.85, alpha: 1)),
    Entry(name: "turquoise", color: NSColor(red: 0.30, green: 0.72, blue: 0.68, alpha: 1)),
    Entry(name: "pink", color: NSColor(red: 0.85, green: 0.40, blue: 0.55, alpha: 1)),
    Entry(name: "red", color: NSColor(red: 0.82, green: 0.35, blue: 0.35, alpha: 1)),
    Entry(name: "purple", color: NSColor(red: 0.60, green: 0.42, blue: 0.78, alpha: 1)),
    Entry(name: "orange", color: NSColor(red: 0.90, green: 0.58, blue: 0.30, alpha: 1)),
    Entry(name: "grey", color: NSColor(red: 0.58, green: 0.58, blue: 0.60, alpha: 1)),
    Entry(
      name: "white",
      color: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
          ? .white : .black
      }),
  ]

  static func color(named name: String) -> NSColor? {
    colors.first(where: { $0.name == name })?.color
  }

  static func name(for color: NSColor) -> String? {
    colors.first(where: { $0.color == color })?.name
  }
}

// MARK: - Styler

enum MarkdownStyler {

  static let bulletMarker = "•"
  static let uncheckedMarker = "\u{FFFC}"
  static let checkedMarker = "\u{FFFC}"
  static let attachmentChar = "\u{FFFC}"

  // MARK: - Heading Color Presets (backed by the shared palette)

  static let headingColorPresets: [(name: String, color: NSColor)] =
    DayraPalette.colors.map { ($0.name, $0.color) }

  static func headingColor(named name: String) -> NSColor? {
    DayraPalette.color(named: name)
  }

  static func headingColorName(for color: NSColor) -> String? {
    DayraPalette.name(for: color)
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

  static func listParagraphStyle(for appearance: NoteAppearanceSettings) -> NSMutableParagraphStyle
  {
    let style = NSMutableParagraphStyle()
    style.firstLineHeadIndent = 8
    style.headIndent = 28
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
    let hcolorRegex = try! NSRegularExpression(pattern: #"^<!-- hcolor:(\w+) -->$"#)

    for (index, line) in lines.enumerated() {
      if index > 0 {
        result.append(NSAttributedString(string: "\n"))
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

      // Section divider — dayra-specific card-gap marker
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
        processInlinePatterns(
          in: textStorage, lineRange: lineRange, defaultFont: appearance.bodyFont)
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
    let baseAttrs: [NSAttributedString.Key: Any] = [
      .font: appearance.bodyFont,
      .foregroundColor: NSColor.labelColor,
      .paragraphStyle: bodyParagraphStyle(for: appearance),
    ]

    // Section divider — dayra card-gap marker
    if rawLine == "<!-- section -->" {
      return styledSectionDivider()
    }

    // Horizontal rule — standard markdown visible line
    if rawLine.range(of: #"^-{3,}$"#, options: .regularExpression) != nil {
      return styledHorizontalRule()
    }

    // Heading
    if let match = rawLine.range(of: #"^(#{1,3})\s+"#, options: .regularExpression) {
      let level = rawLine[match].filter { $0 == "#" }.count
      let content = String(rawLine[match.upperBound...])
      let fontSize = headingFontSize(for: level)
      let result = NSMutableAttributedString(
        string: content,
        attributes: [
          .font: appearance.boldBodyFont(ofSize: fontSize),
          .foregroundColor: NSColor.labelColor,
          .markdownHeadingLevel: level,
          .paragraphStyle: bodyParagraphStyle(for: appearance),
        ])
      stripInlineBold(in: result, defaultBoldFont: appearance.boldBodyFont(ofSize: fontSize))
      stripInlineItalic(in: result, defaultItalicFont: appearance.italicBodyFont(ofSize: fontSize))
      stripInlineStrikethrough(in: result)
      stripInlineCode(in: result)
      stripInlineLinks(in: result)
      return result
    }

    // Checkbox checked
    if rawLine.hasPrefix("- [x] ") {
      let content = String(rawLine.dropFirst(6))
      let checkAttr = checkboxAttributedString(checked: true, appearance: appearance)
      let contentAttr = NSMutableAttributedString(string: " \(content)", attributes: baseAttrs)
      stripInlineBold(
        in: contentAttr, defaultBoldFont: appearance.boldBodyFont(ofSize: appearance.bodyFontSize))
      stripInlineItalic(
        in: contentAttr,
        defaultItalicFont: appearance.italicBodyFont(ofSize: appearance.bodyFontSize))
      stripInlineStrikethrough(in: contentAttr)
      stripInlineCode(in: contentAttr)
      stripInlineLinks(in: contentAttr)
      let result = NSMutableAttributedString()
      result.append(checkAttr)
      result.append(contentAttr)
      let fullRange = NSRange(location: 0, length: result.length)
      result.addAttributes(
        [
          .markdownListType: MarkdownListType.checkboxChecked.rawValue,
          .strikethroughStyle: NSUnderlineStyle.single.rawValue,
          .paragraphStyle: listParagraphStyle(for: appearance),
        ], range: fullRange)
      // Remove strikethrough from the checkbox character itself
      result.removeAttribute(.strikethroughStyle, range: NSRange(location: 0, length: 1))
      return result
    }

    // Checkbox unchecked
    if rawLine.hasPrefix("- [ ] ") {
      let content = String(rawLine.dropFirst(6))
      let checkAttr = checkboxAttributedString(checked: false, appearance: appearance)
      let contentAttr = NSMutableAttributedString(string: " \(content)", attributes: baseAttrs)
      stripInlineBold(
        in: contentAttr, defaultBoldFont: appearance.boldBodyFont(ofSize: appearance.bodyFontSize))
      stripInlineItalic(
        in: contentAttr,
        defaultItalicFont: appearance.italicBodyFont(ofSize: appearance.bodyFontSize))
      stripInlineStrikethrough(in: contentAttr)
      stripInlineCode(in: contentAttr)
      stripInlineLinks(in: contentAttr)
      let result = NSMutableAttributedString()
      result.append(checkAttr)
      result.append(contentAttr)
      let fullRange = NSRange(location: 0, length: result.length)
      result.addAttributes(
        [
          .markdownListType: MarkdownListType.checkboxUnchecked.rawValue,
          .paragraphStyle: listParagraphStyle(for: appearance),
        ], range: fullRange)
      return result
    }

    // Bullet list
    if rawLine.range(of: #"^(?:-|•)\s+"#, options: .regularExpression) != nil {
      let prefixMatch = rawLine.range(of: #"^(?:-|•)\s+"#, options: .regularExpression)!
      let content = String(rawLine[prefixMatch.upperBound...])
      let displayText = "\(bulletMarker) \(content)"
      let result = NSMutableAttributedString(string: displayText, attributes: baseAttrs)
      let fullRange = NSRange(location: 0, length: result.length)
      result.addAttributes(
        [
          .markdownListType: MarkdownListType.bullet.rawValue,
          .paragraphStyle: listParagraphStyle(for: appearance),
        ], range: fullRange)
      result.addAttributes(
        [
          .foregroundColor: bulletColor(for: appearance),
          .font: NSFont.systemFont(ofSize: appearance.bulletSize, weight: .bold),
        ], range: NSRange(location: 0, length: 1))
      stripInlineBold(
        in: result, defaultBoldFont: appearance.boldBodyFont(ofSize: appearance.bodyFontSize))
      stripInlineItalic(
        in: result, defaultItalicFont: appearance.italicBodyFont(ofSize: appearance.bodyFontSize))
      stripInlineStrikethrough(in: result)
      stripInlineCode(in: result)
      stripInlineLinks(in: result)
      return result
    }

    // Numbered list
    if rawLine.range(of: #"^\d+\.\s+"#, options: .regularExpression) != nil {
      let result = NSMutableAttributedString(string: rawLine, attributes: baseAttrs)
      let fullRange = NSRange(location: 0, length: result.length)
      result.addAttributes(
        [
          .markdownListType: MarkdownListType.numbered.rawValue,
          .paragraphStyle: listParagraphStyle(for: appearance),
        ], range: fullRange)
      if let numMatch = rawLine.range(of: #"^\d+\."#, options: .regularExpression) {
        let numLength = rawLine.distance(from: numMatch.lowerBound, to: numMatch.upperBound)
        result.addAttribute(
          .foregroundColor, value: NSColor.secondaryLabelColor,
          range: NSRange(location: 0, length: numLength))
      }
      stripInlineBold(
        in: result, defaultBoldFont: appearance.boldBodyFont(ofSize: appearance.bodyFontSize))
      stripInlineItalic(
        in: result, defaultItalicFont: appearance.italicBodyFont(ofSize: appearance.bodyFontSize))
      stripInlineStrikethrough(in: result)
      stripInlineCode(in: result)
      stripInlineLinks(in: result)
      return result
    }

    // Blockquote (single-level only)
    if rawLine.hasPrefix("> ") {
      let content = String(rawLine.dropFirst(2))
      let quoteStyle = blockquoteParagraphStyle(for: appearance)
      let result = NSMutableAttributedString(
        string: content,
        attributes: [
          .font: appearance.bodyFont,
          .foregroundColor: NSColor.secondaryLabelColor,
          .markdownBlockquote: true,
          .paragraphStyle: quoteStyle,
        ])
      stripInlineBold(
        in: result, defaultBoldFont: appearance.boldBodyFont(ofSize: appearance.bodyFontSize))
      stripInlineItalic(
        in: result, defaultItalicFont: appearance.italicBodyFont(ofSize: appearance.bodyFontSize))
      stripInlineStrikethrough(in: result)
      stripInlineCode(in: result)
      stripInlineLinks(in: result)
      return result
    }

    // Plain line — inline formatting only
    let result = NSMutableAttributedString(string: rawLine, attributes: baseAttrs)
    stripInlineBold(
      in: result, defaultBoldFont: appearance.boldBodyFont(ofSize: appearance.bodyFontSize))
    stripInlineItalic(
      in: result, defaultItalicFont: appearance.italicBodyFont(ofSize: appearance.bodyFontSize))
    stripInlineStrikethrough(in: result)
    stripInlineLinks(in: result)
    return result
  }

  // MARK: - Inline Formatting (strips delimiters from attributed string)

  private static func stripInlineBold(
    in attrStr: NSMutableAttributedString, defaultBoldFont: NSFont
  ) {
    let regex = try! NSRegularExpression(pattern: #"\*\*(.+?)\*\*"#)

    // Iterate until no more matches (since positions shift after each replacement)
    while true {
      let string = attrStr.string
      guard
        let match = regex.firstMatch(
          in: string, range: NSRange(location: 0, length: string.utf16.count))
      else { break }

      let innerRange = match.range(at: 1)
      let innerText = (string as NSString).substring(with: innerRange)

      attrStr.replaceCharacters(in: match.range(at: 0), with: innerText)
      let newRange = NSRange(location: match.range(at: 0).location, length: innerText.utf16.count)

      let currentFont =
        attrStr.attribute(.font, at: newRange.location, effectiveRange: nil) as? NSFont
        ?? defaultBoldFont
      let boldFont = NSFontManager.shared.convert(currentFont, toHaveTrait: .boldFontMask)
      attrStr.addAttributes(
        [
          .font: boldFont,
          .markdownBold: true,
        ], range: newRange)
    }
  }

  // Strips single-asterisk italic delimiters without matching double-asterisk bold
  private static func stripInlineItalic(
    in attrStr: NSMutableAttributedString, defaultItalicFont: NSFont
  ) {
    let regex = try! NSRegularExpression(pattern: #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#)

    while true {
      let string = attrStr.string
      guard
        let match = regex.firstMatch(
          in: string, range: NSRange(location: 0, length: string.utf16.count))
      else { break }

      let innerRange = match.range(at: 1)
      let innerText = (string as NSString).substring(with: innerRange)

      attrStr.replaceCharacters(in: match.range(at: 0), with: innerText)
      let newRange = NSRange(location: match.range(at: 0).location, length: innerText.utf16.count)

      let currentFont =
        attrStr.attribute(.font, at: newRange.location, effectiveRange: nil) as? NSFont
        ?? defaultItalicFont
      let italicFont = NSFontManager.shared.convert(currentFont, toHaveTrait: .italicFontMask)
      attrStr.addAttributes(
        [
          .font: italicFont,
          .markdownItalic: true,
        ], range: newRange)
    }
  }

  // Strips ~~text~~ strikethrough delimiters and applies visual strikethrough style
  private static func stripInlineStrikethrough(in attrStr: NSMutableAttributedString) {
    let regex = try! NSRegularExpression(pattern: #"~~(.+?)~~"#)

    while true {
      let string = attrStr.string
      guard
        let match = regex.firstMatch(
          in: string, range: NSRange(location: 0, length: string.utf16.count))
      else { break }

      let innerRange = match.range(at: 1)
      let innerText = (string as NSString).substring(with: innerRange)

      attrStr.replaceCharacters(in: match.range(at: 0), with: innerText)
      let newRange = NSRange(location: match.range(at: 0).location, length: innerText.utf16.count)

      attrStr.addAttributes(
        [
          .strikethroughStyle: NSUnderlineStyle.single.rawValue,
          .markdownStrikethrough: true,
        ], range: newRange)
    }
  }

  private static func stripInlineCode(in attrStr: NSMutableAttributedString) {
    let regex = try! NSRegularExpression(pattern: #"`([^`]+)`"#)

    while true {
      let string = attrStr.string
      guard
        let match = regex.firstMatch(
          in: string, range: NSRange(location: 0, length: string.utf16.count))
      else { break }

      let innerRange = match.range(at: 1)
      let innerText = (string as NSString).substring(with: innerRange)

      attrStr.replaceCharacters(in: match.range(at: 0), with: innerText)
      let newRange = NSRange(location: match.range(at: 0).location, length: innerText.utf16.count)
      attrStr.addAttributes(
        [
          .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
          .backgroundColor: NSColor.quaternaryLabelColor,
          .markdownInlineCode: true,
        ], range: newRange)
    }
  }

  private static func stripInlineLinks(in attrStr: NSMutableAttributedString) {
    let regex = try! NSRegularExpression(pattern: #"\[([^\]]+)\]\(([^\)]+)\)"#)

    while true {
      let string = attrStr.string
      guard
        let match = regex.firstMatch(
          in: string, range: NSRange(location: 0, length: string.utf16.count))
      else { break }

      let textRange = match.range(at: 1)
      let urlRange = match.range(at: 2)
      let linkText = (string as NSString).substring(with: textRange)
      let urlString = (string as NSString).substring(with: urlRange)

      attrStr.replaceCharacters(in: match.range(at: 0), with: linkText)
      let newRange = NSRange(location: match.range(at: 0).location, length: linkText.utf16.count)

      var attrs: [NSAttributedString.Key: Any] = [
        .foregroundColor: NSColor.linkColor,
        .underlineStyle: NSUnderlineStyle.single.rawValue,
        .markdownLinkURL: urlString,
      ]
      if let url = URL(string: urlString) { attrs[.link] = url }
      attrStr.addAttributes(attrs, range: newRange)
    }
  }

  // MARK: - Inline Processing on Existing Text Storage

  private static func processInlinePatterns(
    in textStorage: NSTextStorage, lineRange: NSRange, defaultFont: NSFont
  ) {
    // Bold
    let boldRegex = try! NSRegularExpression(pattern: #"\*\*(.+?)\*\*"#)
    while true {
      let nsString = textStorage.string as NSString
      let currentLineEnd = min(lineRange.location + lineRange.length, nsString.length)
      let currentLineRange = NSRange(
        location: lineRange.location, length: currentLineEnd - lineRange.location)
      let lineText = nsString.substring(with: currentLineRange)
      guard
        let match = boldRegex.firstMatch(
          in: lineText, range: NSRange(location: 0, length: lineText.utf16.count))
      else { break }

      let innerRange = match.range(at: 1)
      let innerText = (lineText as NSString).substring(with: innerRange)
      let absoluteRange = NSRange(
        location: currentLineRange.location + match.range(at: 0).location,
        length: match.range(at: 0).length)

      let currentFont =
        textStorage.attribute(.font, at: absoluteRange.location, effectiveRange: nil) as? NSFont
        ?? defaultFont
      let boldFont = NSFontManager.shared.convert(currentFont, toHaveTrait: .boldFontMask)

      textStorage.beginEditing()
      textStorage.replaceCharacters(in: absoluteRange, with: innerText)
      let newRange = NSRange(location: absoluteRange.location, length: innerText.utf16.count)
      textStorage.addAttributes([.font: boldFont, .markdownBold: true], range: newRange)
      textStorage.endEditing()
    }

    // Italic (single asterisks, avoiding double-asterisk bold)
    let italicRegex = try! NSRegularExpression(pattern: #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#)
    while true {
      let nsStringI = textStorage.string as NSString
      let currentEndI = min(lineRange.location + lineRange.length, nsStringI.length)
      let currentRangeI = NSRange(
        location: lineRange.location, length: currentEndI - lineRange.location)
      let textI = nsStringI.substring(with: currentRangeI)
      guard
        let match = italicRegex.firstMatch(
          in: textI, range: NSRange(location: 0, length: textI.utf16.count))
      else { break }

      let innerRange = match.range(at: 1)
      let innerText = (textI as NSString).substring(with: innerRange)
      let absoluteRange = NSRange(
        location: currentRangeI.location + match.range(at: 0).location,
        length: match.range(at: 0).length)

      let currentFont =
        textStorage.attribute(.font, at: absoluteRange.location, effectiveRange: nil) as? NSFont
        ?? defaultFont
      let italicFont = NSFontManager.shared.convert(currentFont, toHaveTrait: .italicFontMask)

      textStorage.beginEditing()
      textStorage.replaceCharacters(in: absoluteRange, with: innerText)
      let newRange = NSRange(location: absoluteRange.location, length: innerText.utf16.count)
      textStorage.addAttributes([.font: italicFont, .markdownItalic: true], range: newRange)
      textStorage.endEditing()
    }

    // Strikethrough
    let strikeRegex = try! NSRegularExpression(pattern: #"~~(.+?)~~"#)
    while true {
      let nsStringS = textStorage.string as NSString
      let currentEndS = min(lineRange.location + lineRange.length, nsStringS.length)
      let currentRangeS = NSRange(
        location: lineRange.location, length: currentEndS - lineRange.location)
      let textS = nsStringS.substring(with: currentRangeS)
      guard
        let match = strikeRegex.firstMatch(
          in: textS, range: NSRange(location: 0, length: textS.utf16.count))
      else { break }

      let innerRange = match.range(at: 1)
      let innerText = (textS as NSString).substring(with: innerRange)
      let absoluteRange = NSRange(
        location: currentRangeS.location + match.range(at: 0).location,
        length: match.range(at: 0).length)

      textStorage.beginEditing()
      textStorage.replaceCharacters(in: absoluteRange, with: innerText)
      let newRange = NSRange(location: absoluteRange.location, length: innerText.utf16.count)
      textStorage.addAttributes(
        [
          .strikethroughStyle: NSUnderlineStyle.single.rawValue,
          .markdownStrikethrough: true,
        ], range: newRange)
      textStorage.endEditing()
    }

    // Inline code
    let codeRegex = try! NSRegularExpression(pattern: #"`([^`]+)`"#)
    while true {
      let nsString2 = textStorage.string as NSString
      let currentEnd2 = min(lineRange.location + lineRange.length, nsString2.length)
      let currentRange2 = NSRange(
        location: lineRange.location, length: currentEnd2 - lineRange.location)
      let text2 = nsString2.substring(with: currentRange2)
      guard
        let match = codeRegex.firstMatch(
          in: text2, range: NSRange(location: 0, length: text2.utf16.count))
      else { break }

      let innerRange = match.range(at: 1)
      let innerText = (text2 as NSString).substring(with: innerRange)
      let absoluteRange = NSRange(
        location: currentRange2.location + match.range(at: 0).location,
        length: match.range(at: 0).length)

      textStorage.beginEditing()
      textStorage.replaceCharacters(in: absoluteRange, with: innerText)
      let newRange = NSRange(location: absoluteRange.location, length: innerText.utf16.count)
      textStorage.addAttributes(
        [
          .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
          .backgroundColor: NSColor.quaternaryLabelColor,
          .markdownInlineCode: true,
        ], range: newRange)
      textStorage.endEditing()
    }

    // Links
    let linkRegex = try! NSRegularExpression(pattern: #"\[([^\]]+)\]\(([^\)]+)\)"#)
    while true {
      let nsString = textStorage.string as NSString
      let currentLineEnd = min(lineRange.location + lineRange.length, nsString.length)
      let currentLineRange = NSRange(
        location: lineRange.location, length: currentLineEnd - lineRange.location)
      let lineText = nsString.substring(with: currentLineRange)
      guard
        let match = linkRegex.firstMatch(
          in: lineText, range: NSRange(location: 0, length: lineText.utf16.count))
      else { break }

      let textRange = match.range(at: 1)
      let urlRange = match.range(at: 2)
      let linkText = (lineText as NSString).substring(with: textRange)
      let urlString = (lineText as NSString).substring(with: urlRange)
      let absoluteRange = NSRange(
        location: currentLineRange.location + match.range(at: 0).location,
        length: match.range(at: 0).length)

      textStorage.beginEditing()
      textStorage.replaceCharacters(in: absoluteRange, with: linkText)
      let newRange = NSRange(location: absoluteRange.location, length: linkText.utf16.count)
      var attrs: [NSAttributedString.Key: Any] = [
        .foregroundColor: NSColor.linkColor,
        .underlineStyle: NSUnderlineStyle.single.rawValue,
        .markdownLinkURL: urlString,
      ]
      if let url = URL(string: urlString) { attrs[.link] = url }
      textStorage.addAttributes(attrs, range: newRange)
      textStorage.endEditing()
    }
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

    // Section divider — dayra-specific card-gap marker
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
      switch listType {
      case .bullet:
        prefix = "- "
        contentStart = lineText.hasPrefix("\(bulletMarker) ") ? 2 : 0
      case .checkboxUnchecked:
        prefix = "- [ ] "
        contentStart = lineText.hasPrefix("\(uncheckedMarker) ") ? 2 : 0
      case .checkboxChecked:
        prefix = "- [x] "
        contentStart = lineText.hasPrefix("\(checkedMarker) ") ? 2 : 0
      case .numbered:
        // Number text is already in the display, pass through
        return reconstructInlineMarkdown(
          from: attributedString,
          range: textRange
        )
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
    // Invisible marker — the visual split comes from DayraTextView drawing
    // separate card backgrounds for each section. This character occupies
    // a single line that becomes the gap between cards.
    let gapStyle = NSMutableParagraphStyle()
    gapStyle.paragraphSpacingBefore = 16
    gapStyle.paragraphSpacing = 16
    gapStyle.maximumLineHeight = 2

    return NSAttributedString(
      string: " ",
      attributes: [
        .font: NSFont.systemFont(ofSize: 1),
        .foregroundColor: NSColor.clear,
        .paragraphStyle: gapStyle,
        .markdownSectionDivider: true,
      ])
  }

  // Visible thin line for standard markdown horizontal rules (e.g. imported `---`).
  // The actual line is drawn by DayraTextView; this marker reserves the vertical space.
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

  private static func headingFontSize(for level: Int) -> CGFloat {
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
