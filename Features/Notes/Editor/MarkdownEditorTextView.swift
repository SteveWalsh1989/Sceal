//
//  MarkdownEditorTextView.swift
//

// Custom TextKit 2 NSTextView subclass handling section cards, divider navigation, and checkboxes.

import AppKit
import UniformTypeIdentifiers

@MainActor
final class MarkdownEditorTextView: NSTextView {
  private struct SectionLayoutSnapshot {
    let dividerLineRanges: [NSRange]
    let sections: [NSRange]
    let dividerMidYs: [CGFloat]
  }

  var appearanceSettings = NoteAppearanceSettings.default
  var noteID: DayNote.ID?
  var imageAttachmentRootURL: URL?
  var imageAttachmentFileManager: FileManager = .default

  // Section card rendering constants.
  private let sectionCardBaseGapOffset: CGFloat = 4
  private var sectionCardGapOffset: CGFloat {
    sectionCardBaseGapOffset * appearanceSettings.sectionDividerGapScale
  }
  private var cardColor: NSColor {
    appearanceSettings.resolvedColors.sectionCardFill.nsColor
  }
  private let cardRadius: CGFloat = 24
  private let cardHInset: CGFloat = 0
  private let cardVPad: CGFloat = 10

  // Code block background rendering constants.
  private let codeBlockVPad: CGFloat = 4
  private let codeBlockRadius: CGFloat = 6

  // Prompt block rendering and hit testing constants.
  private let promptBlockHInset: CGFloat = 18
  private let promptBlockVPad: CGFloat = 8
  private let promptBlockRadius: CGFloat = 8
  private let promptCopyButtonWidth: CGFloat = 58
  private let promptCopyButtonHeight: CGFloat = 22
  private let promptCloseButtonSize: CGFloat = 22
  private let promptCopyButtonPadding: CGFloat = 10
  private let promptButtonGap: CGFloat = 6
  private var hoveredPromptCopyLocation: Int? = nil
  private var hoveredPromptCloseLocation: Int? = nil
  private var promptCopyTrackingAreas: [NSTrackingArea] = []
  private var promptCloseTrackingAreas: [NSTrackingArea] = []

  // Section icon rendering and hit testing constants.
  private let sectionIconSize: CGFloat = 18
  private let sectionIconPadding: CGFloat = 24
  private let sectionIconHitPadding: CGFloat = 8
  private var hoveredSectionIconLocation: Int? = nil
  private var sectionIconTrackingAreas: [NSTrackingArea] = []

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  private var isDarkAppearance: Bool {
    effectiveAppearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
  }

  // Counts section dividers in the text storage.
  var sectionDividerCount: Int {
    guard let textStorage else { return 0 }
    var count = 0
    textStorage.enumerateAttribute(
      .markdownSectionDivider,
      in: NSRange(location: 0, length: textStorage.length),
      options: []
    ) { value, _, _ in
      if value as? Bool == true { count += 1 }
    }
    return count
  }

  // Finds a nearby non-divider location to source typing attributes from.
  func typingAttributeSourceLocation(forInsertionLocation location: Int) -> Int? {
    guard let textStorage, textStorage.length > 0 else { return nil }

    let clampedLocation = min(max(location, 0), textStorage.length)
    let nsString = textStorage.string as NSString
    let currentLineRange: NSRange = {
      let lineProbe = min(clampedLocation, max(textStorage.length - 1, 0))
      return nsString.lineRange(for: NSRange(location: lineProbe, length: 0))
    }()
    let currentLineStart = currentLineRange.location
    let currentLineEnd = min(NSMaxRange(currentLineRange), textStorage.length)

    if clampedLocation > currentLineStart {
      let backwardRange = stride(
        from: min(clampedLocation - 1, currentLineEnd - 1),
        through: currentLineStart,
        by: -1
      )
      for candidate in backwardRange where canUseTypingAttributes(at: candidate) {
        return candidate
      }
    }

    if clampedLocation < currentLineEnd {
      for candidate in clampedLocation..<currentLineEnd
      where canUseTypingAttributes(at: candidate) {
        return candidate
      }
    }

    if currentLineStart > 0 {
      let priorRange = stride(from: currentLineStart - 1, through: 0, by: -1)
      for candidate in priorRange where canUseTypingAttributes(at: candidate) {
        return candidate
      }
    }

    guard currentLineEnd < textStorage.length else { return nil }
    for candidate in currentLineEnd..<textStorage.length
    where canUseTypingAttributes(at: candidate) {
      return candidate
    }

    return nil
  }

  // Returns false for divider and horizontal rule positions.
  private func canUseTypingAttributes(at location: Int) -> Bool {
    guard let textStorage, location >= 0, location < textStorage.length else { return false }
    let attributes = textStorage.attributes(at: location, effectiveRange: nil)
    guard attributes[.markdownSectionDivider] as? Bool != true else { return false }
    guard attributes[.markdownHorizontalRule] as? Bool != true else { return false }
    guard attributes[.markdownPromptBoundary] as? Bool != true else { return false }
    guard attributes[.markdownImageBlock] as? Bool != true else { return false }
    guard attributes[.font] != nil, attributes[.foregroundColor] != nil else { return false }
    return !isListMarkerTypingAttributeSource(
      at: location,
      attributes: attributes,
      textStorage: textStorage
    )
  }

  // Skips list marker glyph runs so typing inherits the list paragraph style without marker fonts.
  private func isListMarkerTypingAttributeSource(
    at location: Int,
    attributes: [NSAttributedString.Key: Any],
    textStorage: NSTextStorage
  ) -> Bool {
    guard let rawType = attributes[.markdownListType] as? String,
      let listType = MarkdownListType(rawValue: rawType)
    else { return false }

    let nsString = textStorage.string as NSString
    let lineRange = nsString.lineRange(for: NSRange(location: location, length: 0))

    switch listType {
    case .bullet, .checkboxUnchecked, .checkboxChecked:
      return location == lineRange.location
    case .numbered:
      let lineText = nsString.substring(with: lineRange)
      guard let markerRange = lineText.range(of: #"^\d+\."#, options: .regularExpression) else {
        return false
      }
      let markerLength = lineText.distance(from: lineText.startIndex, to: markerRange.upperBound)
      return location < lineRange.location + markerLength
    }
  }

  // Forces layout recalculation and redraws section card backgrounds.
  func refreshSectionLayout() {
    ensureEditorLayoutForEntireDocument()
    setNeedsDisplay(bounds)
    enclosingScrollView?.contentView.needsDisplay = true
  }

  // Walks backward from a character position to find the enclosing section's color settings.
  func sectionColors(at location: Int) -> (
    headingColorName: String?, bulletColorName: String?, useSectionColor: Bool
  )? {
    guard let textStorage, location <= textStorage.length else { return nil }
    var result: (headingColorName: String?, bulletColorName: String?, useSectionColor: Bool)? = nil
    let searchRange = NSRange(location: 0, length: min(location, textStorage.length))
    textStorage.enumerateAttribute(
      .markdownSectionDivider, in: searchRange, options: .reverse
    ) { value, range, stop in
      guard value as? Bool == true else { return }
      let attrs = textStorage.attributes(at: range.location, effectiveRange: nil)
      result = (
        headingColorName: attrs[.markdownSectionHeadingColor] as? String,
        bulletColorName: attrs[.markdownSectionBulletColor] as? String,
        useSectionColor: attrs[.markdownSectionUseSectionColor] as? Bool ?? false
      )
      stop.pointee = true
    }
    return result
  }

  // MARK: - Section Layout Snapshot

