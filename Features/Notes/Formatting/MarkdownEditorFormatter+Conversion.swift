//
//  MarkdownEditorFormatter+Conversion.swift
//

// Converts display NSAttributedString back to raw markdown for persistence.

import AppKit

// MARK: - Display → Raw Markdown

extension MarkdownEditorFormatter {

  // Walks the attributed string line-by-line and reconstructs raw markdown.
  static func convertToMarkdown(
    from attributedString: NSAttributedString,
    normalizesSectionDirectives: Bool = true
  ) -> String {
    let nsString = attributedString.string as NSString
    guard nsString.length > 0 else { return "" }

    var markdownLines: [String] = []
    var lineStart = 0
    var insidePromptBlock = false
    var unmatchedPromptStartIndex: Int?

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

      if let boundary = promptBoundary(in: textRange, from: attributedString) {
        let boundaryLineText = lineTextRemovingPromptBoundary(
          boundary.range,
          from: textRange,
          in: attributedString
        )

        if MarkdownEditorPromptBlockMarkdown.isStartBoundaryKind(boundary.kind) {
          if let unmatchedPromptStartIndex {
            markdownLines.remove(at: unmatchedPromptStartIndex)
          }
          markdownLines.append(
            MarkdownEditorPromptBlockMarkdown.marker(forBoundaryKind: boundary.kind))
          unmatchedPromptStartIndex = markdownLines.count - 1
          insidePromptBlock = true
          if !boundaryLineText.isEmpty {
            markdownLines.append(boundaryLineText)
          }
        } else if insidePromptBlock {
          if !boundaryLineText.isEmpty {
            markdownLines.append(boundaryLineText)
          }
          markdownLines.append(
            MarkdownEditorPromptBlockMarkdown.marker(forBoundaryKind: boundary.kind))
          unmatchedPromptStartIndex = nil
          insidePromptBlock = false
        } else if !boundaryLineText.isEmpty {
          markdownLines.append(boundaryLineText)
        }

        lineStart = NSMaxRange(lineRange)
        continue
      }

      let markdownLine: String
      if insidePromptBlock {
        markdownLine = lineText
      } else {
        markdownLine = reconstructLine(from: attributedString, textRange: textRange)
      }
      markdownLines.append(markdownLine)
      lineStart = NSMaxRange(lineRange)
    }

    if let unmatchedPromptStartIndex {
      markdownLines.remove(at: unmatchedPromptStartIndex)
    }

    guard normalizesSectionDirectives else {
      return markdownLines.joined(separator: "\n")
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

  // Finds a prompt marker even when editable text has become attached to its hidden glyph.
  private static func promptBoundary(
    in textRange: NSRange,
    from attributedString: NSAttributedString
  ) -> (kind: String, range: NSRange)? {
    guard textRange.length > 0 else { return nil }

    var boundary: (kind: String, range: NSRange)?
    attributedString.enumerateAttribute(
      .markdownPromptBoundaryKind,
      in: textRange,
      options: []
    ) { value, range, stop in
      guard let kind = value as? String else { return }
      boundary = (kind, range)
      stop.pointee = true
    }
    return boundary
  }

  // Preserves accidental text on a boundary row while stripping only the structural glyph.
  private static func lineTextRemovingPromptBoundary(
    _ boundaryRange: NSRange,
    from textRange: NSRange,
    in attributedString: NSAttributedString
  ) -> String {
    let line = NSMutableAttributedString(
      attributedString: attributedString.attributedSubstring(from: textRange)
    )
    let intersection = NSIntersectionRange(boundaryRange, textRange)
    guard intersection.length > 0 else { return line.string }
    line.deleteCharacters(
      in: NSRange(
        location: intersection.location - textRange.location,
        length: intersection.length
      )
    )
    return line.string
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
      return MarkdownEditorPromptBlockMarkdown.marker(forBoundaryKind: kind)
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
      return MarkdownEditorBlockMarkdown.horizontalRuleMarker
    }

    // Determine line prefix from attributes
    var prefix = ""
    var contentStart = 0

    if let level = attrs[.markdownHeadingLevel] as? Int {
      prefix = MarkdownEditorBlockMarkdown.headingPrefix(for: level)
      contentStart = 0

      // Heading color comment
      if let colorName = attrs[.markdownHeadingColor] as? String {
        let contentRange = NSRange(
          location: textRange.location + contentStart,
          length: textRange.length - contentStart
        )
        let inlineMarkdown = reconstructInlineMarkdown(from: attributedString, range: contentRange)
        return
          "\(MarkdownEditorHeadingColorMarkdown.marker(colorName: colorName))\n" + prefix
          + inlineMarkdown
      }
    } else if attrs[.markdownBlockquote] as? Bool == true {
      prefix = MarkdownEditorBlockMarkdown.blockquotePrefix
      contentStart = 0
    } else if let rawType = attrs[.markdownListType] as? String,
      let listType = MarkdownListType(rawValue: rawType)
    {
      let indentLevel = attrs[.markdownIndentLevel] as? Int ?? 0
      switch listType {
      case .bullet, .checkboxUnchecked, .checkboxChecked:
        prefix =
          MarkdownEditorListMarkdown.persistedPrefix(
            for: listType,
            indentLevel: indentLevel
          ) ?? ""
        contentStart = MarkdownEditorListMarkdown.displayContentStart(
          in: lineText,
          listType: listType,
          bulletMarker: bulletMarker,
          uncheckedMarker: uncheckedMarker,
          checkedMarker: checkedMarker
        )
      case .numbered:
        // Number text is already in the display, pass through
        let inlineMarkdown = reconstructInlineMarkdown(
          from: attributedString,
          range: textRange
        )
        return MarkdownEditorListMarkdown.indentPrefix(for: indentLevel) + inlineMarkdown
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

      result += MarkdownEditorInlineMarkdown.serializedSpan(
        text: text,
        isBold: isBold,
        isItalic: isItalic,
        isStrikethrough: isStrike,
        isCode: isCode,
        linkURL: linkURL
      )
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
