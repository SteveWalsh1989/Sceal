//
//  MarkdownStyler+Display.swift
//

// Builds display-ready attributed strings from raw markdown lines.

import AppKit

// MARK: - Display Line Building & Inline Formatting

extension MarkdownStyler {

  // MARK: - Build Display Line (single raw markdown line → attributed string)

  // Converts a single raw markdown line into a styled NSAttributedString.
  static func buildDisplayLine(_ rawLine: String, appearance: NoteAppearanceSettings)
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
      return styledSectionDivider(appearance: appearance)
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
  static func applyInlineFormatting(
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
          .font: NSFont.monospacedSystemFont(ofSize: defaultFont.pointSize, weight: .regular),
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
  static func applyInlineFormatting(
    in attrStr: NSMutableAttributedString, defaultFont: NSFont
  ) {
    applyInlineFormatting(
      in: attrStr, range: NSRange(location: 0, length: attrStr.length), defaultFont: defaultFont)
  }

  // MARK: - Styled Special Lines (kept as raw text, just styled)

  // Styles a code fence delimiter (```) as dimmed monospace text.
  static func styledCodeFenceLine(_ line: String) -> NSAttributedString {
    NSAttributedString(
      string: line,
      attributes: [
        .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
        .foregroundColor: NSColor.tertiaryLabelColor,
        .markdownCodeFence: true,
      ])
  }

  // Styles a code block line with monospace font and background.
  static func styledCodeBlockLine(_ line: String) -> NSAttributedString {
    NSAttributedString(
      string: line,
      attributes: [
        .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
        .backgroundColor: NSColor.quaternaryLabelColor,
        .foregroundColor: NSColor.labelColor,
        .markdownCodeBlock: true,
      ])
  }

  // Creates an invisible marker that ScealTextView renders as a card gap.
  static func styledSectionDivider(
    appearance: NoteAppearanceSettings = .default,
    headingColorName: String? = nil,
    bulletColorName: String? = nil,
    useSectionColor: Bool? = nil
  ) -> NSAttributedString {
    // Invisible marker — the visual split comes from ScealTextView drawing
    // separate card backgrounds for each section. This character occupies
    // a single line that becomes the gap between cards.
    let gapStyle = NSMutableParagraphStyle()
    gapStyle.paragraphSpacingBefore =
      sectionDividerSpacingBefore * appearance.sectionDividerGapScale
    gapStyle.paragraphSpacing = sectionDividerSpacingAfter * appearance.sectionDividerGapScale
    gapStyle.minimumLineHeight = sectionDividerLineHeight
    gapStyle.maximumLineHeight = sectionDividerLineHeight

    var attrs: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 1),
      .foregroundColor: NSColor.clear,
      .paragraphStyle: gapStyle,
      .markdownSectionDivider: true,
    ]
    if let name = headingColorName {
      attrs[.markdownSectionHeadingColor] = name
    }
    if let name = bulletColorName {
      attrs[.markdownSectionBulletColor] = name
    }
    if let flag = useSectionColor {
      attrs[.markdownSectionUseSectionColor] = flag
    }

    return NSAttributedString(string: " ", attributes: attrs)
  }

  // Exposes the final divider display form for editor insertions that must avoid raw markdown text.
  static func sectionDividerDisplayString(appearance: NoteAppearanceSettings = .default)
    -> NSAttributedString
  {
    styledSectionDivider(appearance: appearance)
  }

  // Visible thin line for standard markdown horizontal rules (e.g. imported `---`).
  // The actual line is drawn by ScealTextView; this marker reserves the vertical space.
  static func styledHorizontalRule() -> NSAttributedString {
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

  // MARK: - Section Color Propagation

  // Applies section-level color defaults to a display line. Returns a modified
  // copy when changes were made, or nil when the line is unaffected.
  static func applySectionColors(
    to displayLine: NSAttributedString,
    headingColorName: String?,
    bulletColorName: String?,
    useSectionColor: Bool,
    appearance: NoteAppearanceSettings
  ) -> NSAttributedString? {
    guard displayLine.length > 0 else { return nil }
    let attrs = displayLine.attributes(at: 0, effectiveRange: nil)

    // Headings without an explicit hcolor inherit the section heading color.
    if attrs[.markdownHeadingLevel] != nil,
      attrs[.markdownHeadingColor] == nil,
      let colorName = headingColorName,
      let color = headingColor(named: colorName)
    {
      let mutable = NSMutableAttributedString(attributedString: displayLine)
      let fullRange = NSRange(location: 0, length: mutable.length)
      mutable.addAttribute(.foregroundColor, value: color, range: fullRange)
      // Intentionally NOT setting .markdownHeadingColor — absence means "inherited from section".
      return mutable
    }

    // Bullets and checkboxes inherit section color when useSectionColor is on.
    guard useSectionColor,
      let rawType = attrs[.markdownListType] as? String,
      let listType = MarkdownListType(rawValue: rawType)
    else { return nil }

    let sectionColor: NSColor? = {
      if let name = bulletColorName { return headingColor(named: name) }
      if let name = headingColorName { return headingColor(named: name) }
      return nil
    }()
    guard let color = sectionColor else { return nil }

    switch listType {
    case .bullet:
      let mutable = NSMutableAttributedString(attributedString: displayLine)
      mutable.addAttributes(
        [
          .foregroundColor: color,
          .font: NSFont.systemFont(ofSize: appearance.bulletSize, weight: .bold),
        ], range: NSRange(location: 0, length: 1))
      return mutable

    case .checkboxChecked, .checkboxUnchecked:
      let checked = listType == .checkboxChecked
      let newAttachment = NSAttributedString(
        attachment: checkboxAttachment(checked: checked, color: color))
      let mutable = NSMutableAttributedString(attributedString: displayLine)
      mutable.replaceCharacters(in: NSRange(location: 0, length: 1), with: newAttachment)
      return mutable

    case .numbered:
      return nil
    }
  }

  // MARK: - Helpers

  // Extracts an optional capture group from a regex match, returning nil when unmatched.
  static func extractGroup(
    _ match: NSTextCheckingResult, index: Int, in line: String
  ) -> String? {
    let range = match.range(at: index)
    guard range.location != NSNotFound, let swiftRange = Range(range, in: line) else {
      return nil
    }
    return String(line[swiftRange])
  }

  // Returns the display font size for heading levels 1-3.
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
