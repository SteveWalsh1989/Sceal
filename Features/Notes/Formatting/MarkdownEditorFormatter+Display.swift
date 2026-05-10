//
//  MarkdownEditorFormatter+Display.swift
//

// Builds display-ready attributed strings from raw markdown lines.

import AppKit

// MARK: - Display Line Building & Inline Formatting

extension MarkdownEditorFormatter {

  // MARK: - Build Display Line (single raw markdown line → attributed string)

  // Converts a single raw markdown line into a styled NSAttributedString.
  static func buildDisplayLine(
    _ rawLine: String,
    appearance: NoteAppearanceSettings,
    imageWidth: CGFloat? = nil,
    libraryRootURL: URL? = nil
  )
    -> NSAttributedString
  {
    let parsedListLine = MarkdownEditorListMarkdown.parse(rawLine)
    let trimmedLine =
      parsedListLine?.displayText ?? MarkdownEditorListMarkdown.lineWithoutIndent(rawLine)

    let baseAttrs: [NSAttributedString.Key: Any] = [
      .font: appearance.bodyFont,
      .foregroundColor: NSColor.labelColor,
      .paragraphStyle: bodyParagraphStyle(for: appearance),
    ]

    if let image = parseMarkdownImage(trimmedLine) {
      return styledImageBlock(
        title: image.title,
        path: image.path,
        width: imageWidth,
        appearance: appearance,
        libraryRootURL: libraryRootURL
      )
    }

    // Section divider — Sceal card-gap marker
    if let section = MarkdownEditorSectionDirectiveMarkdown.parse(trimmedLine) {
      return styledSectionDivider(
        appearance: appearance,
        headingColorName: section.headingColorName,
        bulletColorName: section.bulletColorName,
        useSectionColor: section.useSectionColorAttributeValue
      )
    }

    // Horizontal rule — standard markdown visible line
    if MarkdownEditorBlockMarkdown.isHorizontalRule(trimmedLine) {
      return styledHorizontalRule()
    }

    // Heading
    if let headingLine = MarkdownEditorBlockMarkdown.parseHeading(trimmedLine) {
      let fontSize = headingFontSize(for: headingLine.level)
      let result = NSMutableAttributedString(
        string: headingLine.content,
        attributes: [
          .font: appearance.boldBodyFont(ofSize: fontSize),
          .foregroundColor: NSColor.labelColor,
          .markdownHeadingLevel: headingLine.level,
          .paragraphStyle: bodyParagraphStyle(for: appearance),
        ])
      applyInlineFormatting(in: result, defaultFont: appearance.boldBodyFont(ofSize: fontSize))
      return result
    }

    if let listLine = parsedListLine, listLine.type == .checkboxChecked {
      let checkAttr = checkboxAttributedString(checked: true, appearance: appearance)
      let contentAttr = NSMutableAttributedString(
        string: " \(listLine.content)", attributes: baseAttrs)
      applyInlineFormatting(in: contentAttr, defaultFont: appearance.bodyFont)
      let result = NSMutableAttributedString()
      result.append(checkAttr)
      result.append(contentAttr)
      let fullRange = NSRange(location: 0, length: result.length)
      result.addAttributes(
        [
          .markdownListType: MarkdownListType.checkboxChecked.rawValue,
          .strikethroughStyle: NSUnderlineStyle.single.rawValue,
          .paragraphStyle: listParagraphStyle(for: appearance, indentLevel: listLine.indentLevel),
          .markdownIndentLevel: listLine.indentLevel,
        ], range: fullRange)
      // Remove strikethrough from the checkbox character itself
      result.removeAttribute(.strikethroughStyle, range: NSRange(location: 0, length: 1))
      return result
    }

    if let listLine = parsedListLine, listLine.type == .checkboxUnchecked {
      let checkAttr = checkboxAttributedString(checked: false, appearance: appearance)
      let contentAttr = NSMutableAttributedString(
        string: " \(listLine.content)", attributes: baseAttrs)
      applyInlineFormatting(in: contentAttr, defaultFont: appearance.bodyFont)
      let result = NSMutableAttributedString()
      result.append(checkAttr)
      result.append(contentAttr)
      let fullRange = NSRange(location: 0, length: result.length)
      result.addAttributes(
        [
          .markdownListType: MarkdownListType.checkboxUnchecked.rawValue,
          .paragraphStyle: listParagraphStyle(for: appearance, indentLevel: listLine.indentLevel),
          .markdownIndentLevel: listLine.indentLevel,
        ], range: fullRange)
      return result
    }

    if let listLine = parsedListLine, listLine.type == .bullet {
      let displayText = "\(bulletMarker) \(listLine.content)"
      let result = NSMutableAttributedString(string: displayText, attributes: baseAttrs)
      let fullRange = NSRange(location: 0, length: result.length)
      result.addAttributes(
        [
          .markdownListType: MarkdownListType.bullet.rawValue,
          .paragraphStyle: listParagraphStyle(for: appearance, indentLevel: listLine.indentLevel),
          .markdownIndentLevel: listLine.indentLevel,
        ], range: fullRange)
      result.addAttributes(
        [
          .foregroundColor: bulletColor(for: appearance),
          .font: NSFont.systemFont(ofSize: appearance.bulletSize, weight: .bold),
        ], range: NSRange(location: 0, length: 1))
      applyInlineFormatting(in: result, defaultFont: appearance.bodyFont)
      return result
    }

    if let listLine = parsedListLine, listLine.type == .numbered {
      let result = NSMutableAttributedString(string: trimmedLine, attributes: baseAttrs)
      let fullRange = NSRange(location: 0, length: result.length)
      result.addAttributes(
        [
          .markdownListType: MarkdownListType.numbered.rawValue,
          .paragraphStyle: listParagraphStyle(for: appearance, indentLevel: listLine.indentLevel),
          .markdownIndentLevel: listLine.indentLevel,
        ], range: fullRange)
      if let numLength = listLine.orderedMarkerLength {
        result.addAttribute(
          .foregroundColor, value: NSColor.secondaryLabelColor,
          range: NSRange(location: 0, length: numLength))
      }
      applyInlineFormatting(in: result, defaultFont: appearance.bodyFont)
      return result
    }

    // Blockquote (single-level only)
    if let blockquoteLine = MarkdownEditorBlockMarkdown.parseBlockquote(trimmedLine) {
      let quoteStyle = blockquoteParagraphStyle(for: appearance)
      let result = NSMutableAttributedString(
        string: blockquoteLine.content,
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
        let match = MarkdownEditorInlineMarkdown.boldRegex.firstMatch(
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
        let match = MarkdownEditorInlineMarkdown.italicRegex.firstMatch(
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
        let match = MarkdownEditorInlineMarkdown.strikethroughRegex.firstMatch(
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
        let match = MarkdownEditorInlineMarkdown.inlineCodeRegex.firstMatch(
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
        let match = MarkdownEditorInlineMarkdown.linkRegex.firstMatch(
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

    applyAutomaticLinkDetection(in: attrStr, range: range)
  }

  // Convenience for applying all inline formatting to a standalone attributed string.
  static func applyInlineFormatting(
    in attrStr: NSMutableAttributedString, defaultFont: NSFont
  ) {
    applyInlineFormatting(
      in: attrStr, range: NSRange(location: 0, length: attrStr.length), defaultFont: defaultFont)
  }

  // Detects plain URLs so pasted or typed links become clickable without explicit markdown syntax.
  private static func applyAutomaticLinkDetection(
    in attrStr: NSMutableAttributedString,
    range: NSRange
  ) {
    guard let urlDetector = MarkdownEditorInlineMarkdown.urlDetector else { return }

    let matches = urlDetector.matches(in: attrStr.string, range: range)
    for match in matches {
      let matchRange = match.range
      guard matchRange.length > 0 else { continue }
      guard let url = match.url else { continue }
      guard shouldApplyAutomaticLink(to: attrStr, range: matchRange) else { continue }

      attrStr.addAttributes(
        [
          .foregroundColor: NSColor.linkColor,
          .link: url,
        ],
        range: matchRange
      )
    }
  }

  // Skips autolinks inside code or ranges that already carry explicit link metadata.
  private static func shouldApplyAutomaticLink(
    to attrStr: NSMutableAttributedString,
    range: NSRange
  ) -> Bool {
    var shouldApply = true

    attrStr.enumerateAttributes(in: range, options: []) { attrs, _, stop in
      let alreadyLinked =
        attrs[.markdownInlineCode] as? Bool == true
        || attrs[.markdownLinkURL] != nil
        || attrs[.link] != nil
      if alreadyLinked {
        shouldApply = false
        stop.pointee = true
      }
    }

    return shouldApply
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

  // Styles a code block line with monospace font. Background is drawn full-width by MarkdownEditorTextView.
  static func styledCodeBlockLine(_ line: String) -> NSAttributedString {
    NSAttributedString(
      string: line,
      attributes: [
        .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
        .foregroundColor: NSColor.labelColor,
        .markdownCodeBlock: true,
      ])
  }

  // Creates a hidden prompt marker line so prompt blocks can round-trip without visible delimiters.
  static func styledPromptBoundaryLine(
    kind: String,
    appearance _: NoteAppearanceSettings
  ) -> NSAttributedString {
    let style = NSMutableParagraphStyle()
    style.baseWritingDirection = .leftToRight
    style.minimumLineHeight = 12
    style.maximumLineHeight = 12

    return NSAttributedString(
      string: " ",
      attributes: [
        .font: NSFont.systemFont(ofSize: 1),
        .foregroundColor: NSColor.clear,
        .paragraphStyle: style,
        .markdownPromptBoundary: true,
        .markdownPromptBoundaryKind: kind,
      ])
  }

  // Styles prompt block content as plain text inside a copyable editor box.
  static func styledPromptBlockLine(
    _ line: String,
    appearance: NoteAppearanceSettings
  ) -> NSAttributedString {
    NSAttributedString(
      string: line,
      attributes: [
        .font: appearance.bodyFont,
        .foregroundColor: NSColor.labelColor,
        .paragraphStyle: promptBlockParagraphStyle(for: appearance),
        .markdownPromptBlock: true,
      ])
  }

  // Creates a single attachment character that renders an image plus its optional title.
  static func styledImageBlock(
    title: String,
    path: String,
    width: CGFloat?,
    appearance: NoteAppearanceSettings,
    libraryRootURL: URL? = nil
  ) -> NSAttributedString {
    let resolvedWidth = clampedImageWidth(width ?? imageDefaultWidth)
    let renderedImage = renderedImageAttachment(
      title: title,
      path: path,
      width: resolvedWidth,
      libraryRootURL: libraryRootURL
    )
    let attachment = NSTextAttachment()
    attachment.image = renderedImage
    attachment.bounds = NSRect(origin: .zero, size: renderedImage.size)

    let result = NSMutableAttributedString(attachment: attachment)
    var attrs: [NSAttributedString.Key: Any] = [
      .markdownImageBlock: true,
      .markdownImagePath: path,
      .markdownImageTitle: title,
      .paragraphStyle: imageParagraphStyle(for: appearance),
    ]
    if let width {
      attrs[.markdownImageWidth] = clampedImageWidth(width)
    }
    result.addAttributes(attrs, range: NSRange(location: 0, length: result.length))
    return result
  }

  static func styledTableBlock(
    _ table: MarkdownEditorTable,
    appearance: NoteAppearanceSettings
  ) -> NSAttributedString {
    let normalized = table.normalized()
    let size = MarkdownEditorTableMetrics.tableSize(for: normalized, appearance: appearance)
    let attachment = NSTextAttachment()
    attachment.image = transparentTablePlaceholder(size: size)
    attachment.bounds = NSRect(origin: .zero, size: size)

    let result = NSMutableAttributedString(attachment: attachment)
    result.addAttributes(
      [
        .markdownTableBlock: true,
        .markdownTableID: normalized.runtimeID,
        .markdownTableModel: normalized,
        .paragraphStyle: tableParagraphStyle(for: appearance),
      ],
      range: NSRange(location: 0, length: result.length)
    )
    return result
  }

  static func clampedImageWidth(_ width: CGFloat) -> CGFloat {
    MarkdownEditorImageMarkdown.clampedWidth(width)
  }

  static func parseImageWidthMarker(_ line: String) -> CGFloat? {
    MarkdownEditorImageMarkdown.parseWidthMarker(line)
  }

  static func parseMarkdownImage(_ line: String) -> (title: String, path: String)? {
    MarkdownEditorImageMarkdown.parseImage(line)
  }

  static func imageWidthMarker(for width: CGFloat) -> String {
    MarkdownEditorImageMarkdown.widthMarker(for: width)
  }

  static func imageMarkdownLine(title: String, path: String) -> String {
    MarkdownEditorImageMarkdown.imageLine(title: title, path: path)
  }

  private static func imageParagraphStyle(for appearance: NoteAppearanceSettings)
    -> NSParagraphStyle
  {
    let style = NSMutableParagraphStyle()
    style.baseWritingDirection = .leftToRight
    style.paragraphSpacingBefore = 8
    style.paragraphSpacing = 10
    style.lineHeightMultiple = appearance.lineHeight
    return style.copy() as! NSParagraphStyle
  }

  static func updateTableAttachment(
    in attributedString: NSMutableAttributedString,
    range: NSRange,
    table: MarkdownEditorTable,
    appearance: NoteAppearanceSettings
  ) {
    guard range.length > 0, range.location < attributedString.length else { return }
    let normalized = table.normalized()
    let size = MarkdownEditorTableMetrics.tableSize(for: normalized, appearance: appearance)
    if let attachment = attributedString.attribute(
      .attachment, at: range.location, effectiveRange: nil)
      as? NSTextAttachment
    {
      attachment.image = transparentTablePlaceholder(size: size)
      attachment.bounds = NSRect(origin: .zero, size: size)
    }
    attributedString.addAttributes(
      [
        .markdownTableBlock: true,
        .markdownTableID: normalized.runtimeID,
        .markdownTableModel: normalized,
        .paragraphStyle: tableParagraphStyle(for: appearance),
      ],
      range: range
    )
  }

  private static func tableParagraphStyle(for appearance: NoteAppearanceSettings)
    -> NSParagraphStyle
  {
    let style = NSMutableParagraphStyle()
    style.baseWritingDirection = .leftToRight
    style.paragraphSpacingBefore = 8
    style.paragraphSpacing = 10
    style.lineHeightMultiple = appearance.lineHeight
    return style.copy() as! NSParagraphStyle
  }

  private static func transparentTablePlaceholder(size: NSSize) -> NSImage {
    let rendered = NSImage(size: size)
    rendered.lockFocus()
    NSColor.clear.setFill()
    NSRect(origin: .zero, size: size).fill()
    rendered.unlockFocus()
    return rendered
  }

  private static func renderedImageAttachment(
    title: String,
    path: String,
    width: CGFloat,
    libraryRootURL: URL?
  ) -> NSImage {
    let sourceImage = NoteImageAttachmentStore.resolvedImageURL(
      for: path,
      libraryRootURL: libraryRootURL
    )
    .flatMap { NSImage(contentsOf: $0) }
    let imageSize = sourceImage?.size ?? NSSize(width: width, height: width * 0.58)
    let safeImageWidth = max(imageSize.width, 1)
    let imageHeight = max(width * (imageSize.height / safeImageWidth), 80)
    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let captionHeight: CGFloat = trimmedTitle.isEmpty ? 0 : 24
    let canvasSize = NSSize(width: width, height: imageHeight + captionHeight)

    let rendered = NSImage(size: canvasSize)
    rendered.lockFocus()

    let imageRect = NSRect(x: 0, y: captionHeight, width: width, height: imageHeight)
    if let sourceImage {
      sourceImage.draw(
        in: imageRect,
        from: .zero,
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: true,
        hints: [.interpolation: NSImageInterpolation.high]
      )
    } else {
      drawMissingImagePlaceholder(in: imageRect)
    }

    if !trimmedTitle.isEmpty {
      let caption = trimmedTitle as NSString
      let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12, weight: .medium),
        .foregroundColor: NSColor.secondaryLabelColor,
      ]
      caption.draw(
        in: NSRect(x: 0, y: 2, width: width, height: 18),
        withAttributes: attrs
      )
    }

    rendered.unlockFocus()
    return rendered
  }

  private static func drawMissingImagePlaceholder(in rect: NSRect) {
    let fillColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.22)
    fillColor.setFill()
    NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()

    let label = "Image unavailable" as NSString
    let attrs: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 12, weight: .medium),
      .foregroundColor: NSColor.secondaryLabelColor,
    ]
    let labelSize = label.size(withAttributes: attrs)
    label.draw(
      in: NSRect(
        x: rect.midX - labelSize.width / 2,
        y: rect.midY - labelSize.height / 2,
        width: labelSize.width,
        height: labelSize.height
      ),
      withAttributes: attrs
    )
  }

  // Creates an invisible marker that MarkdownEditorTextView renders as a card gap.
  static func styledSectionDivider(
    appearance: NoteAppearanceSettings = .default,
    headingColorName: String? = nil,
    bulletColorName: String? = nil,
    useSectionColor: Bool? = nil
  ) -> NSAttributedString {
    // Invisible marker — the visual split comes from MarkdownEditorTextView drawing
    // separate card backgrounds for each section. This character occupies
    // a single line that becomes the gap between cards.
    let gapStyle = NSMutableParagraphStyle()
    gapStyle.baseWritingDirection = .leftToRight
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
  // The actual line is drawn by MarkdownEditorTextView; this marker reserves the vertical space.
  static func styledHorizontalRule() -> NSAttributedString {
    let style = NSMutableParagraphStyle()
    style.baseWritingDirection = .leftToRight
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

    // Bullets and checkboxes use the heading color in same-color mode, otherwise their own color.
    guard
      let rawType = attrs[.markdownListType] as? String,
      let listType = MarkdownListType(rawValue: rawType)
    else { return nil }

    let sectionColor: NSColor? = {
      if useSectionColor, let name = headingColorName {
        return headingColor(named: name)
      }
      if let name = bulletColorName {
        return headingColor(named: name)
      }
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
      let preservedParagraphStyle = attrs[.paragraphStyle]
      let preservedIndentLevel = attrs[.markdownIndentLevel]
      mutable.replaceCharacters(in: NSRange(location: 0, length: 1), with: newAttachment)
      mutable.addAttribute(
        .markdownListType, value: listType.rawValue,
        range: NSRange(location: 0, length: 1))
      if let preservedParagraphStyle {
        mutable.addAttribute(
          .paragraphStyle,
          value: preservedParagraphStyle,
          range: NSRange(location: 0, length: 1)
        )
      }
      if let preservedIndentLevel {
        mutable.addAttribute(
          .markdownIndentLevel,
          value: preservedIndentLevel,
          range: NSRange(location: 0, length: 1)
        )
      }
      return mutable

    case .numbered:
      return nil
    }
  }

  // MARK: - Helpers

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
