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
  static let markdownLinkURL = NSAttributedString.Key("dayra.linkURL")
  static let markdownCodeFence = NSAttributedString.Key("dayra.codeFence")
  static let markdownCodeBlock = NSAttributedString.Key("dayra.codeBlock")
  static let markdownSectionDivider = NSAttributedString.Key("dayra.sectionDivider")
  static let markdownInlineCode = NSAttributedString.Key("dayra.inlineCode")
  static let markdownHeadingColor = NSAttributedString.Key("dayra.headingColor")
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

  private static let defaultSize: CGFloat = 15

  // MARK: - Accent Colors (single source of truth for future settings)

  static var accentColor: NSColor {
    NSColor.systemPink
  }

  static var checkboxCheckedColor: NSColor {
    NSColor.systemPink
  }

  static var checkboxUncheckedColor: NSColor {
    accentColor
  }

  static var bulletColor: NSColor {
    accentColor
  }

  // MARK: - Heading Color Presets

  static let headingColorPresets: [(name: String, color: NSColor)] = [
    ("pink", .systemPink),
    ("cyan", .systemCyan),
    ("purple", .systemPurple),
    ("orange", .systemOrange),
    ("mint", .systemMint),
  ]

  static func headingColor(named name: String) -> NSColor? {
    headingColorPresets.first(where: { $0.name == name })?.color
  }

  static func headingColorName(for color: NSColor) -> String? {
    headingColorPresets.first(where: { $0.color == color })?.name
  }

  // MARK: - Checkbox Attachments

  static func checkboxAttachment(checked: Bool) -> NSTextAttachment {
    let symbolName = checked ? "checkmark.circle.fill" : "circle"
    let color = checked ? checkboxCheckedColor : checkboxUncheckedColor
    let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
      .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
    let attachment = NSTextAttachment()
    attachment.image = NSImage(
      systemSymbolName: symbolName, accessibilityDescription: checked ? "Done" : "To do")?
      .withSymbolConfiguration(config)
    return attachment
  }

  static func checkboxAttributedString(checked: Bool) -> NSAttributedString {
    NSAttributedString(attachment: checkboxAttachment(checked: checked))
  }

  // MARK: - Raw Markdown → Display Attributed String

  static func formatForDisplay(_ rawMarkdown: String, defaultFont: NSFont) -> NSAttributedString {
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

      if line.range(of: #"^-{3,}$"#, options: .regularExpression) != nil {
        // Flush pending color as-is if next line is a divider
        if let colorName = pendingHeadingColorName {
          result.append(NSAttributedString(string: "<!-- hcolor:\(colorName) -->\n"))
          pendingHeadingColor = nil
          pendingHeadingColorName = nil
        }
        result.append(styledSectionDivider())
        continue
      }

      let displayLine = buildDisplayLine(line, defaultFont: defaultFont)

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
    in textStorage: NSTextStorage, lineRange: NSRange, defaultFont: NSFont
  ) -> MarkdownListType? {
    let nsString = textStorage.string as NSString
    let lineText = nsString.substring(with: lineRange)

    // Check if line already has formatting attributes (was formatted before)
    if lineRange.length > 0 {
      let attrs = textStorage.attributes(at: lineRange.location, effectiveRange: nil)
      // Section dividers are fully styled — no further processing needed
      if attrs[.markdownSectionDivider] as? Bool == true {
        return nil
      }

      let alreadyFormatted =
        attrs[.markdownHeadingLevel] != nil || attrs[.markdownListType] != nil

      if alreadyFormatted {
        // Only process inline formatting on existing formatted lines
        processInlinePatterns(in: textStorage, lineRange: lineRange, defaultFont: defaultFont)
        if let rawType = attrs[.markdownListType] as? String {
          return MarkdownListType(rawValue: rawType)
        }
        return nil
      }
    }

    // Build formatted version of this raw markdown line
    let displayLine = buildDisplayLine(lineText, defaultFont: defaultFont)

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

  private static func buildDisplayLine(_ rawLine: String, defaultFont: NSFont)
    -> NSAttributedString
  {
    let baseAttrs: [NSAttributedString.Key: Any] = [
      .font: defaultFont,
      .foregroundColor: NSColor.labelColor,
    ]

    // Section divider
    if rawLine.range(of: #"^-{3,}$"#, options: .regularExpression) != nil {
      return styledSectionDivider()
    }

    // Heading
    if let match = rawLine.range(of: #"^(#{1,3})\s+"#, options: .regularExpression) {
      let level = rawLine[match].filter { $0 == "#" }.count
      let content = String(rawLine[match.upperBound...])
      let fontSize: CGFloat = level == 1 ? 22 : level == 2 ? 19 : 17
      let result = NSMutableAttributedString(
        string: content,
        attributes: [
          .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
          .foregroundColor: NSColor.labelColor,
          .markdownHeadingLevel: level,
        ])
      stripInlineBold(
        in: result, defaultBoldFont: NSFont.systemFont(ofSize: fontSize, weight: .bold))
      stripInlineCode(in: result)
      stripInlineLinks(in: result)
      return result
    }

    // Checkbox checked
    if rawLine.hasPrefix("- [x] ") {
      let content = String(rawLine.dropFirst(6))
      let checkAttr = checkboxAttributedString(checked: true)
      let contentAttr = NSMutableAttributedString(string: " \(content)", attributes: baseAttrs)
      stripInlineBold(in: contentAttr, defaultBoldFont: NSFont.boldSystemFont(ofSize: defaultSize))
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
          .paragraphStyle: listParagraphStyle(),
        ], range: fullRange)
      // Remove strikethrough from the checkbox character itself
      result.removeAttribute(.strikethroughStyle, range: NSRange(location: 0, length: 1))
      return result
    }

    // Checkbox unchecked
    if rawLine.hasPrefix("- [ ] ") {
      let content = String(rawLine.dropFirst(6))
      let checkAttr = checkboxAttributedString(checked: false)
      let contentAttr = NSMutableAttributedString(string: " \(content)", attributes: baseAttrs)
      stripInlineBold(in: contentAttr, defaultBoldFont: NSFont.boldSystemFont(ofSize: defaultSize))
      stripInlineCode(in: contentAttr)
      stripInlineLinks(in: contentAttr)
      let result = NSMutableAttributedString()
      result.append(checkAttr)
      result.append(contentAttr)
      let fullRange = NSRange(location: 0, length: result.length)
      result.addAttributes(
        [
          .markdownListType: MarkdownListType.checkboxUnchecked.rawValue,
          .paragraphStyle: listParagraphStyle(),
        ], range: fullRange)
      return result
    }

    // Bullet list
    if rawLine.range(of: #"^-\s+"#, options: .regularExpression) != nil {
      let prefixMatch = rawLine.range(of: #"^-\s+"#, options: .regularExpression)!
      let content = String(rawLine[prefixMatch.upperBound...])
      let displayText = "\(bulletMarker) \(content)"
      let result = NSMutableAttributedString(string: displayText, attributes: baseAttrs)
      let fullRange = NSRange(location: 0, length: result.length)
      result.addAttributes(
        [
          .markdownListType: MarkdownListType.bullet.rawValue,
          .paragraphStyle: listParagraphStyle(),
        ], range: fullRange)
      result.addAttributes(
        [
          .foregroundColor: bulletColor,
          .font: NSFont.systemFont(ofSize: 11, weight: .bold),
        ], range: NSRange(location: 0, length: 1))
      stripInlineBold(in: result, defaultBoldFont: NSFont.boldSystemFont(ofSize: defaultSize))
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
          .paragraphStyle: listParagraphStyle(),
        ], range: fullRange)
      if let numMatch = rawLine.range(of: #"^\d+\."#, options: .regularExpression) {
        let numLength = rawLine.distance(from: numMatch.lowerBound, to: numMatch.upperBound)
        result.addAttribute(
          .foregroundColor, value: NSColor.secondaryLabelColor,
          range: NSRange(location: 0, length: numLength))
      }
      stripInlineBold(in: result, defaultBoldFont: NSFont.boldSystemFont(ofSize: defaultSize))
      stripInlineCode(in: result)
      stripInlineLinks(in: result)
      return result
    }

    // Plain line — inline formatting only
    let result = NSMutableAttributedString(string: rawLine, attributes: baseAttrs)
    stripInlineBold(in: result, defaultBoldFont: NSFont.boldSystemFont(ofSize: defaultSize))
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

    // Section divider — reconstruct as standard markdown horizontal rule
    if attrs[.markdownSectionDivider] as? Bool == true {
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
      let isCode = attrs[.markdownInlineCode] as? Bool == true
      let linkURL = attrs[.markdownLinkURL] as? String

      if isCode {
        result += "`\(text)`"
      } else if isBold, let url = linkURL {
        result += "**[\(text)](\(url))**"
      } else if isBold {
        result += "**\(text)**"
      } else if let url = linkURL {
        result += "[\(text)](\(url))"
      } else {
        result += text
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
    let dividerText = String(repeating: "\u{2500}", count: 40)

    let centeredParagraph = NSMutableParagraphStyle()
    centeredParagraph.alignment = .center
    centeredParagraph.paragraphSpacingBefore = 16
    centeredParagraph.paragraphSpacing = 12

    return NSAttributedString(
      string: dividerText,
      attributes: [
        .font: NSFont.systemFont(ofSize: 11),
        .foregroundColor: MarkdownStyler.accentColor,
        .paragraphStyle: centeredParagraph,
        .markdownSectionDivider: true,
      ])
  }

  // MARK: - Helpers

  private static func listParagraphStyle() -> NSMutableParagraphStyle {
    let style = NSMutableParagraphStyle()
    style.firstLineHeadIndent = 8
    style.headIndent = 28
    style.paragraphSpacing = 2
    return style
  }
}