  // Finds line ranges for a markdown display attribute like dividers or horizontal rules.
  private func lineRanges(
    forAttribute key: NSAttributedString.Key,
    in textStorage: NSTextStorage
  ) -> [NSRange] {
    let fullRange = NSRange(location: 0, length: textStorage.length)
    var ranges: [NSRange] = []
    textStorage.enumerateAttribute(key, in: fullRange, options: []) { value, range, _ in
      if value as? Bool == true {
        ranges.append((textStorage.string as NSString).lineRange(for: range))
      }
    }
    return ranges
  }

  // Builds the content ranges that sit between section divider lines.
  private func sectionRanges(
    between dividerLineRanges: [NSRange],
    textLength: Int
  ) -> [NSRange] {
    var sections: [NSRange] = []
    var currentStart = 0
    for divRange in dividerLineRanges {
      if divRange.location > currentStart {
        sections.append(NSRange(location: currentStart, length: divRange.location - currentStart))
      }
      currentStart = NSMaxRange(divRange)
    }
    if currentStart < textLength {
      sections.append(NSRange(location: currentStart, length: textLength - currentStart))
    }
    return sections
  }

  // Captures the divider line ranges, section ranges, and divider midpoints for card layout.
  private func sectionLayoutSnapshot() -> SectionLayoutSnapshot? {
    guard let textStorage, textStorage.length > 0 else { return nil }

    let dividerLineRanges = lineRanges(forAttribute: .markdownSectionDivider, in: textStorage)
    guard !dividerLineRanges.isEmpty else { return nil }

    let sections = sectionRanges(between: dividerLineRanges, textLength: textStorage.length)
    let dividerMidYs = dividerLineRanges.compactMap {
      editorMidYInViewCoordinates(forCharacterRange: $0)
    }
    guard dividerMidYs.count == dividerLineRanges.count else { return nil }

    return SectionLayoutSnapshot(
      dividerLineRanges: dividerLineRanges,
      sections: sections,
      dividerMidYs: dividerMidYs
    )
  }

  // MARK: - Section Card Backgrounds

  // Draws section card backgrounds and palette icons instead of the default background.
  override func drawBackground(in rect: NSRect) {
    guard let textStorage, textStorage.length > 0 else {
      drawSingleCard(in: rect)
      return
    }

    let hrLineRanges = lineRanges(forAttribute: .markdownHorizontalRule, in: textStorage)

    guard let layoutSnapshot = sectionLayoutSnapshot() else {
      drawSingleCard(in: rect)
      drawCodeBlocks(in: rect, textStorage: textStorage)
      drawPromptBlocks(in: rect, textStorage: textStorage)
      drawHorizontalRules(hrLineRanges, in: rect)
      return
    }

    let viewBottom = max(bounds.height, enclosingScrollView?.contentSize.height ?? bounds.height)

    for (index, sectionRange) in layoutSnapshot.sections.enumerated() {
      let isLastSection = (index == layoutSnapshot.sections.count - 1)
      guard editorHasVisibleGlyphs(forCharacterRange: sectionRange) || isLastSection else {
        continue
      }

      let cardTop: CGFloat
      if index == 0 {
        cardTop = 0
      } else {
        let divIndex = min(index - 1, layoutSnapshot.dividerMidYs.count - 1)
        cardTop = layoutSnapshot.dividerMidYs[divIndex] + sectionCardGapOffset
      }

      let cardBottom: CGFloat
      if isLastSection {
        cardBottom = viewBottom
      } else {
        let divIndex = min(index, layoutSnapshot.dividerMidYs.count - 1)
        cardBottom = layoutSnapshot.dividerMidYs[divIndex] - sectionCardGapOffset
      }

      let cardRect = NSRect(
        x: cardHInset,
        y: cardTop,
        width: bounds.width - (cardHInset * 2),
        height: max(cardBottom - cardTop, 0)
      )
      guard cardRect.height > 0, cardRect.intersects(rect) else { continue }

      let path = NSBezierPath(roundedRect: cardRect, xRadius: cardRadius, yRadius: cardRadius)
      cardColor.setFill()
      path.fill()

      if index > 0, index - 1 < layoutSnapshot.dividerLineRanges.count {
        let iconRect = NSRect(
          x: cardRect.maxX - sectionIconSize - sectionIconPadding,
          y: cardRect.minY + sectionIconPadding,
          width: sectionIconSize,
          height: sectionIconSize
        )
        let isHovered =
          hoveredSectionIconLocation == layoutSnapshot.dividerLineRanges[index - 1].location
        drawSectionIcon(in: iconRect, hovered: isHovered)
      }
    }
    drawCodeBlocks(in: rect, textStorage: textStorage)
    drawPromptBlocks(in: rect, textStorage: textStorage)
    drawHorizontalRules(hrLineRanges, in: rect)
  }

  // Draws a single full-height card when there are no section dividers.
  private func drawSingleCard(in rect: NSRect) {
    let fullHeight = max(bounds.height, enclosingScrollView?.contentSize.height ?? bounds.height)
    let cardRect = NSRect(
      x: cardHInset, y: 0, width: bounds.width - cardHInset * 2, height: fullHeight
    )
    guard cardRect.intersects(rect) else { return }
    let path = NSBezierPath(roundedRect: cardRect, xRadius: cardRadius, yRadius: cardRadius)
    cardColor.setFill()
    path.fill()
  }

  // Draws a thin visible line for each standard markdown horizontal rule (`---`).
  private func drawHorizontalRules(_ ranges: [NSRange], in rect: NSRect) {
    guard !ranges.isEmpty else { return }
    let lineInset: CGFloat = 24
    let dividerColor =
      MarkdownEditorFormatter.accentColor(for: appearanceSettings).withAlphaComponent(
        isDarkAppearance ? 0.52 : 0.44
      )
    dividerColor.setFill()
    for range in ranges {
      guard let midY = editorMidYInViewCoordinates(forCharacterRange: range) else { continue }
      let hrRect = NSRect(
        x: lineInset, y: midY, width: bounds.width - (lineInset * 2), height: 1
      )
      guard hrRect.intersects(rect) else { continue }
      hrRect.fill()
    }
  }

  // Draws full-width background rectangles behind fenced code blocks.
  private func drawCodeBlocks(in rect: NSRect, textStorage: NSTextStorage) {
    let ranges = codeBlockVisualRanges(in: textStorage)
    guard !ranges.isEmpty else { return }

    let nsString = textStorage.string as NSString
    let codeBlockColor =
      isDarkAppearance
      ? NSColor.black.withAlphaComponent(0.3)
      : NSColor.black.withAlphaComponent(0.06)

    for range in ranges {
      guard range.length > 0 else { continue }

      // Opening fence line rect — trim trailing newline for a tighter glyph rect.
      var openFenceLine = nsString.lineRange(for: NSRange(location: range.location, length: 0))
      if openFenceLine.length > 0,
        nsString.character(at: openFenceLine.location + openFenceLine.length - 1) == 0x0A
      {
        openFenceLine.length -= 1
      }

      // Closing fence line rect — work backward from the end of the code block range.
      let closeFenceLocation = max(NSMaxRange(range) - 1, range.location)
      var closeFenceLine = nsString.lineRange(
        for: NSRange(location: min(closeFenceLocation, max(nsString.length - 1, 0)), length: 0))
      if closeFenceLine.length > 0,
        nsString.character(at: closeFenceLine.location + closeFenceLine.length - 1) == 0x0A
      {
        closeFenceLine.length -= 1
      }

      guard openFenceLine.length > 0, closeFenceLine.length > 0 else { continue }
      guard
        let openRect = editorRectInViewCoordinates(forCharacterRange: openFenceLine),
        let closeRect = editorRectInViewCoordinates(forCharacterRange: closeFenceLine)
      else { continue }

      let blockRect = NSRect(
        x: 0,
        y: openRect.minY - codeBlockVPad,
        width: bounds.width,
        height: closeRect.maxY - openRect.minY + codeBlockVPad * 2
      )
      guard blockRect.height > 0, blockRect.intersects(rect) else { continue }

      codeBlockColor.setFill()
      NSBezierPath(roundedRect: blockRect, xRadius: codeBlockRadius, yRadius: codeBlockRadius)
        .fill()
    }
  }

