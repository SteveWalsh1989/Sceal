//
//  MarkdownEditorFormatter+Conversion.swift
//

// Converts display NSAttributedString back to raw markdown for persistence.

import AppKit

// MARK: - Display → Raw Markdown

extension MarkdownEditorFormatter {

  // Walks the attributed string line-by-line and reconstructs raw markdown.
  static func convertToMarkdown(from attributedString: NSAttributedString) -> String {
    let nsString = attributedString.string as NSString
    guard nsString.length > 0 else { return "" }

    var markdownLines: [String] = []
    var lineStart = 0
    var insidePromptBlock = false

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

      let lineText =
        textRange.length > 0 ? nsString.substring(with: textRange) : ""
      let attrs =
        textRange.length > 0
        ? attributedString.attributes(at: textRange.location, effectiveRange: nil)
        : [:]

      let markdownLine: String
      if attrs[.markdownPromptBoundary] as? Bool == true,
        let kind = attrs[.markdownPromptBoundaryKind] as? String
      {
        if kind == promptBoundaryStartKind {
          insidePromptBlock = true
          markdownLine = promptBlockStartMarker
        } else {
          insidePromptBlock = false
          markdownLine = promptBlockEndMarker
        }
      } else if insidePromptBlock {
        markdownLine = lineText
      } else {
        markdownLine = reconstructLine(from: attributedString, textRange: textRange)
      }
      markdownLines.append(markdownLine)
      lineStart = NSMaxRange(lineRange)
    }

    // Collapse blank lines immediately after section dividers so they don't accumulate on reload.
    let sectionPrefix = "<!-- section"
    var normalized: [String] = []
    var skipBlanks = false
    for mdLine in markdownLines {
      if mdLine.hasPrefix(sectionPrefix) {
        normalized.append(mdLine)
        skipBlanks = true
        continue
      }
      if skipBlanks {
        if mdLine.trimmingCharacters(in: .whitespaces).isEmpty {
          continue
        }
        skipBlanks = false
      }
      normalized.append(mdLine)
    }

    return normalized.joined(separator: "\n")
  }

  // Converts a selection to markdown, falling back to inline-only reconstruction for partial lines.
  static func convertSelectionToMarkdown(
    from attributedString: NSAttributedString,
    preserveBlockStructure: Bool
  ) -> String {
    if preserveBlockStructure {
      return convertToMarkdown(from: attributedString)
    }
    return convertInlineSelectionToMarkdown(from: attributedString)
  }

  // Rebuilds a single markdown line from its display attributes.
  private static func reconstructLine(
    from attributedString: NSAttributedString, textRange: NSRange
  ) -> String {
    guard textRange.length > 0 else { return "" }

    let nsString = attributedString.string as NSString
    let lineText = nsString.substring(with: textRange)
    let attrs = attributedString.attributes(at: textRange.location, effectiveRange: nil)

    // Prompt boundary — hidden Sceal-specific marker.
    if attrs[.markdownPromptBoundary] as? Bool == true,
      let kind = attrs[.markdownPromptBoundaryKind] as? String
    {
      return kind == promptBoundaryStartKind ? promptBlockStartMarker : promptBlockEndMarker
    }

    // Prompt block — pass through without inline markdown reconstruction.
    if attrs[.markdownPromptBlock] as? Bool == true {
      return lineText
    }

    if attrs[.markdownTableBlock] as? Bool == true,
      let table = attrs[.markdownTableModel] as? MarkdownEditorTable
    {
      return MarkdownEditorTableMarkdown.serialize(table)
    }

    if attrs[.markdownImageBlock] as? Bool == true,
      let path = attrs[.markdownImagePath] as? String
    {
      let title = attrs[.markdownImageTitle] as? String ?? ""
      let imageLine = imageMarkdownLine(title: title, path: path)
      if let width = imageWidthValue(from: attrs[.markdownImageWidth]) {
        return "\(imageWidthMarker(for: width))\n\(imageLine)"
      }
      return imageLine
    }

    // Code fence — pass through
    if attrs[.markdownCodeFence] as? Bool == true {
      return lineText
    }

    // Code block — pass through
    if attrs[.markdownCodeBlock] as? Bool == true {
      return lineText
    }

    // Section divider — Sceal-specific card-gap marker with optional per-section colors
    if attrs[.markdownSectionDivider] as? Bool == true {
      return MarkdownEditorSectionDirectiveMarkdown.marker(
        headingColorName: attrs[.markdownSectionHeadingColor] as? String,
        bulletColorName: attrs[.markdownSectionBulletColor] as? String,
        usesSectionColor: (attrs[.markdownSectionUseSectionColor] as? Bool) == true
      )
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

  // Restores inline delimiters (bold, italic, links, etc.) from attributes.
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

      if attrs[.markdownTableBlock] as? Bool == true,
        let table = attrs[.markdownTableModel] as? MarkdownEditorTable
      {
        result += MarkdownEditorTableMarkdown.serialize(table)
        return
      }

      if attrs[.markdownImageBlock] as? Bool == true,
        let path = attrs[.markdownImagePath] as? String
      {
        let title = attrs[.markdownImageTitle] as? String ?? ""
        if let width = imageWidthValue(from: attrs[.markdownImageWidth]) {
          result += "\(imageWidthMarker(for: width))\n"
        }
        result += imageMarkdownLine(title: title, path: path)
        return
      }

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

  // Reconstructs only inline markdown so partial-line selections don't grow block prefixes.
  private static func convertInlineSelectionToMarkdown(from attributedString: NSAttributedString)
    -> String
  {
    let nsString = attributedString.string as NSString
    guard nsString.length > 0 else { return "" }

    var markdownLines: [String] = []
    var lineStart = 0

    while lineStart < nsString.length {
      let lineRange = nsString.lineRange(for: NSRange(location: lineStart, length: 0))
      var textRange = lineRange

      if textRange.length > 0
        && nsString.character(at: textRange.location + textRange.length - 1) == 0x0A
      {
        textRange.length -= 1
      }

      markdownLines.append(reconstructInlineMarkdown(from: attributedString, range: textRange))
      lineStart = NSMaxRange(lineRange)
    }

    return markdownLines.joined(separator: "\n")
  }

  private static func imageWidthValue(from value: Any?) -> CGFloat? {
    MarkdownEditorImageMarkdown.widthValue(from: value)
  }
}
