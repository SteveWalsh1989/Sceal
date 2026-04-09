//
//  MarkdownEditorTextView.swift
//

// Custom TextKit 2 NSTextView subclass handling section cards, divider navigation, and checkboxes.

import AppKit

@MainActor
final class MarkdownEditorTextView: NSTextView {
  private struct SectionLayoutSnapshot {
    let dividerLineRanges: [NSRange]
    let sections: [NSRange]
    let dividerMidYs: [CGFloat]
  }

  var appearanceSettings = NoteAppearanceSettings.default

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

    if clampedLocation > 0 {
      let backwardRange = stride(
        from: min(clampedLocation - 1, textStorage.length - 1),
        through: 0,
        by: -1
      )
      for candidate in backwardRange where canUseTypingAttributes(at: candidate) {
        return candidate
      }
    }

    guard clampedLocation < textStorage.length else { return nil }
    for candidate in clampedLocation..<textStorage.length
    where canUseTypingAttributes(at: candidate) {
      return candidate
    }

    return nil
  }

  // Returns false for divider and horizontal rule positions.
  private func canUseTypingAttributes(at location: Int) -> Bool {
    guard let textStorage, location >= 0, location < textStorage.length else { return false }
    let attributes = textStorage.attributes(at: location, effectiveRange: nil)
    return attributes[.markdownSectionDivider] as? Bool != true
      && attributes[.markdownHorizontalRule] as? Bool != true
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

  // Shows the pointing hand cursor when hovering a section icon.
  override func mouseEntered(with event: NSEvent) {
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

  // Returns the raw markdown for the current selection if it starts at a line boundary,
  // nil otherwise — partial-line selections don't have reliable line structure.
  private func markdownForCurrentSelection() -> String? {
    let range = selectedRange()
    guard range.length > 0, let textStorage else { return nil }
    let nsString = textStorage.string as NSString
    let lineRange = nsString.lineRange(for: NSRange(location: range.location, length: 0))
    guard range.location == lineRange.location else { return nil }
    let selected = textStorage.attributedSubstring(from: range)
    return MarkdownEditorFormatter.convertToMarkdown(from: selected)
  }

  // Copies selection and also writes raw markdown to a custom pasteboard type.
  override func copy(_ sender: Any?) {
    super.copy(sender)
    if let markdown = markdownForCurrentSelection() {
      NSPasteboard.general.addTypes([Self.markdownPasteboardType], owner: nil)
      NSPasteboard.general.setString(markdown, forType: Self.markdownPasteboardType)
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
    }
  }

  // Pastes with markdown formatting preserved when content was copied from this editor,
  // otherwise falls back to plain text.
  override func paste(_ sender: Any?) {
    let pasteRange = selectedRange()
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
    popover.contentSize = NSSize(width: 264, height: 240)

    let controller = EditorSectionColorPopoverViewController(
      headingColorName: currentHeading,
      bulletColorName: currentBullet,
      useSectionColor: currentUseSC
    ) { [weak self, weak popover] newHeading, newBullet, newUseSC in
      popover?.performClose(nil)
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
