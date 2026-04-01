//
//  MarkdownStyler.swift
//  dayra
//
//  Created by Steve Walsh on 01/04/2026.
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
  static let markdownBlockType = NSAttributedString.Key("dayra.blockType")
  static let markdownInlineCode = NSAttributedString.Key("dayra.inlineCode")
}

enum MarkdownListType: String {
  case bullet
  case numbered
  case checkboxUnchecked
  case checkboxChecked
}

// MARK: - Styler

enum MarkdownStyler {

  static let bulletMarker = "●"
  static let uncheckedMarker = "☐"
  static let checkedMarker = "☑"

  private static let defaultSize: CGFloat = 15

  // MARK: - Raw Markdown → Display Attributed String

  static func formatForDisplay(_ rawMarkdown: String, defaultFont: NSFont) -> NSAttributedString {
    let result = NSMutableAttributedString()
    let lines = rawMarkdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var insideCodeBlock = false

    for (index, line) in lines.enumerated() {
      if index > 0 {
        result.append(NSAttributedString(string: "\n"))
      }

      if line.hasPrefix("```") {
        insideCodeBlock.toggle()
        result.append(styledCodeFenceLine(line))
        continue
      }

      if insideCodeBlock {
        result.append(styledCodeBlockLine(line))
        continue
      }

      if line.range(of: #"^<!--\s*block:(\w+)\s*-->$"#, options: .regularExpression) != nil {
        result.append(styledBlockDividerLine(line))
        continue
      }

      result.append(buildDisplayLine(line, defaultFont: defaultFont))
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
      stripInlineBold(in: result, defaultBoldFont: NSFont.systemFont(ofSize: fontSize, weight: .bold))
      stripInlineCode(in: result)
      stripInlineLinks(in: result)
      return result
    }

    // Checkbox checked
    if rawLine.hasPrefix("- [x] ") {
      let content = String(rawLine.dropFirst(6))
      let displayText = "\(checkedMarker) \(content)"
      let result = NSMutableAttributedString(string: displayText, attributes: baseAttrs)
      let fullRange = NSRange(location: 0, length: result.length)
      result.addAttributes([
        .markdownListType: MarkdownListType.checkboxChecked.rawValue,
        .strikethroughStyle: NSUnderlineStyle.single.rawValue,
        .paragraphStyle: listParagraphStyle(),
      ], range: fullRange)
      result.addAttributes([
        .foregroundColor: NSColor.systemGreen,
        .font: NSFont.systemFont(ofSize: defaultSize, weight: .medium),
      ], range: NSRange(location: 0, length: 1))
      stripInlineBold(in: result, defaultBoldFont: NSFont.boldSystemFont(ofSize: defaultSize))
      stripInlineCode(in: result)
      stripInlineLinks(in: result)
      return result
    }

    // Checkbox unchecked
    if rawLine.hasPrefix("- [ ] ") {
      let content = String(rawLine.dropFirst(6))
      let displayText = "\(uncheckedMarker) \(content)"
      let result = NSMutableAttributedString(string: displayText, attributes: baseAttrs)
      let fullRange = NSRange(location: 0, length: result.length)
      result.addAttributes([
        .markdownListType: MarkdownListType.checkboxUnchecked.rawValue,
        .paragraphStyle: listParagraphStyle(),
      ], range: fullRange)
      result.addAttributes([
        .foregroundColor: NSColor.secondaryLabelColor,
        .font: NSFont.systemFont(ofSize: defaultSize, weight: .medium),
      ], range: NSRange(location: 0, length: 1))
      stripInlineBold(in: result, defaultBoldFont: NSFont.boldSystemFont(ofSize: defaultSize))
      stripInlineCode(in: result)
      stripInlineLinks(in: result)
      return result
    }

    // Bullet list
    if rawLine.range(of: #"^-\s+"#, options: .regularExpression) != nil {
      let prefixMatch = rawLine.range(of: #"^-\s+"#, options: .regularExpression)!
      let content = String(rawLine[prefixMatch.upperBound...])
      let displayText = "\(bulletMarker) \(content)"
      let result = NSMutableAttributedString(string: displayText, attributes: baseAttrs)
      let fullRange = NSRange(location: 0, length: result.length)
      result.addAttributes([
        .markdownListType: MarkdownListType.bullet.rawValue,
        .paragraphStyle: listParagraphStyle(),
      ], range: fullRange)
      result.addAttributes([
        .foregroundColor: NSColor.controlAccentColor,
        .font: NSFont.systemFont(ofSize: defaultSize - 2, weight: .regular),
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
      result.addAttributes([
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
      attrStr.addAttributes([
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
      attrStr.addAttributes([
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
      textStorage.addAttributes([
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

    // Block divider — pass through (raw comment text is preserved)
    if attrs[.markdownBlockType] != nil {
      return lineText
    }

    // Determine line prefix from attributes
    var prefix = ""
    var contentStart = 0

    if let level = attrs[.markdownHeadingLevel] as? Int {
      prefix = String(repeating: "#", count: level) + " "
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

  private static func styledBlockDividerLine(_ line: String) -> NSAttributedString {
    let regex = try! NSRegularExpression(pattern: #"^<!--\s*block:(\w+)\s*-->$"#)
    let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: line.utf16.count))
    let blockType = match.map { (line as NSString).substring(with: $0.range(at: 1)) } ?? "other"

    let centeredParagraph = NSMutableParagraphStyle()
    centeredParagraph.alignment = .center
    centeredParagraph.paragraphSpacingBefore = 12
    centeredParagraph.paragraphSpacing = 8

    let smallCapsFont = NSFont.systemFont(ofSize: 11, weight: .medium)
    let descriptor = smallCapsFont.fontDescriptor.addingAttributes([
      .featureSettings: [
        [
          NSFontDescriptor.FeatureKey.typeIdentifier: kUpperCaseType,
          NSFontDescriptor.FeatureKey.selectorIdentifier: kUpperCaseSmallCapsSelector,
        ]
      ]
    ])
    let resolvedFont = NSFont(descriptor: descriptor, size: 0) ?? smallCapsFont

    return NSAttributedString(
      string: line,
      attributes: [
        .font: resolvedFont,
        .foregroundColor: NSColor.secondaryLabelColor,
        .paragraphStyle: centeredParagraph,
        .markdownBlockType: blockType,
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
