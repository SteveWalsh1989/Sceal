//
//  MarkdownStyler.swift
//  dayra
//
//  Created by Steve Walsh on 01/04/2026.
//

import AppKit

enum MarkdownStyler {

  // MARK: - Public API

  static func applyFormatting(to textStorage: NSTextStorage, defaultFont: NSFont) {
    let fullString = textStorage.string as NSString
    let fullRange = NSRange(location: 0, length: fullString.length)

    textStorage.beginEditing()

    // Reset all attributes to defaults
    let defaultParagraph = NSMutableParagraphStyle()
    textStorage.setAttributes([
      .font: defaultFont,
      .foregroundColor: NSColor.labelColor,
      .paragraphStyle: defaultParagraph,
    ], range: fullRange)

    // Track which line ranges are inside fenced code blocks (used by both passes)
    var codeBlockLineRanges: Set<Int> = []
    var insideCodeBlock = false

    // MARK: First pass — line-level patterns

    let lines = splitLines(fullString)

    for (lineIndex, lineRange) in lines.enumerated() {
      let line = fullString.substring(with: lineRange)

      // Fenced code block toggle
      if line.hasPrefix("```") {
        applyFenceMarker(textStorage, range: lineRange)
        insideCodeBlock.toggle()
        continue
      }

      if insideCodeBlock {
        codeBlockLineRanges.insert(lineIndex)
        applyCodeBlockLine(textStorage, range: lineRange)
        continue
      }

      // Block dividers: <!-- block:type -->
      if applyBlockDivider(textStorage, line: line, range: lineRange) {
        continue
      }

      // Headings
      if applyHeading(textStorage, line: line, range: lineRange, fullString: fullString) {
        continue
      }

      // Checkboxes (checked) — must test before unchecked
      if applyCheckedCheckbox(textStorage, line: line, range: lineRange, fullString: fullString) {
        continue
      }

      // Checkboxes (unchecked)
      if applyUncheckedCheckbox(textStorage, line: line, range: lineRange, fullString: fullString) {
        continue
      }

      // Bullet lists (excluding checkboxes, already handled above)
      if applyBulletList(textStorage, line: line, range: lineRange, fullString: fullString) {
        continue
      }

      // Numbered lists
      if applyNumberedList(textStorage, line: line, range: lineRange, fullString: fullString) {
        continue
      }
    }

    // MARK: Second pass — inline patterns (skip code block lines)

    for (lineIndex, lineRange) in lines.enumerated() {
      if codeBlockLineRanges.contains(lineIndex) { continue }

      let line = fullString.substring(with: lineRange)
      if line.hasPrefix("```") { continue }

      applyBold(textStorage, searchRange: lineRange, fullString: fullString)
      applyLinks(textStorage, searchRange: lineRange, fullString: fullString)
    }

    textStorage.endEditing()
  }

  // MARK: - Line Splitting

  private static func splitLines(_ string: NSString) -> [NSRange] {
    var ranges: [NSRange] = []
    var start = 0
    let length = string.length

    while start < length {
      let lineEnd = NSMaxRange(string.lineRange(for: NSRange(location: start, length: 0)))
      let lineLength = lineEnd - start

      // Trim trailing newline from the range used for matching
      var trimmedLength = lineLength
      if trimmedLength > 0 && string.character(at: start + trimmedLength - 1) == UInt16(0x0A) {
        trimmedLength -= 1
      }

      ranges.append(NSRange(location: start, length: trimmedLength))
      start = lineEnd
    }

    return ranges
  }

  // MARK: - Fenced Code Blocks

  private static func applyFenceMarker(_ textStorage: NSTextStorage, range: NSRange) {
    textStorage.addAttributes([
      .foregroundColor: NSColor.tertiaryLabelColor,
      .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
    ], range: range)
  }

  private static func applyCodeBlockLine(_ textStorage: NSTextStorage, range: NSRange) {
    textStorage.addAttributes([
      .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
      .backgroundColor: NSColor.quaternaryLabelColor,
    ], range: range)
  }

  // MARK: - Block Dividers

  private static func applyBlockDivider(
    _ textStorage: NSTextStorage, line: String, range: NSRange
  ) -> Bool {
    guard let regex = try? NSRegularExpression(pattern: #"^<!--\s*block:(\w+)\s*-->$"#),
      let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: line.utf16.count))
    else {
      return false
    }

    let delimiterColor = NSColor.tertiaryLabelColor.withAlphaComponent(0.5)