  // Returns the character ranges of each complete fenced code block (opening fence through closing fence).
  private func codeBlockVisualRanges(in textStorage: NSTextStorage) -> [NSRange] {
    let fullRange = NSRange(location: 0, length: textStorage.length)
    var fenceRanges: [NSRange] = []
    textStorage.enumerateAttribute(.markdownCodeFence, in: fullRange, options: []) {
      value, range, _ in
      if value as? Bool == true { fenceRanges.append(range) }
    }
    var result: [NSRange] = []
    var i = 0
    while i + 1 < fenceRanges.count {
      let opening = fenceRanges[i]
      let closing = fenceRanges[i + 1]
      result.append(
        NSRange(location: opening.location, length: NSMaxRange(closing) - opening.location))
      i += 2
    }
    return result
  }

  // Draws copyable prompt boxes using hidden prompt marker lines as the block boundaries.
  private func drawPromptBlocks(in rect: NSRect, textStorage: NSTextStorage) {
    let ranges = promptBlockVisualRanges(in: textStorage)
    guard !ranges.isEmpty else { return }

    let nsString = textStorage.string as NSString
    let fillColor =
      isDarkAppearance
      ? NSColor.white.withAlphaComponent(0.07)
      : NSColor.black.withAlphaComponent(0.045)
    let strokeColor =
      MarkdownEditorFormatter.accentColor(for: appearanceSettings)
      .withAlphaComponent(isDarkAppearance ? 0.24 : 0.18)

    for range in ranges {
      guard let blockRect = promptBlockRect(for: range, string: nsString) else { continue }
      guard blockRect.intersects(rect) else { continue }

      let path = NSBezierPath(
        roundedRect: blockRect, xRadius: promptBlockRadius, yRadius: promptBlockRadius)
      fillColor.setFill()
      path.fill()
      strokeColor.setStroke()
      path.lineWidth = 1
      path.stroke()

      drawPromptCopyButton(
        in: promptCopyButtonRect(in: blockRect),
        hovered: hoveredPromptCopyLocation == range.location
      )
      drawPromptCloseButton(
        in: promptCloseButtonRect(in: blockRect),
        hovered: hoveredPromptCloseLocation == range.location
      )
    }
  }

  // Pairs hidden prompt start/end marker lines into visual block ranges.
  private func promptBlockVisualRanges(in textStorage: NSTextStorage) -> [NSRange] {
    let fullRange = NSRange(location: 0, length: textStorage.length)
    var result: [NSRange] = []
    var openingLineRange: NSRange?
    let nsString = textStorage.string as NSString

    textStorage.enumerateAttribute(.markdownPromptBoundaryKind, in: fullRange, options: []) {
      value, range, _ in
      guard let kind = value as? String else { return }
      let lineRange = nsString.lineRange(for: range)
      if kind == MarkdownEditorFormatter.promptBoundaryStartKind {
        openingLineRange = lineRange
      } else if kind == MarkdownEditorFormatter.promptBoundaryEndKind,
        let startLineRange = openingLineRange
      {
        result.append(
          NSRange(
            location: startLineRange.location,
            length: NSMaxRange(lineRange) - startLineRange.location
          ))
        openingLineRange = nil
      }
    }

    return result
  }

  // Computes the full prompt box frame from the hidden boundary lines.
  private func promptBlockRect(for range: NSRange, string nsString: NSString) -> NSRect? {
    guard range.length > 0 else { return nil }

    let firstLine = nsString.lineRange(for: NSRange(location: range.location, length: 0))
    let lastLocation = min(max(NSMaxRange(range) - 1, range.location), max(nsString.length - 1, 0))
    let lastLine = nsString.lineRange(for: NSRange(location: lastLocation, length: 0))

    guard
      let firstRect = editorRectInViewCoordinates(forCharacterRange: firstLine),
      let lastRect = editorRectInViewCoordinates(forCharacterRange: lastLine)
    else { return nil }

    return NSRect(
      x: promptBlockHInset,
      y: firstRect.minY - promptBlockVPad,
      width: bounds.width - promptBlockHInset * 2,
      height: lastRect.maxY - firstRect.minY + promptBlockVPad * 2
    )
  }

  private func promptCopyButtonRect(in blockRect: NSRect) -> NSRect {
    let closeRect = promptCloseButtonRect(in: blockRect)
    return NSRect(
      x: closeRect.minX - promptButtonGap - promptCopyButtonWidth,
      y: blockRect.minY + promptCopyButtonPadding,
      width: promptCopyButtonWidth,
      height: promptCopyButtonHeight
    )
  }

  private func promptCloseButtonRect(in blockRect: NSRect) -> NSRect {
    return NSRect(
      x: blockRect.maxX - promptCloseButtonSize - promptCopyButtonPadding,
      y: blockRect.minY + promptCopyButtonPadding,
      width: promptCloseButtonSize,
      height: promptCloseButtonSize
    )
  }