    // Style the opening <!--
    let openRange = NSRange(location: range.location, length: 4)
    textStorage.addAttribute(.foregroundColor, value: delimiterColor, range: openRange)

    // Style the closing -->
    let closeStart = range.location + range.length - 3
    let closeRange = NSRange(location: closeStart, length: 3)
    textStorage.addAttribute(.foregroundColor, value: delimiterColor, range: closeRange)

    // Style the block type label
    let labelNSRange = match.range(at: 1)
    let labelRange = NSRange(
      location: range.location + labelNSRange.location, length: labelNSRange.length)

    let centeredParagraph = NSMutableParagraphStyle()
    centeredParagraph.alignment = .center
    centeredParagraph.paragraphSpacingBefore = 12
    centeredParagraph.paragraphSpacing = 8

    let smallCapsFont = NSFont.systemFont(ofSize: 11, weight: .medium)
    let smallCapsDescriptor = smallCapsFont.fontDescriptor.addingAttributes([
      .featureSettings: [
        [
          NSFontDescriptor.FeatureKey.typeIdentifier: kUpperCaseType,
          NSFontDescriptor.FeatureKey.selectorIdentifier: kUpperCaseSmallCapsSelector,
        ]
      ]
    ])
    let resolvedSmallCaps = NSFont(descriptor: smallCapsDescriptor, size: 0) ?? smallCapsFont

    textStorage.addAttributes([
      .foregroundColor: NSColor.secondaryLabelColor,
      .font: resolvedSmallCaps,
    ], range: labelRange)

    // Apply centered paragraph to entire line
    textStorage.addAttribute(.paragraphStyle, value: centeredParagraph, range: range)

    // The portions between <!-- and label, and between label and --> are also delimiters
    let betweenOpenAndLabel = NSRange(
      location: openRange.location + openRange.length,
      length: labelRange.location - (openRange.location + openRange.length))
    if betweenOpenAndLabel.length > 0 {
      textStorage.addAttribute(.foregroundColor, value: delimiterColor, range: betweenOpenAndLabel)
    }

    let betweenLabelAndClose = NSRange(
      location: labelRange.location + labelRange.length,
      length: closeRange.location - (labelRange.location + labelRange.length))
    if betweenLabelAndClose.length > 0 {
      textStorage.addAttribute(.foregroundColor, value: delimiterColor, range: betweenLabelAndClose)
    }