  private func drawPromptCopyButton(in buttonRect: NSRect, hovered: Bool) {
    let buttonPath = NSBezierPath(roundedRect: buttonRect, xRadius: 5, yRadius: 5)
    let buttonFill =
      hovered
      ? MarkdownEditorFormatter.accentColor(for: appearanceSettings).withAlphaComponent(0.24)
      : NSColor.controlBackgroundColor.withAlphaComponent(isDarkAppearance ? 0.38 : 0.72)
    buttonFill.setFill()
    buttonPath.fill()

    let title = "Copy" as NSString
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
      .foregroundColor: NSColor.secondaryLabelColor,
    ]
    let titleSize = title.size(withAttributes: attributes)
    let titleRect = NSRect(
      x: buttonRect.midX - titleSize.width / 2,
      y: buttonRect.midY - titleSize.height / 2,
      width: titleSize.width,
      height: titleSize.height
    )
    title.draw(in: titleRect, withAttributes: attributes)
  }

  private func drawPromptCloseButton(in buttonRect: NSRect, hovered: Bool) {
    let buttonPath = NSBezierPath(roundedRect: buttonRect, xRadius: 5, yRadius: 5)
    let buttonFill =
      hovered
      ? NSColor.systemRed.withAlphaComponent(isDarkAppearance ? 0.28 : 0.18)
      : NSColor.controlBackgroundColor.withAlphaComponent(isDarkAppearance ? 0.3 : 0.62)
    buttonFill.setFill()
    buttonPath.fill()

    guard
      let image = NSImage(
        systemSymbolName: "xmark",
        accessibilityDescription: "Delete prompt block"
      )?
      .withSymbolConfiguration(
        NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
          .applying(
            NSImage.SymbolConfiguration(paletteColors: [.secondaryLabelColor]))
      )
    else { return }

    let imageSize = NSSize(width: 9, height: 9)
    let imageRect = NSRect(
      x: buttonRect.midX - imageSize.width / 2,
      y: buttonRect.midY - imageSize.height / 2,
      width: imageSize.width,
      height: imageSize.height
    )
    image.draw(
      in: imageRect, from: .zero, operation: .sourceOver, fraction: 1,
      respectFlipped: true, hints: nil
    )
  }

  private func promptCopyHitTest(at point: NSPoint) -> NSRange? {
    guard let textStorage else { return nil }
    let nsString = textStorage.string as NSString
    for range in promptBlockVisualRanges(in: textStorage) {
      guard let blockRect = promptBlockRect(for: range, string: nsString) else { continue }
      if promptCopyButtonRect(in: blockRect).contains(point) {
        return range
      }
    }
    return nil
  }

  private func promptCloseHitTest(at point: NSPoint) -> NSRange? {
    guard let textStorage else { return nil }
    let nsString = textStorage.string as NSString
    for range in promptBlockVisualRanges(in: textStorage) {
      guard let blockRect = promptBlockRect(for: range, string: nsString) else { continue }
      if promptCloseButtonRect(in: blockRect).contains(point) {
        return range
      }
    }
    return nil
  }

  private func copyPromptBlock(in range: NSRange, textStorage: NSTextStorage) {
    let promptText = promptBlockText(in: range, textStorage: textStorage)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(promptText, forType: .string)
  }

  // Deletes a whole prompt block, including hidden boundary markers and its content.
  @discardableResult
  func deletePromptBlock(containing location: Int) -> Bool {
    guard let textStorage else { return false }
    let ranges = promptBlockVisualRanges(in: textStorage)
    guard
      let range = ranges.first(where: {
        NSLocationInRange(location, $0) || location == NSMaxRange($0)
      })
    else { return false }
    return deletePromptBlock(in: range, textStorage: textStorage)
  }

  private func deletePromptBlock(in range: NSRange, textStorage: NSTextStorage) -> Bool {
    let handled = performEditorEdit(
      affectedRange: range,
      replacementString: "",
      actionName: "Delete Prompt Block"
    ) { textStorage in
      textStorage.replaceCharacters(in: range, with: "")
      return NSRange(location: range.location, length: 0)
    }

    if handled {
      hoveredPromptCopyLocation = nil
      hoveredPromptCloseLocation = nil
      updateTrackingAreas()
      setNeedsDisplay(bounds)
    }
    return handled
  }

  private func promptBlockText(in range: NSRange, textStorage: NSTextStorage) -> String {
    let nsString = textStorage.string as NSString
    let rangeEnd = min(NSMaxRange(range), nsString.length)
    var lines: [String] = []
    var lineStart = range.location

    while lineStart < rangeEnd {
      let lineRange = nsString.lineRange(for: NSRange(location: lineStart, length: 0))
      var textRange = lineRange
      if textRange.length > 0,
        nsString.character(at: textRange.location + textRange.length - 1) == 0x0A
      {
        textRange.length -= 1
      }

      let isBoundary =
        textRange.length > 0
        && textStorage.attribute(
          .markdownPromptBoundary, at: textRange.location, effectiveRange: nil) as? Bool == true
      if !isBoundary {
        lines.append(textRange.length > 0 ? nsString.substring(with: textRange) : "")
      }

      lineStart = NSMaxRange(lineRange)
    }

    return lines.joined(separator: "\n")
  }

  // Draws the small palette icon — faint by default, full opacity on hover.
  private func drawSectionIcon(in rect: NSRect, hovered: Bool) {
    let color: NSColor = hovered ? .secondaryLabelColor : .quaternaryLabelColor
    guard
      let image = NSImage(
        systemSymbolName: "paintpalette",
        accessibilityDescription: "Section colors"
      )?
      .withSymbolConfiguration(
        NSImage.SymbolConfiguration(pointSize: sectionIconSize, weight: .regular)
          .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
      )
    else { return }
    image.draw(
      in: rect, from: .zero, operation: .sourceOver, fraction: 1.0,
      respectFlipped: true, hints: nil
    )
  }

  // MARK: - Section Icon Hover Tracking

  // Creates hover tracking areas over each section's palette icon.
  override func updateTrackingAreas() {
    super.updateTrackingAreas()

    for area in sectionIconTrackingAreas { removeTrackingArea(area) }
    sectionIconTrackingAreas.removeAll()
    for area in promptCopyTrackingAreas { removeTrackingArea(area) }
    promptCopyTrackingAreas.removeAll()
    for area in promptCloseTrackingAreas { removeTrackingArea(area) }
    promptCloseTrackingAreas.removeAll()

    addPromptActionTrackingAreas()

    guard let layoutSnapshot = sectionLayoutSnapshot() else { return }

    for (index, sectionRange) in layoutSnapshot.sections.enumerated() {
      guard index > 0, index - 1 < layoutSnapshot.dividerLineRanges.count else { continue }
      let isLastSection = (index == layoutSnapshot.sections.count - 1)
      guard editorHasVisibleGlyphs(forCharacterRange: sectionRange) || isLastSection else {
        continue
      }

      let divIndex = min(index - 1, layoutSnapshot.dividerMidYs.count - 1)
      let cardTop = layoutSnapshot.dividerMidYs[divIndex] + sectionCardGapOffset
      let cardWidth = bounds.width - (cardHInset * 2)

      let iconRect = NSRect(
        x: cardHInset + cardWidth - sectionIconSize - sectionIconPadding,
        y: cardTop + sectionIconPadding,
        width: sectionIconSize,
        height: sectionIconSize
      )
      let trackRect = iconRect.insetBy(dx: -sectionIconHitPadding, dy: -sectionIconHitPadding)

      let area = NSTrackingArea(
        rect: trackRect,
        options: [.mouseEnteredAndExited, .activeInActiveApp],
        owner: self,
        userInfo: ["dividerLocation": layoutSnapshot.dividerLineRanges[index - 1].location]
      )
      addTrackingArea(area)
      sectionIconTrackingAreas.append(area)
    }
  }

  // Adds hover tracking over prompt copy and delete buttons.
  private func addPromptActionTrackingAreas() {
    guard let textStorage else { return }
    let nsString = textStorage.string as NSString
    for range in promptBlockVisualRanges(in: textStorage) {
      guard let blockRect = promptBlockRect(for: range, string: nsString) else { continue }
      let copyArea = NSTrackingArea(
        rect: promptCopyButtonRect(in: blockRect),
        options: [.mouseEnteredAndExited, .activeInActiveApp],
        owner: self,
        userInfo: ["promptLocation": range.location]
      )
      let closeArea = NSTrackingArea(
        rect: promptCloseButtonRect(in: blockRect),
        options: [.mouseEnteredAndExited, .activeInActiveApp],
        owner: self,
        userInfo: ["promptCloseLocation": range.location]
      )
      addTrackingArea(copyArea)
      addTrackingArea(closeArea)
      promptCopyTrackingAreas.append(copyArea)
      promptCloseTrackingAreas.append(closeArea)
    }
  }

  // Shows the pointing hand cursor when hovering a section icon.
  override func mouseEntered(with event: NSEvent) {
    if let location = event.trackingArea?.userInfo?["promptCloseLocation"] as? Int {
      hoveredPromptCloseLocation = location
      setNeedsDisplay(bounds)
      NSCursor.pointingHand.push()
      return
    }
    if let location = event.trackingArea?.userInfo?["promptLocation"] as? Int {
      hoveredPromptCopyLocation = location
      setNeedsDisplay(bounds)
      NSCursor.pointingHand.push()
      return
    }
    if let location = event.trackingArea?.userInfo?["dividerLocation"] as? Int {
      hoveredSectionIconLocation = location
      setNeedsDisplay(bounds)
      NSCursor.pointingHand.push()
      return
    }
    super.mouseEntered(with: event)
  }

  // Restores the default cursor when leaving a section icon.
  override func mouseExited(with event: NSEvent) {
    if event.trackingArea?.userInfo?["promptCloseLocation"] != nil {
      hoveredPromptCloseLocation = nil
      setNeedsDisplay(bounds)
      NSCursor.pop()
      return
    }
    if event.trackingArea?.userInfo?["promptLocation"] != nil {
      hoveredPromptCopyLocation = nil
      setNeedsDisplay(bounds)
      NSCursor.pop()
      return
    }
    if event.trackingArea?.userInfo?["dividerLocation"] != nil {
      hoveredSectionIconLocation = nil
      setNeedsDisplay(bounds)
      NSCursor.pop()
      return
    }
    super.mouseExited(with: event)
  }

  // MARK: - Section Icon Hit Testing

  // Computes fresh icon rects on every call so hit testing never relies on stale cache.
  private func sectionIconHitTest(at point: NSPoint) -> NSRange? {
    guard let layoutSnapshot = sectionLayoutSnapshot() else { return nil }

    for (index, sectionRange) in layoutSnapshot.sections.enumerated() {
      guard index > 0, index - 1 < layoutSnapshot.dividerLineRanges.count else { continue }
      let isLastSection = (index == layoutSnapshot.sections.count - 1)
      guard editorHasVisibleGlyphs(forCharacterRange: sectionRange) || isLastSection else {
        continue
      }

      let divIndex = min(index - 1, layoutSnapshot.dividerMidYs.count - 1)
      let cardTop = layoutSnapshot.dividerMidYs[divIndex] + sectionCardGapOffset
      let cardWidth = bounds.width - (cardHInset * 2)
      let iconRect = NSRect(
        x: cardHInset + cardWidth - sectionIconSize - sectionIconPadding,
        y: cardTop + sectionIconPadding,
        width: sectionIconSize,
        height: sectionIconSize
      )
      let hitRect = iconRect.insetBy(dx: -sectionIconHitPadding, dy: -sectionIconHitPadding)
      if hitRect.contains(point) {
        return layoutSnapshot.dividerLineRanges[index - 1]
      }
    }
    return nil
  }

  // MARK: - Navigation

  // Skips section dividers when arrowing up.
  override func moveUp(_ sender: Any?) {
    super.moveUp(sender)
    _ = editorNormalizeSelectionIfNeeded(prefer: .previous)
  }

  // Skips section dividers when arrowing down.
  override func moveDown(_ sender: Any?) {
    super.moveDown(sender)
    _ = editorNormalizeSelectionIfNeeded(prefer: .next)
  }

  // Sanitizes the replacement range to avoid writing into dividers.
  override func insertText(_ insertString: Any, replacementRange: NSRange) {
    let baseRange = replacementRange.location == NSNotFound ? selectedRange() : replacementRange
    guard baseRange.length == 0 else {
      super.insertText(insertString, replacementRange: baseRange)
      return
    }

    let resolvedLocation = editorResolvedInsertionLocation(
      for: baseRange.location,
      prefer: .nearest
    )
    if resolvedLocation != baseRange.location {
      super.setSelectedRange(NSRange(location: resolvedLocation, length: 0))
    }

    super.insertText(
      insertString,
      replacementRange: NSRange(location: resolvedLocation, length: 0)
    )
  }

  // Custom pasteboard type for preserving markdown structure during app-internal copy/paste.
  private static let markdownPasteboardType = NSPasteboard.PasteboardType("com.sceal.markdown-text")

  // Returns a URL string only when the general pasteboard contains a single standalone link.
  private func pastedURLStringFromGeneralPasteboard() -> String? {
    guard let pastedText = NSPasteboard.general.string(forType: .string) else { return nil }
    let trimmedText = pastedText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedText.isEmpty else { return nil }

    guard
      let detector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue)
    else { return nil }

    let fullRange = NSRange(location: 0, length: (trimmedText as NSString).length)
    guard
      let match = detector.firstMatch(in: trimmedText, options: [], range: fullRange),
      match.range == fullRange,
      match.url != nil
    else { return nil }

    return trimmedText
  }

  private func storedImageAttachment(from pasteboard: NSPasteboard) -> StoredImageAttachment? {
    guard let noteID else { return nil }

    if let imageURL = imageFileURLs(from: pasteboard).first {
      return try? NoteImageAttachmentStore.storeImageFile(
        from: imageURL,
        for: noteID,
        fileManager: imageAttachmentFileManager,
        rootURL: imageAttachmentRootURL
      )
    }

    if let image = NSImage(pasteboard: pasteboard) {
      return try? NoteImageAttachmentStore.storePastedImage(
        image,
        for: noteID,
        fileManager: imageAttachmentFileManager,
        rootURL: imageAttachmentRootURL
      )
    }

    return nil
  }

  private func imageFileURLs(from pasteboard: NSPasteboard) -> [URL] {
    let options: [NSPasteboard.ReadingOptionKey: Any] = [
      .urlReadingFileURLsOnly: true
    ]
    let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: options) ?? []
    return objects.compactMap { object in
      let url: URL?
      if let swiftURL = object as? URL {
        url = swiftURL
      } else if let nsURL = object as? NSURL {
        url = nsURL as URL
      } else {
        url = nil
      }
      guard let url else { return nil }
      return imageFileURLIfSupported(url)
    }
  }

  private func imageFileURLIfSupported(_ url: URL) -> URL? {
    guard
      let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
      type.conforms(to: .image)
    else {
      let knownExtensions = ["png", "jpg", "jpeg", "gif", "tiff", "tif", "heic", "webp"]
      return knownExtensions.contains(url.pathExtension.lowercased()) ? url : nil
    }

    return url
  }

  private func insertImageAttachment(
    _ attachment: StoredImageAttachment,
    replacementRange: NSRange,
    actionName: String
  ) -> Bool {
    let imageMarkdown = MarkdownEditorFormatter.imageMarkdownLine(
      title: attachment.title,
      path: attachment.relativePath
    )
    let markdown = blockMarkdownForInsertion(imageMarkdown, replacing: replacementRange)
    let attributed = MarkdownEditorFormatter.formatForDisplay(
      markdown,
      appearance: appearanceSettings
    )

    return performEditorEdit(
      affectedRange: replacementRange,
      replacementString: attributed.string,
      actionName: actionName
    ) { textStorage in
      let safeLocation = min(replacementRange.location, textStorage.length)
      let safeLength = min(replacementRange.length, max(textStorage.length - safeLocation, 0))
      let safeRange = NSRange(location: safeLocation, length: safeLength)
      textStorage.replaceCharacters(in: safeRange, with: attributed)
      return NSRange(location: safeLocation + attributed.length, length: 0)
    }
  }

  private func blockMarkdownForInsertion(_ markdown: String, replacing range: NSRange) -> String {
    guard let textStorage else { return markdown }
    let nsString = textStorage.string as NSString
    let safeLocation = min(range.location, nsString.length)
    let rangeEnd = min(NSMaxRange(range), nsString.length)
    let needsLeadingNewline =
      safeLocation > 0 && nsString.character(at: safeLocation - 1) != 0x0A
    let needsTrailingNewline =
      rangeEnd < nsString.length && nsString.character(at: rangeEnd) != 0x0A

    return "\(needsLeadingNewline ? "\n" : "")\(markdown)\(needsTrailingNewline ? "\n" : "")"
  }

  // Returns the raw markdown for the current selection if it starts at a line boundary,
  // nil otherwise — partial-line selections don't have reliable line structure.
  private func markdownForCurrentSelection() -> String? {
    let range = selectedRange()
    guard range.length > 0, let textStorage else { return nil }
    let nsString = textStorage.string as NSString
    let lineRange = nsString.lineRange(for: NSRange(location: range.location, length: 0))
    let selected = textStorage.attributedSubstring(from: range)
    return MarkdownEditorFormatter.convertSelectionToMarkdown(
      from: selected,
      preserveBlockStructure: range.location == lineRange.location
    )
  }

  // Copies selection and also writes raw markdown to a custom pasteboard type.
  override func copy(_ sender: Any?) {
    super.copy(sender)
    if let markdown = markdownForCurrentSelection() {
      NSPasteboard.general.addTypes([Self.markdownPasteboardType], owner: nil)
      NSPasteboard.general.setString(markdown, forType: Self.markdownPasteboardType)
      NSPasteboard.general.setString(markdown, forType: .string)
    }
  }

  // Cuts selection and appends the raw markdown to the pasteboard after super writes its types.
  override func cut(_ sender: Any?) {
    // Capture markdown before super.cut() deletes the selection.
    let markdown = markdownForCurrentSelection()
    super.cut(sender)
    if let markdown {
      NSPasteboard.general.addTypes([Self.markdownPasteboardType], owner: nil)
      NSPasteboard.general.setString(markdown, forType: Self.markdownPasteboardType)
      NSPasteboard.general.setString(markdown, forType: .string)
    }
  }

  // Pastes with markdown formatting preserved when content was copied from this editor,
  // otherwise falls back to plain text.
  override func paste(_ sender: Any?) {
    let pasteRange = selectedRange()
    if selectionIsInsidePromptBlock(pasteRange),
      let plainText = NSPasteboard.general.string(forType: .string)
    {
      let attributed = NSAttributedString(
        string: plainText,
        attributes: promptBlockTypingAttributes()
      )
      performEditorEdit(
        affectedRange: pasteRange,
        replacementString: plainText,
        actionName: "Paste"
      ) { textStorage in
        let safeLocation = min(pasteRange.location, textStorage.length)
        let safeLength = min(pasteRange.length, max(textStorage.length - safeLocation, 0))
        let safeRange = NSRange(location: safeLocation, length: safeLength)
        textStorage.replaceCharacters(in: safeRange, with: attributed)
        return NSRange(location: safeLocation + attributed.length, length: 0)
      }
      return
    }

    if let storedImage = storedImageAttachment(from: NSPasteboard.general),
      insertImageAttachment(storedImage, replacementRange: pasteRange, actionName: "Paste Image")
    {
      return
    }

    if pasteRange.length > 0,
      let pastedURL = pastedURLStringFromGeneralPasteboard(),
      performEditorEdit(
        affectedRange: pasteRange,
        actionName: "Paste Link",
        edit: { textStorage in
          let safeLocation = min(pasteRange.location, textStorage.length)
          let safeLength = min(pasteRange.length, max(textStorage.length - safeLocation, 0))
          let safeRange = NSRange(location: safeLocation, length: safeLength)
          guard safeRange.length > 0 else { return nil }

          textStorage.removeAttribute(.link, range: safeRange)
          var attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.linkColor,
            .markdownLinkURL: pastedURL,
          ]
          if let url = URL(string: pastedURL) {
            attrs[.link] = url
          }
          textStorage.addAttributes(attrs, range: safeRange)
          return NSRange(location: NSMaxRange(safeRange), length: 0)
        }
      )
    {
      return
    }

    if let markdown = NSPasteboard.general.string(forType: Self.markdownPasteboardType) {
      let attributed = MarkdownEditorFormatter.formatForDisplay(
        markdown, appearance: appearanceSettings)
      performEditorEdit(
        affectedRange: pasteRange,
        replacementString: attributed.string,
        actionName: "Paste"
      ) { textStorage in
        let safeLocation = min(pasteRange.location, textStorage.length)
        let safeLength = min(pasteRange.length, max(textStorage.length - safeLocation, 0))
        let safeRange = NSRange(location: safeLocation, length: safeLength)
        textStorage.replaceCharacters(in: safeRange, with: attributed)
        return NSRange(location: safeLocation + attributed.length, length: 0)
      }
      return
    }
    guard let plainText = NSPasteboard.general.string(forType: .string) else { return }
    let attributed = MarkdownEditorFormatter.formatForDisplay(
      plainText, appearance: appearanceSettings)
    performEditorEdit(
      affectedRange: pasteRange,
      replacementString: attributed.string,
      actionName: "Paste"
    ) { textStorage in
      let safeLocation = min(pasteRange.location, textStorage.length)
      let safeLength = min(pasteRange.length, max(textStorage.length - safeLocation, 0))
      let safeRange = NSRange(location: safeLocation, length: safeLength)
      textStorage.replaceCharacters(in: safeRange, with: attributed)
      return NSRange(location: safeLocation + attributed.length, length: 0)
    }
  }

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    pasteboardContainsSupportedImage(sender.draggingPasteboard) == false
      ? super.draggingEntered(sender)
      : .copy
  }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    guard let storedImage = storedImageAttachment(from: sender.draggingPasteboard) else {
      return super.performDragOperation(sender)
    }

    let point = convert(sender.draggingLocation, from: nil)
    let insertionLocation = editorCharacterIndex(forViewPoint: point) ?? string.utf16.count
    let insertionRange = NSRange(location: insertionLocation, length: 0)
    setSelectedRange(insertionRange)
    return insertImageAttachment(
      storedImage,
      replacementRange: insertionRange,
      actionName: "Drop Image"
    )
  }

  private func pasteboardContainsSupportedImage(_ pasteboard: NSPasteboard) -> Bool {
    !imageFileURLs(from: pasteboard).isEmpty || NSImage(pasteboard: pasteboard) != nil
  }

  private func selectionIsInsidePromptBlock(_ range: NSRange) -> Bool {
    if typingAttributes[.markdownPromptBlock] as? Bool == true {
      return true
    }

    guard let textStorage, textStorage.length > 0 else { return false }
    if range.length == 0 {
      let beforeLocation = range.location > 0 ? range.location - 1 : nil
      let afterLocation = range.location < textStorage.length ? range.location : nil
      return [beforeLocation, afterLocation].contains { location in
        guard let location else { return false }
        return textStorage.attribute(.markdownPromptBlock, at: location, effectiveRange: nil)
          as? Bool == true
      }
    }

    let safeLocation = min(range.location, textStorage.length)
    let safeLength = min(range.length, max(textStorage.length - safeLocation, 0))
    guard safeLength > 0 else { return false }

    var isPromptBlock = false
    textStorage.enumerateAttribute(
      .markdownPromptBlock,
      in: NSRange(location: safeLocation, length: safeLength),
      options: []
    ) { value, _, stop in
      if value as? Bool == true {
        isPromptBlock = true
        stop.pointee = true
      }
    }
    return isPromptBlock
  }

  private func promptBlockTypingAttributes() -> [NSAttributedString.Key: Any] {
    [
      .font: appearanceSettings.bodyFont,
      .foregroundColor: NSColor.labelColor,
      .paragraphStyle: MarkdownEditorFormatter.promptBlockParagraphStyle(for: appearanceSettings),
      .markdownPromptBlock: true,
    ]
  }

  // MARK: - Keyboard Shortcuts

  // Intercepts Cmd+B for bold and Cmd+[/] for indent/outdent.
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command else {
      return super.performKeyEquivalent(with: event)
    }
    switch event.charactersIgnoringModifiers {
    case "b":
      toggleBoldInSelection()
      return true
    case "[":
      return handleIndentShortcut(increase: false)
    case "]":
      return handleIndentShortcut(increase: true)
    default:
      return super.performKeyEquivalent(with: event)
    }
  }

  // Routes Cmd+[/] to the coordinator's indent handler.
  private func handleIndentShortcut(increase: Bool) -> Bool {
    guard let coordinator = delegate as? MarkdownEditorView.Coordinator else { return false }
    return coordinator.handleListIndent(textView: self, increase: increase)
  }

  // Toggles bold on the current selection, mirroring EditorFormattingToolbar.toggleBold().
  private func toggleBoldInSelection() {
    guard let textStorage else { return }
    let range = selectedRange()
    guard range.length > 0 else { return }

    var allBold = true
    textStorage.enumerateAttribute(.markdownBold, in: range, options: []) { value, _, stop in
      if value as? Bool != true {
        allBold = false
        stop.pointee = true
      }
    }

    performEditorEdit(
      affectedRange: range,
      actionName: allBold ? "Remove Bold" : "Bold"
    ) { textStorage in
      if allBold {
        textStorage.removeAttribute(.markdownBold, range: range)
        textStorage.addAttribute(.font, value: self.appearanceSettings.bodyFont, range: range)
      } else {
        let currentFont =
          textStorage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
          ?? self.appearanceSettings.bodyFont
        let boldFont = NSFontManager.shared.convert(currentFont, toHaveTrait: .boldFontMask)
        textStorage.addAttribute(.font, value: boldFont, range: range)
        textStorage.addAttribute(.markdownBold, value: true, range: range)
      }
      return nil
    }
  }

  // MARK: - Mouse Handling

  // Handles section icon clicks, checkbox toggles, and divider selection.
  override func mouseDown(with event: NSEvent) {
    if window?.firstResponder !== self {
      window?.makeFirstResponder(self)
    }

    guard let textStorage else {
      super.mouseDown(with: event)
      return
    }

    let point = convert(event.locationInWindow, from: nil)

    if let promptRange = promptCloseHitTest(at: point) {
      _ = deletePromptBlock(in: promptRange, textStorage: textStorage)
      return
    }

    if let promptRange = promptCopyHitTest(at: point) {
      copyPromptBlock(in: promptRange, textStorage: textStorage)
      return
    }

    // Section color icon click — computed fresh each time.
    if let dividerRange = sectionIconHitTest(at: point) {
      let cardWidth = bounds.width - (cardHInset * 2)
      let iconRect = NSRect(
        x: cardHInset + cardWidth - sectionIconSize - sectionIconPadding,
        y: point.y - sectionIconSize / 2,
        width: sectionIconSize,
        height: sectionIconSize
      )
      showSectionColorPopover(for: dividerRange, at: iconRect)
      return
    }

    guard let charIndex = editorCharacterIndex(forViewPoint: point) else {
      super.mouseDown(with: event)
      return
    }

    if let imageRange = imageBlockRange(at: charIndex) {
      super.setSelectedRange(imageRange)
      let imageRect =
        editorRectInViewCoordinates(forCharacterRange: imageRange)
        ?? NSRect(origin: point, size: NSSize(width: 1, height: 1))
      showImagePopover(for: imageRange, at: imageRect)
      return
    }

    // Divider line click — resolve to nearest editable side.
    if let dividerSelectionLocation = editorDividerSelectionLocation(
      for: charIndex,
      atViewPoint: point
    ) {
      super.setSelectedRange(NSRange(location: dividerSelectionLocation, length: 0))
      scrollRangeToVisible(NSRange(location: dividerSelectionLocation, length: 0))
      return
    }

    guard charIndex < textStorage.length else {
      super.mouseDown(with: event)
      return
    }

    // Checkbox toggle — allow clicks on the checkbox attachment or the space after it.
    let nsString = string as NSString
    let lineRange = nsString.lineRange(for: NSRange(location: charIndex, length: 0))
    guard charIndex <= lineRange.location + 1 else {
      super.mouseDown(with: event)
      return
    }

    let checkboxIndex = lineRange.location
    guard checkboxIndex < textStorage.length else {
      super.mouseDown(with: event)
      return
    }

    let attrs = textStorage.attributes(at: checkboxIndex, effectiveRange: nil)
    guard let listTypeRaw = attrs[.markdownListType] as? String,
      listTypeRaw == MarkdownListType.checkboxUnchecked.rawValue
        || listTypeRaw == MarkdownListType.checkboxChecked.rawValue
    else {
      super.mouseDown(with: event)
      return
    }

    if editorToggleCheckbox(at: checkboxIndex, appearanceSettings: appearanceSettings) {
      return
    }

    super.mouseDown(with: event)
  }

  // MARK: - Image Popover

  private func imageBlockRange(at location: Int) -> NSRange? {
    guard let textStorage, location >= 0, location < textStorage.length else { return nil }
    var effectiveRange = NSRange(location: 0, length: 0)
    let isImage =
      textStorage.attribute(
        .markdownImageBlock,
        at: location,
        effectiveRange: &effectiveRange
      ) as? Bool == true
    return isImage ? effectiveRange : nil
  }

  private func showImagePopover(for imageRange: NSRange, at imageRect: NSRect) {
    guard let textStorage, imageRange.location < textStorage.length else { return }
    let attrs = textStorage.attributes(at: imageRange.location, effectiveRange: nil)
    guard let path = attrs[.markdownImagePath] as? String else { return }

    let title = attrs[.markdownImageTitle] as? String ?? ""
    let explicitWidth = imageWidthValue(from: attrs[.markdownImageWidth])
    let popover = NSPopover()
    popover.behavior = .transient
    popover.contentSize = NSSize(width: 300, height: 144)

    let controller = EditorImagePopoverViewController(
      title: title,
      explicitWidth: explicitWidth
    ) { [weak self] newTitle, newWidth in
      self?.applyImageChange(
        imageRange: imageRange,
        path: path,
        title: newTitle,
        width: newWidth
      )
    } onRemove: { [weak self] in
      self?.removeImageBlock(imageRange: imageRange)
    }

    popover.contentViewController = controller
    popover.show(relativeTo: imageRect, of: self, preferredEdge: .maxY)
  }

  private func applyImageChange(
    imageRange: NSRange,
    path: String,
    title: String,
    width: CGFloat?
  ) {
    let replacement = MarkdownEditorFormatter.styledImageBlock(
      title: title,
      path: path,
      width: width,
      appearance: appearanceSettings
    )

    _ = performEditorEdit(
      affectedRange: imageRange,
      replacementString: replacement.string,
      actionName: "Edit Image"
    ) { textStorage in
      let safeLocation = min(imageRange.location, textStorage.length)
      let safeLength = min(imageRange.length, max(textStorage.length - safeLocation, 0))
      let safeRange = NSRange(location: safeLocation, length: safeLength)
      textStorage.replaceCharacters(in: safeRange, with: replacement)
      return NSRange(location: safeLocation + replacement.length, length: 0)
    }
  }

  private func removeImageBlock(imageRange: NSRange) {
    guard let textStorage else { return }
    let removalRange = imageLineRemovalRange(for: imageRange, in: textStorage)

    _ = performEditorEdit(
      affectedRange: removalRange,
      replacementString: "",
      actionName: "Remove Image"
    ) { textStorage in
      let safeLocation = min(removalRange.location, textStorage.length)
      let safeLength = min(removalRange.length, max(textStorage.length - safeLocation, 0))
      let safeRange = NSRange(location: safeLocation, length: safeLength)
      textStorage.replaceCharacters(in: safeRange, with: "")
      return NSRange(location: safeRange.location, length: 0)
    }
  }

  private func imageLineRemovalRange(for imageRange: NSRange, in textStorage: NSTextStorage)
    -> NSRange
  {
    let safeLocation = min(imageRange.location, textStorage.length)
    let safeLength = min(imageRange.length, max(textStorage.length - safeLocation, 0))
    let safeRange = NSRange(location: safeLocation, length: safeLength)
    guard safeRange.length > 0 else { return safeRange }

    let nsString = textStorage.string as NSString
    let lineRange = nsString.lineRange(for: safeRange)
    return NSRange(
      location: lineRange.location,
      length: min(lineRange.length, max(textStorage.length - lineRange.location, 0))
    )
  }

  private func imageWidthValue(from value: Any?) -> CGFloat? {
    if let width = value as? CGFloat {
      return width
    }
    if let number = value as? NSNumber {
      return CGFloat(truncating: number)
    }
    return nil
  }

  // MARK: - Section Color Popover

  // Presents the color picker popover for a section divider.
  private func showSectionColorPopover(for dividerRange: NSRange, at iconRect: NSRect) {
    guard let textStorage else { return }
    let attrs = textStorage.attributes(at: dividerRange.location, effectiveRange: nil)

    let currentHeading = attrs[.markdownSectionHeadingColor] as? String
    let currentBullet = attrs[.markdownSectionBulletColor] as? String
    let currentUseSC = attrs[.markdownSectionUseSectionColor] as? Bool ?? true

    let popover = NSPopover()
    popover.behavior = .transient
    popover.contentSize = NSSize(width: 264, height: 208)

    let controller = EditorSectionColorPopoverViewController(
      headingColorName: currentHeading,
      bulletColorName: currentBullet,
      useSectionColor: currentUseSC
    ) { [weak self] newHeading, newBullet, newUseSC in
      self?.applySectionColorChange(
        dividerRange: dividerRange,
        headingColorName: newHeading,
        bulletColorName: newBullet,
        useSectionColor: newUseSC
      )
    }

    popover.contentViewController = controller
    popover.show(relativeTo: iconRect, of: self, preferredEdge: .maxX)
  }

  // Updates the divider's section color attributes and re-applies colors to affected content.
  private func applySectionColorChange(
    dividerRange: NSRange,
    headingColorName: String?,
    bulletColorName: String?,
    useSectionColor: Bool
  ) {
    guard let textStorage else { return }

    let nsString = textStorage.string as NSString
    var trimmed = dividerRange
    if trimmed.length > 0,
      nsString.character(at: trimmed.location + trimmed.length - 1) == 0x0A
    {
      trimmed.length -= 1
    }
    guard trimmed.length > 0, trimmed.location < textStorage.length else { return }

    _ = performEditorEdit(
      affectedRange: trimmed,
      actionName: "Section Colors"
    ) { textStorage in
      if let name = headingColorName {
        textStorage.addAttribute(.markdownSectionHeadingColor, value: name, range: trimmed)
      } else {
        textStorage.removeAttribute(.markdownSectionHeadingColor, range: trimmed)
      }
      if let name = bulletColorName {
        textStorage.addAttribute(.markdownSectionBulletColor, value: name, range: trimmed)
      } else {
        textStorage.removeAttribute(.markdownSectionBulletColor, range: trimmed)
      }
      if useSectionColor {
        textStorage.addAttribute(.markdownSectionUseSectionColor, value: true, range: trimmed)
      } else {
        textStorage.removeAttribute(.markdownSectionUseSectionColor, range: trimmed)
      }
      return nil
    }

    reapplySectionColorsAfterDivider(at: dividerRange)
  }

  // Walks forward from a divider and recolors headings/bullets within that section.
  private func reapplySectionColorsAfterDivider(at dividerRange: NSRange) {
    guard let textStorage else { return }

    let nsString = textStorage.string as NSString
    let dividerAttrs = textStorage.attributes(at: dividerRange.location, effectiveRange: nil)

    let headingColorName = dividerAttrs[.markdownSectionHeadingColor] as? String
    let bulletColorName = dividerAttrs[.markdownSectionBulletColor] as? String
    let useSC = dividerAttrs[.markdownSectionUseSectionColor] as? Bool ?? false

    let headingColor = headingColorName.flatMap { MarkdownEditorFormatter.headingColor(named: $0) }
    let bulletColor: NSColor? = {
      if let n = bulletColorName { return MarkdownEditorFormatter.headingColor(named: n) }
      if let n = headingColorName { return MarkdownEditorFormatter.headingColor(named: n) }
      return nil
    }()

    var lineStart = NSMaxRange(dividerRange)
    while lineStart < nsString.length {
      let lineRange = nsString.lineRange(for: NSRange(location: lineStart, length: 0))
      var trimmed = lineRange
      if trimmed.length > 0,
        nsString.character(at: trimmed.location + trimmed.length - 1) == 0x0A
      {
        trimmed.length -= 1
      }
      guard trimmed.length > 0 else {
        lineStart = NSMaxRange(lineRange)
        continue
      }

      let attrs = textStorage.attributes(at: trimmed.location, effectiveRange: nil)
      if attrs[.markdownSectionDivider] as? Bool == true { break }

      if attrs[.markdownHeadingLevel] != nil, attrs[.markdownHeadingColor] == nil {
        if let color = headingColor {
          textStorage.addAttribute(.foregroundColor, value: color, range: trimmed)
        } else {
          textStorage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: trimmed)
        }
      }

      if useSC, let color = bulletColor,
        let rawType = attrs[.markdownListType] as? String,
        let listType = MarkdownListType(rawValue: rawType)
      {
        switch listType {
        case .bullet:
          textStorage.addAttributes(
            [
              .foregroundColor: color,
              .font: NSFont.systemFont(ofSize: appearanceSettings.bulletSize, weight: .bold),
            ], range: NSRange(location: trimmed.location, length: 1))
        case .checkboxChecked, .checkboxUnchecked:
          let checked = listType == .checkboxChecked
          let newAttachment = NSAttributedString(
            attachment: MarkdownEditorFormatter.checkboxAttachment(checked: checked, color: color))
          let preservedParagraphStyle = attrs[.paragraphStyle]
          let preservedIndentLevel = attrs[.markdownIndentLevel]
          textStorage.replaceCharacters(
            in: NSRange(location: trimmed.location, length: 1), with: newAttachment)
          textStorage.addAttribute(
            .markdownListType, value: rawType,
            range: NSRange(location: trimmed.location, length: 1))
          if let preservedParagraphStyle {
            textStorage.addAttribute(
              .paragraphStyle,
              value: preservedParagraphStyle,
              range: NSRange(location: trimmed.location, length: 1)
            )
          }
          if let preservedIndentLevel {
            textStorage.addAttribute(
              .markdownIndentLevel,
              value: preservedIndentLevel,
              range: NSRange(location: trimmed.location, length: 1)
            )
          }
        case .numbered:
          break
        }
      } else if !useSC,
        let rawType = attrs[.markdownListType] as? String,
        let listType = MarkdownListType(rawValue: rawType)
      {
        switch listType {
        case .bullet:
          textStorage.addAttributes(
            [
              .foregroundColor: MarkdownEditorFormatter.bulletColor(for: appearanceSettings),
              .font: NSFont.systemFont(ofSize: appearanceSettings.bulletSize, weight: .bold),
            ], range: NSRange(location: trimmed.location, length: 1))
        case .checkboxChecked, .checkboxUnchecked:
          let checked = listType == .checkboxChecked
          let newAttachment = NSAttributedString(
            attachment: MarkdownEditorFormatter.checkboxAttachment(
              checked: checked, appearance: appearanceSettings))
          let preservedParagraphStyle = attrs[.paragraphStyle]
          let preservedIndentLevel = attrs[.markdownIndentLevel]
          textStorage.replaceCharacters(
            in: NSRange(location: trimmed.location, length: 1), with: newAttachment)
          textStorage.addAttribute(
            .markdownListType, value: rawType,
            range: NSRange(location: trimmed.location, length: 1))
          if let preservedParagraphStyle {
            textStorage.addAttribute(
              .paragraphStyle,
              value: preservedParagraphStyle,
              range: NSRange(location: trimmed.location, length: 1)
            )
          }
          if let preservedIndentLevel {
            textStorage.addAttribute(
              .markdownIndentLevel,
              value: preservedIndentLevel,
              range: NSRange(location: trimmed.location, length: 1)
            )
          }
        case .numbered:
          break
        }
      }

      lineStart = NSMaxRange(lineRange)
    }

    setNeedsDisplay(bounds)
  }
}