    return true
  }

  // MARK: - Headings

  private static func applyHeading(
    _ textStorage: NSTextStorage, line: String, range: NSRange, fullString: NSString
  ) -> Bool {
    guard let regex = try? NSRegularExpression(pattern: #"^(#{1,3})\s+(.+)$"#),
      let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: line.utf16.count))
    else {
      return false
    }

    let hashRange = match.range(at: 1)
    let level = hashRange.length
    let fontSize: CGFloat = level == 1 ? 22 : level == 2 ? 19 : 17

    // Style the # characters
    let hashAbsoluteRange = NSRange(location: range.location + hashRange.location, length: hashRange.length)
    textStorage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: hashAbsoluteRange)

    // Style the heading text (includes the space after #)
    let textNSRange = match.range(at: 2)
    let textAbsoluteRange = NSRange(
      location: range.location + textNSRange.location, length: textNSRange.length)
    textStorage.addAttribute(
      .font, value: NSFont.systemFont(ofSize: fontSize, weight: .bold), range: textAbsoluteRange)

    return true
  }

  // MARK: - Checkboxes

  private static func applyCheckedCheckbox(
    _ textStorage: NSTextStorage, line: String, range: NSRange, fullString: NSString
  ) -> Bool {
    guard let regex = try? NSRegularExpression(pattern: #"^(-\s+\[x\]\s+)(.+)$"#),
      let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: line.utf16.count))
    else {
      return false
    }

    let markerRange = match.range(at: 1)
    let textRange = match.range(at: 2)

    let markerAbsolute = NSRange(
      location: range.location + markerRange.location, length: markerRange.length)
    let textAbsolute = NSRange(
      location: range.location + textRange.location, length: textRange.length)

    textStorage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: markerAbsolute)
    textStorage.addAttribute(
      .strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: textAbsolute)

    return true
  }

  private static func applyUncheckedCheckbox(
    _ textStorage: NSTextStorage, line: String, range: NSRange, fullString: NSString
  ) -> Bool {
    guard let regex = try? NSRegularExpression(pattern: #"^(-\s+\[\s\]\s+)(.+)$"#),
      let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: line.utf16.count))
    else {
      return false
    }

    let markerRange = match.range(at: 1)
    let markerAbsolute = NSRange(
      location: range.location + markerRange.location, length: markerRange.length)

    textStorage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: markerAbsolute)

    return true
  }

  // MARK: - Bullet Lists

  private static func applyBulletList(
    _ textStorage: NSTextStorage, line: String, range: NSRange, fullString: NSString
  ) -> Bool {
    guard let regex = try? NSRegularExpression(pattern: #"^(-)\s+(.+)$"#),
      let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: line.utf16.count))
    else {
      return false
    }

    let dashRange = match.range(at: 1)
    let dashAbsolute = NSRange(
      location: range.location + dashRange.location, length: dashRange.length)

    textStorage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: dashAbsolute)

    let listParagraph = NSMutableParagraphStyle()
    listParagraph.firstLineHeadIndent = 0
    listParagraph.headIndent = 20
    textStorage.addAttribute(.paragraphStyle, value: listParagraph, range: range)

    return true
  }

  // MARK: - Numbered Lists

  private static func applyNumberedList(
    _ textStorage: NSTextStorage, line: String, range: NSRange, fullString: NSString
  ) -> Bool {
    guard let regex = try? NSRegularExpression(pattern: #"^(\d+\.)\s+(.+)$"#),
      let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: line.utf16.count))
    else {
      return false
    }

    let numberRange = match.range(at: 1)
    let numberAbsolute = NSRange(
      location: range.location + numberRange.location, length: numberRange.length)

    textStorage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: numberAbsolute)

    let listParagraph = NSMutableParagraphStyle()
    listParagraph.firstLineHeadIndent = 0
    listParagraph.headIndent = 20
    textStorage.addAttribute(.paragraphStyle, value: listParagraph, range: range)

    return true
  }

  // MARK: - Inline Bold

  private static func applyBold(
    _ textStorage: NSTextStorage, searchRange: NSRange, fullString: NSString
  ) {
    guard let regex = try? NSRegularExpression(pattern: #"\*\*(.+?)\*\*"#) else { return }

    let line = fullString.substring(with: searchRange)
    let matches = regex.matches(in: line, range: NSRange(location: 0, length: line.utf16.count))

    for match in matches {
      let fullMatchRange = match.range(at: 0)
      let innerRange = match.range(at: 1)

      // Style the opening **
      let openStars = NSRange(
        location: searchRange.location + fullMatchRange.location, length: 2)
      textStorage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: openStars)

      // Style the closing **
      let closeStars = NSRange(
        location: searchRange.location + fullMatchRange.location + fullMatchRange.length - 2,
        length: 2)
      textStorage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: closeStars)

      // Bold the inner text
      let innerAbsolute = NSRange(
        location: searchRange.location + innerRange.location, length: innerRange.length)
      let currentFont =
        textStorage.attribute(.font, at: innerAbsolute.location, effectiveRange: nil) as? NSFont
        ?? NSFont.systemFont(ofSize: 15)
      let boldFont = NSFontManager.shared.convert(currentFont, toHaveTrait: .boldFontMask)
      textStorage.addAttribute(.font, value: boldFont, range: innerAbsolute)
    }
  }

  // MARK: - Inline Links

  private static func applyLinks(
    _ textStorage: NSTextStorage, searchRange: NSRange, fullString: NSString
  ) {
    guard let regex = try? NSRegularExpression(pattern: #"\[([^\]]+)\]\(([^\)]+)\)"#) else {
      return
    }

    let line = fullString.substring(with: searchRange)
    let matches = regex.matches(in: line, range: NSRange(location: 0, length: line.utf16.count))

    for match in matches {
      let fullMatchRange = match.range(at: 0)
      let linkTextRange = match.range(at: 1)
      let urlRange = match.range(at: 2)

      let fullAbsolute = NSRange(
        location: searchRange.location + fullMatchRange.location, length: fullMatchRange.length)

      // Color all delimiter characters and the URL in tertiaryLabelColor
      textStorage.addAttribute(
        .foregroundColor, value: NSColor.tertiaryLabelColor, range: fullAbsolute)

      // Style the link text
      let linkTextAbsolute = NSRange(
        location: searchRange.location + linkTextRange.location, length: linkTextRange.length)
      textStorage.addAttribute(.foregroundColor, value: NSColor.linkColor, range: linkTextAbsolute)

      // Add the link attribute
      let urlString = (line as NSString).substring(with: urlRange)
      if let url = URL(string: urlString) {
        textStorage.addAttribute(.link, value: url, range: linkTextAbsolute)
      }
    }
  }
}
