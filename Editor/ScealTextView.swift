//
//  ScealTextView.swift
//

// Custom NSTextView subclass handling section card rendering, divider navigation, and checkboxes.

import AppKit
import SwiftUI

// MARK: - Custom NSTextView subclass

enum DividerResolutionPreference {
  case previous
  case next
  case nearest
}

@MainActor class ScealTextView: NSTextView {

  // Accept clicks even when the window is not key (e.g. after popover dismissal).
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  var appearanceSettings = NoteAppearanceSettings.default
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

  private let sectionIconSize: CGFloat = 18
  private let sectionIconPadding: CGFloat = 24
  private let sectionIconHitPadding: CGFloat = 8
  // Tracks which section icon (by divider range location) the mouse is hovering over.
  private var hoveredSectionIconLocation: Int? = nil
  private var sectionIconTrackingAreas: [NSTrackingArea] = []

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

  private var isDarkAppearance: Bool {
    effectiveAppearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
  }

  // Counts section dividers in the text storage.
  var sectionDividerCount: Int {
    guard let textStorage else { return 0 }

    var dividerCount = 0
    textStorage.enumerateAttribute(
      .markdownSectionDivider,
      in: NSRange(location: 0, length: textStorage.length),
      options: []
    ) { value, _, _ in
      if value as? Bool == true {
        dividerCount += 1
      }
    }
    return dividerCount
  }

  // Forces layout recalculation and redraws section card backgrounds.
  func refreshSectionLayout() {
    ensureEditorLayoutForEntireDocument()
    setNeedsDisplay(bounds)
    enclosingScrollView?.contentView.needsDisplay = true
  }

  // Moves the cursor out of a section divider to the nearest editable position.
  @discardableResult
  func normalizeSelectionIfNeeded(prefer preference: DividerResolutionPreference = .nearest) -> Bool
  {
    let currentSelection = selectedRange()
    guard currentSelection.length == 0 else { return false }

    let resolvedLocation = resolvedInsertionLocation(
      for: currentSelection.location,
      prefer: preference
    )
    guard resolvedLocation != currentSelection.location else { return false }

    super.setSelectedRange(NSRange(location: resolvedLocation, length: 0))
    return true
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

  // MARK: - Section Card Backgrounds

  // Draws section card backgrounds and palette icons instead of the default background.
  override func drawBackground(in rect: NSRect) {
    // Don't call super — we draw all backgrounds ourselves so there's
    // no default background bleeding through between cards.

    guard let textStorage = textStorage, let layoutManager = layoutManager,
      let textContainer = textContainer, textStorage.length > 0
    else {
      // Empty: draw one full-height card
      drawSingleCard(in: rect)
      return
    }

    // Find section divider positions
    let fullRange = NSRange(location: 0, length: textStorage.length)
    var dividerLineRanges: [NSRange] = []

    textStorage.enumerateAttribute(.markdownSectionDivider, in: fullRange, options: []) {
      value, range, _ in
      if value as? Bool == true {
        let nsString = textStorage.string as NSString
        dividerLineRanges.append(nsString.lineRange(for: range))
      }
    }

    // Find horizontal rule positions (visible lines, not card-splitting)
    var hrLineRanges: [NSRange] = []
    textStorage.enumerateAttribute(.markdownHorizontalRule, in: fullRange, options: []) {
      value, range, _ in
      if value as? Bool == true {
        let nsString = textStorage.string as NSString
        hrLineRanges.append(nsString.lineRange(for: range))
      }
    }

    // No section dividers → one card covering everything
    if dividerLineRanges.isEmpty {
      drawSingleCard(in: rect)
      drawHorizontalRules(hrLineRanges, in: rect)
      return
    }

    // Build section content ranges (between dividers)
    var sections: [NSRange] = []
    var currentStart = 0

    for divRange in dividerLineRanges {
      if divRange.location > currentStart {
        sections.append(NSRange(location: currentStart, length: divRange.location - currentStart))
      }
      currentStart = NSMaxRange(divRange)
    }
    if currentStart < textStorage.length {
      sections.append(NSRange(location: currentStart, length: textStorage.length - currentStart))
    }

    // Calculate divider midpoints — these define where one card ends and the next begins
    var dividerMidYs: [CGFloat] = []
    for divRange in dividerLineRanges {
      let divGlyphs = layoutManager.glyphRange(
        forCharacterRange: divRange, actualCharacterRange: nil)
      let divRect = layoutManager.boundingRect(forGlyphRange: divGlyphs, in: textContainer)
      let midY = divRect.midY + textContainerOrigin.y
      dividerMidYs.append(midY)
    }

    let viewBottom = max(bounds.height, enclosingScrollView?.contentSize.height ?? bounds.height)

    // Draw a card for each section, bounded by divider midpoints
    for (index, sectionRange) in sections.enumerated() {
      let glyphRange = layoutManager.glyphRange(
        forCharacterRange: sectionRange, actualCharacterRange: nil)
      let isLastSection = (index == sections.count - 1)
      guard glyphRange.length > 0 || isLastSection else { continue }

      let cardTop: CGFloat
      if index == 0 {
        cardTop = 0
      } else {
        let divIndex = min(index - 1, dividerMidYs.count - 1)
        cardTop = dividerMidYs[divIndex] + sectionCardGapOffset
      }

      let cardBottom: CGFloat
      if index == sections.count - 1 {
        cardBottom = viewBottom
      } else {
        let divIndex = min(index, dividerMidYs.count - 1)
        cardBottom = dividerMidYs[divIndex] - sectionCardGapOffset
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

      // Draw palette icon for divider-defined sections (index >= 1).
      if index > 0, index - 1 < dividerLineRanges.count {
        let iconRect = NSRect(
          x: cardRect.maxX - sectionIconSize - sectionIconPadding,
          y: cardRect.minY + sectionIconPadding,
          width: sectionIconSize,
          height: sectionIconSize
        )
        let isHovered = hoveredSectionIconLocation == dividerLineRanges[index - 1].location
        drawSectionIcon(in: iconRect, hovered: isHovered)
      }
    }
    drawHorizontalRules(hrLineRanges, in: rect)
  }

  // Draws a single full-height card when there are no section dividers.
  private func drawSingleCard(in rect: NSRect) {
    let fullHeight = max(bounds.height, enclosingScrollView?.contentSize.height ?? bounds.height)
    let cardRect = NSRect(
      x: cardHInset, y: 0, width: bounds.width - cardHInset * 2, height: fullHeight)
    guard cardRect.intersects(rect) else { return }
    let path = NSBezierPath(roundedRect: cardRect, xRadius: cardRadius, yRadius: cardRadius)
    cardColor.setFill()
    path.fill()
  }

  // Draws a thin visible line for each standard markdown horizontal rule (`---`).
  private func drawHorizontalRules(_ ranges: [NSRange], in rect: NSRect) {
    guard let layoutManager = layoutManager, let textContainer = textContainer,
      !ranges.isEmpty
    else { return }

    let lineInset: CGFloat = 24
    let dividerColor =
      MarkdownStyler.accentColor(for: appearanceSettings).withAlphaComponent(
        isDarkAppearance ? 0.52 : 0.44)
    dividerColor.setFill()

    for range in ranges {
      let glyphRange = layoutManager.glyphRange(
        forCharacterRange: range, actualCharacterRange: nil)
      let lineRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
      let midY = lineRect.midY + textContainerOrigin.y

      let hrRect = NSRect(
        x: lineInset,
        y: midY,
        width: bounds.width - (lineInset * 2),
        height: 1
      )

      guard hrRect.intersects(rect) else { continue }
      hrRect.fill()
    }
  }

  // Draws the small palette icon — faint by default, full opacity on hover.
  private func drawSectionIcon(in rect: NSRect, hovered: Bool) {
    let color: NSColor =
      hovered
      ? .secondaryLabelColor
      : .quaternaryLabelColor
    guard
      let image = NSImage(
        systemSymbolName: "paintpalette",
        accessibilityDescription: "Section colors")?
        .withSymbolConfiguration(
          NSImage.SymbolConfiguration(pointSize: sectionIconSize, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color])))
    else { return }
    image.draw(
      in: rect,
      from: .zero,
      operation: .sourceOver,
      fraction: 1.0,
      respectFlipped: true,
      hints: nil
    )
  }

  // MARK: - Section Icon Hover Tracking

  // Creates hover tracking areas over each section's palette icon.
  override func updateTrackingAreas() {
    super.updateTrackingAreas()

    // Remove old tracking areas.
    for area in sectionIconTrackingAreas {
      removeTrackingArea(area)
    }
    sectionIconTrackingAreas.removeAll()

    guard let textStorage, let layoutManager, let textContainer,
      textStorage.length > 0
    else { return }

    let fullRange = NSRange(location: 0, length: textStorage.length)
    var dividerLineRanges: [NSRange] = []
    textStorage.enumerateAttribute(.markdownSectionDivider, in: fullRange, options: []) {
      value, range, _ in
      if value as? Bool == true {
        dividerLineRanges.append((textStorage.string as NSString).lineRange(for: range))
      }
    }
    guard !dividerLineRanges.isEmpty else { return }

    var sections: [NSRange] = []
    var currentStart = 0
    for divRange in dividerLineRanges {
      if divRange.location > currentStart {
        sections.append(NSRange(location: currentStart, length: divRange.location - currentStart))
      }
      currentStart = NSMaxRange(divRange)
    }
    if currentStart < textStorage.length {
      sections.append(NSRange(location: currentStart, length: textStorage.length - currentStart))
    }

    var dividerMidYs: [CGFloat] = []
    for divRange in dividerLineRanges {
      let glyphs = layoutManager.glyphRange(
        forCharacterRange: divRange, actualCharacterRange: nil)
      let rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
      dividerMidYs.append(rect.midY + textContainerOrigin.y)
    }

    for (index, sectionRange) in sections.enumerated() {
      guard index > 0, index - 1 < dividerLineRanges.count else { continue }
      let glyphRange = layoutManager.glyphRange(
        forCharacterRange: sectionRange, actualCharacterRange: nil)
      let isLastSection = (index == sections.count - 1)
      guard glyphRange.length > 0 || isLastSection else { continue }

      let divIndex = min(index - 1, dividerMidYs.count - 1)
      let cardTop = dividerMidYs[divIndex] + sectionCardGapOffset
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
        userInfo: ["dividerLocation": dividerLineRanges[index - 1].location]
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
    guard let textStorage, let layoutManager, let textContainer,
      textStorage.length > 0
    else { return nil }

    let fullRange = NSRange(location: 0, length: textStorage.length)
    var dividerLineRanges: [NSRange] = []
    textStorage.enumerateAttribute(.markdownSectionDivider, in: fullRange, options: []) {
      value, range, _ in
      if value as? Bool == true {
        let nsString = textStorage.string as NSString
        dividerLineRanges.append(nsString.lineRange(for: range))
      }
    }
    guard !dividerLineRanges.isEmpty else { return nil }

    // Build section ranges (content between dividers).
    var sections: [NSRange] = []
    var currentStart = 0
    for divRange in dividerLineRanges {
      if divRange.location > currentStart {
        sections.append(NSRange(location: currentStart, length: divRange.location - currentStart))
      }
      currentStart = NSMaxRange(divRange)
    }
    if currentStart < textStorage.length {
      sections.append(NSRange(location: currentStart, length: textStorage.length - currentStart))
    }

    // Calculate divider midpoints.
    var dividerMidYs: [CGFloat] = []
    for divRange in dividerLineRanges {
      let divGlyphs = layoutManager.glyphRange(
        forCharacterRange: divRange, actualCharacterRange: nil)
      let divRect = layoutManager.boundingRect(forGlyphRange: divGlyphs, in: textContainer)
      dividerMidYs.append(divRect.midY + textContainerOrigin.y)
    }

    // Check each divider-defined section (index >= 1) for an icon hit.
    for (index, sectionRange) in sections.enumerated() {
      guard index > 0, index - 1 < dividerLineRanges.count else { continue }
      let glyphRange = layoutManager.glyphRange(
        forCharacterRange: sectionRange, actualCharacterRange: nil)
      let isLastSection = (index == sections.count - 1)
      guard glyphRange.length > 0 || isLastSection else { continue }

      let divIndex = min(index - 1, dividerMidYs.count - 1)
      let cardTop = dividerMidYs[divIndex] + sectionCardGapOffset

      let cardWidth = bounds.width - (cardHInset * 2)
      let iconRect = NSRect(
        x: cardHInset + cardWidth - sectionIconSize - sectionIconPadding,
        y: cardTop + sectionIconPadding,
        width: sectionIconSize,
        height: sectionIconSize
      )

      // Use a padded rect for a more forgiving click target.
      let hitRect = iconRect.insetBy(dx: -sectionIconHitPadding, dy: -sectionIconHitPadding)
      if hitRect.contains(point) {
        return dividerLineRanges[index - 1]
      }
    }

    return nil
  }

  // MARK: - Paste

  // Skips section dividers when arrowing up.
  override func moveUp(_ sender: Any?) {
    super.moveUp(sender)
    skipSectionDividers(direction: .previous, sender: sender)
  }

  // Skips section dividers when arrowing down.
  override func moveDown(_ sender: Any?) {
    super.moveDown(sender)
    skipSectionDividers(direction: .next, sender: sender)
  }

  // Sanitizes the replacement range to avoid writing into dividers.
  override func insertText(_ insertString: Any, replacementRange: NSRange) {
    let targetRange = sanitizedReplacementRange(replacementRange)
    super.insertText(insertString, replacementRange: targetRange)
  }

  // Pastes as plain text only, stripping any rich formatting.
  override func paste(_ sender: Any?) {
    guard let plainText = NSPasteboard.general.string(forType: .string) else { return }
    insertText(plainText, replacementRange: selectedRange())
  }

  // MARK: - Keyboard Shortcuts

  // Intercepts Cmd+B to toggle bold on the selection.
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command else {
      return super.performKeyEquivalent(with: event)
    }
    switch event.charactersIgnoringModifiers {
    case "b":
      toggleBoldInSelection()
      return true
    default:
      return super.performKeyEquivalent(with: event)
    }
  }

  // Toggles bold on the current selection, mirroring FormattingToolbar.toggleBold()
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

  // MARK: - Checkbox Click

  // Handles section icon clicks, checkbox toggles, and divider selection.
  override func mouseDown(with event: NSEvent) {
    // Always reclaim first-responder on click so the cursor is placeable after
    // focus was lost to a popover, sidebar interaction, or programmatic edit.
    if window?.firstResponder !== self {
      window?.makeFirstResponder(self)
    }

    guard let textStorage = textStorage, let layoutManager = layoutManager,
      let textContainer = textContainer
    else {
      super.mouseDown(with: event)
      return
    }

    let point = convert(event.locationInWindow, from: nil)

    // Section color icon click — computed fresh each time, no stale cache.
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

    let textPoint = NSPoint(
      x: point.x - textContainerInset.width,
      y: point.y - textContainerInset.height)
    let charIndex = layoutManager.characterIndex(
      for: textPoint, in: textContainer,
      fractionOfDistanceBetweenInsertionPoints: nil)

    if let dividerSelectionLocation = dividerSelectionLocation(
      for: charIndex,
      at: textPoint,
      layoutManager: layoutManager,
      textContainer: textContainer
    ) {
      super.setSelectedRange(NSRange(location: dividerSelectionLocation, length: 0))
      scrollRangeToVisible(NSRange(location: dividerSelectionLocation, length: 0))
      return
    }

    guard charIndex < textStorage.length else {
      super.mouseDown(with: event)
      return
    }

    let attrs = textStorage.attributes(at: charIndex, effectiveRange: nil)
    guard let listTypeRaw = attrs[.markdownListType] as? String,
      listTypeRaw == MarkdownListType.checkboxUnchecked.rawValue
        || listTypeRaw == MarkdownListType.checkboxChecked.rawValue
    else {
      super.mouseDown(with: event)
      return
    }

    let nsString = string as NSString
    let lineRange = nsString.lineRange(for: NSRange(location: charIndex, length: 0))
    guard charIndex == lineRange.location else {
      super.mouseDown(with: event)
      return
    }

    toggleCheckbox(at: charIndex)
  }

  // Toggles a checkbox between checked and unchecked states.
  private func toggleCheckbox(at charIndex: Int) {
    guard let textStorage = textStorage else { return }
    let nsString = textStorage.string as NSString
    let lineRange = nsString.lineRange(for: NSRange(location: charIndex, length: 0))
    var textRange = lineRange
    if textRange.length > 0
      && nsString.character(at: textRange.location + textRange.length - 1) == 0x0A
    {
      textRange.length -= 1
    }

    let currentTypeRaw =
      textStorage.attribute(.markdownListType, at: charIndex, effectiveRange: nil) as? String
    let isChecked = currentTypeRaw == MarkdownListType.checkboxChecked.rawValue

    _ = performEditorEdit(
      affectedRange: textRange,
      actionName: isChecked ? "Uncheck Item" : "Check Item"
    ) { textStorage in
      let newAttachment = MarkdownStyler.checkboxAttachment(
        checked: !isChecked,
        appearance: appearanceSettings
      )
      let attachmentStr = NSAttributedString(attachment: newAttachment)
      textStorage.replaceCharacters(
        in: NSRange(location: charIndex, length: 1),
        with: attachmentStr
      )

      let updatedNSString = textStorage.string as NSString
      let updatedLineRange = updatedNSString.lineRange(
        for: NSRange(location: charIndex, length: 0))
      var updatedTextRange = updatedLineRange
      if updatedTextRange.length > 0
        && updatedNSString.character(
          at: updatedTextRange.location + updatedTextRange.length - 1) == 0x0A
      {
        updatedTextRange.length -= 1
      }

      let newType: MarkdownListType = isChecked ? .checkboxUnchecked : .checkboxChecked
      textStorage.addAttribute(
        .markdownListType,
        value: newType.rawValue,
        range: updatedTextRange
      )
      textStorage.addAttribute(
        .paragraphStyle,
        value: MarkdownStyler.listParagraphStyle(for: appearanceSettings),
        range: updatedTextRange
      )

      let contentStart = min(charIndex + 2, updatedTextRange.location + updatedTextRange.length)
      let contentLength = (updatedTextRange.location + updatedTextRange.length) - contentStart
      if contentLength > 0 {
        let contentRange = NSRange(location: contentStart, length: contentLength)
        if isChecked {
          textStorage.removeAttribute(.strikethroughStyle, range: contentRange)
        } else {
          textStorage.addAttribute(
            .strikethroughStyle,
            value: NSUnderlineStyle.single.rawValue,
            range: contentRange
          )
        }
      }
      return nil
    }
  }

  // Auto-advances past divider lines after arrow key navigation.
  private func skipSectionDividers(direction: DividerResolutionPreference, sender: Any?) {
    guard selectedRange().length == 0 else { return }

    var previousLocation = selectedRange().location
    var safetyCounter = 0

    while sectionDividerLineRange(containingInsertionLocation: selectedRange().location) != nil,
      safetyCounter < 8
    {
      if direction == .previous {
        super.moveUp(sender)
      } else {
        super.moveDown(sender)
      }

      let currentLocation = selectedRange().location
      if currentLocation == previousLocation { break }
      previousLocation = currentLocation
      safetyCounter += 1
    }

    _ = normalizeSelectionIfNeeded(prefer: direction)
  }

  // Adjusts a replacement range so it doesn't cross into a divider.
  private func sanitizedReplacementRange(_ replacementRange: NSRange) -> NSRange {
    let baseRange = replacementRange.location == NSNotFound ? selectedRange() : replacementRange
    guard baseRange.length == 0 else { return baseRange }

    let resolvedLocation = resolvedInsertionLocation(for: baseRange.location, prefer: .nearest)
    if resolvedLocation != baseRange.location {
      super.setSelectedRange(NSRange(location: resolvedLocation, length: 0))
    }
    return NSRange(location: resolvedLocation, length: 0)
  }

  // Detects when a click lands on a divider line.
  private func dividerSelectionLocation(
    for charIndex: Int,
    at textPoint: NSPoint,
    layoutManager: NSLayoutManager,
    textContainer: NSTextContainer
  ) -> Int? {
    guard let textStorage, textStorage.length > 0 else { return nil }

    let clampedIndex = min(max(charIndex, 0), textStorage.length - 1)
    let candidateIndexes = [clampedIndex, max(clampedIndex - 1, 0)]

    for candidateIndex in candidateIndexes {
      let lineRange = (string as NSString).lineRange(
        for: NSRange(location: candidateIndex, length: 0))
      guard lineHasSectionDivider(lineRange) else { continue }

      let glyphRange = layoutManager.glyphRange(
        forCharacterRange: lineRange,
        actualCharacterRange: nil
      )
      let dividerRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
      guard dividerRect.insetBy(dx: -textContainerInset.width, dy: -6).contains(textPoint) else {
        continue
      }

      let upperHalf = isFlipped ? textPoint.y < dividerRect.midY : textPoint.y > dividerRect.midY
      let preference: DividerResolutionPreference = upperHalf ? .previous : .next
      return resolvedInsertionLocation(for: candidateIndex, prefer: preference)
    }

    return nil
  }

  // Resolves a divider-crossing cursor to the nearest editable location.
  private func resolvedInsertionLocation(
    for proposedLocation: Int,
    prefer preference: DividerResolutionPreference
  ) -> Int {
    guard
      let dividerLineRange = sectionDividerLineRange(containingInsertionLocation: proposedLocation)
    else {
      return min(max(proposedLocation, 0), textStorage?.length ?? 0)
    }

    let previousLocation = previousEditableInsertionLocation(before: dividerLineRange)
    let nextLocation = nextEditableInsertionLocation(after: dividerLineRange)

    switch preference {
    case .previous:
      return previousLocation ?? nextLocation ?? dividerLineRange.location
    case .next:
      return nextLocation ?? previousLocation ?? dividerLineRange.location
    case .nearest:
      let clampedLocation = min(max(proposedLocation, 0), textStorage?.length ?? 0)
      switch (previousLocation, nextLocation) {
      case (let previous?, let next?):
        return abs(clampedLocation - previous) <= abs(next - clampedLocation) ? previous : next
      case (let previous?, nil):
        return previous
      case (nil, let next?):
        return next
      default:
        return dividerLineRange.location
      }
    }
  }

  // Finds the last editable position before a divider.
  private func previousEditableInsertionLocation(before dividerLineRange: NSRange) -> Int? {
    guard dividerLineRange.location > 0 else { return nil }

    let nsString = string as NSString
    var searchLocation = dividerLineRange.location - 1

    while searchLocation >= 0 {
      let lineRange = nsString.lineRange(for: NSRange(location: searchLocation, length: 0))
      if lineHasSectionDivider(lineRange) {
        guard lineRange.location > 0 else { return nil }
        searchLocation = lineRange.location - 1
        continue
      }

      return NSMaxRange(trimmedLineRange(from: lineRange, in: nsString))
    }

    return nil
  }

  // Finds the first editable position after a divider.
  private func nextEditableInsertionLocation(after dividerLineRange: NSRange) -> Int? {
    let nsString = string as NSString
    var searchLocation = NSMaxRange(dividerLineRange)

    while searchLocation < nsString.length {
      let lineRange = nsString.lineRange(for: NSRange(location: searchLocation, length: 0))
      if !lineHasSectionDivider(lineRange) {
        return lineRange.location
      }
      searchLocation = NSMaxRange(lineRange)
    }

    return nsString.length
  }

  // Returns the line range of the divider at the given location, if any.
  private func sectionDividerLineRange(containingInsertionLocation location: Int) -> NSRange? {
    guard let textStorage, textStorage.length > 0 else { return nil }

    let nsString = string as NSString
    let clampedLocation = min(max(location, 0), textStorage.length)
    // Allow the caret to sit after a divider's trailing newline when the divider is the last line.
    if clampedLocation == textStorage.length { return nil }
    let lineRange = nsString.lineRange(for: NSRange(location: clampedLocation, length: 0))
    return lineHasSectionDivider(lineRange) ? lineRange : nil
  }

  // Checks if a line range carries the section divider attribute.
  private func lineHasSectionDivider(_ lineRange: NSRange) -> Bool {
    lineHasAttribute(.markdownSectionDivider, in: lineRange)
  }

  // Returns false for divider and horizontal rule positions.
  private func canUseTypingAttributes(at location: Int) -> Bool {
    guard let textStorage, location >= 0, location < textStorage.length else { return false }

    let attributes = textStorage.attributes(at: location, effectiveRange: nil)
    return attributes[.markdownSectionDivider] as? Bool != true
      && attributes[.markdownHorizontalRule] as? Bool != true
  }

  // Checks if the first character of a line has a given attribute.
  private func lineHasAttribute(_ key: NSAttributedString.Key, in lineRange: NSRange) -> Bool {
    guard let textStorage else { return false }

    let trimmedRange = trimmedLineRange(from: lineRange, in: string as NSString)
    guard trimmedRange.length > 0, trimmedRange.location < textStorage.length else { return false }

    return textStorage.attribute(key, at: trimmedRange.location, effectiveRange: nil) as? Bool
      == true
  }

  // Strips the trailing newline from a line range.
  private func trimmedLineRange(from lineRange: NSRange, in nsString: NSString) -> NSRange {
    var trimmedRange = lineRange
    if trimmedRange.length > 0,
      nsString.character(at: trimmedRange.location + trimmedRange.length - 1) == 0x0A
    {
      trimmedRange.length -= 1
    }
    return trimmedRange
  }

  // MARK: - Section Color Popover

  // Presents the color picker popover for a section divider.
  private func showSectionColorPopover(for dividerRange: NSRange, at iconRect: NSRect) {
    guard let textStorage else { return }
    let attrs = textStorage.attributes(at: dividerRange.location, effectiveRange: nil)

    let currentHeading = attrs[.markdownSectionHeadingColor] as? String
    let currentBullet = attrs[.markdownSectionBulletColor] as? String
    let currentUseSC = attrs[.markdownSectionUseSectionColor] as? Bool ?? false

    let popover = NSPopover()
    popover.behavior = .transient
    popover.contentSize = NSSize(width: 264, height: 240)

    let controller = SectionColorPopoverViewController(
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

    // Find the character range for just the divider marker (trimmed).
    let nsString = textStorage.string as NSString
    let trimmed = trimmedLineRange(from: dividerRange, in: nsString)
    guard trimmed.length > 0, trimmed.location < textStorage.length else { return }

    _ = performEditorEdit(
      affectedRange: trimmed,
      actionName: "Section Colors"
    ) { textStorage in
      // Set or remove section color attributes on the divider.
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

    // Re-apply section colors to content lines between this divider and the next.
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

    let headingColor = headingColorName.flatMap { MarkdownStyler.headingColor(named: $0) }
    let bulletColor: NSColor? = {
      if let n = bulletColorName { return MarkdownStyler.headingColor(named: n) }
      if let n = headingColorName { return MarkdownStyler.headingColor(named: n) }
      return nil
    }()

    // Walk forward from the end of the divider line to the next divider or document end.
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

      // Stop at the next section divider.
      if attrs[.markdownSectionDivider] as? Bool == true { break }

      // Heading without explicit hcolor
      if attrs[.markdownHeadingLevel] != nil, attrs[.markdownHeadingColor] == nil {
        if let color = headingColor {
          textStorage.addAttribute(.foregroundColor, value: color, range: trimmed)
        } else {
          textStorage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: trimmed)
        }
      }

      // Bullet/checkbox
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
            attachment: MarkdownStyler.checkboxAttachment(checked: checked, color: color))
          textStorage.replaceCharacters(
            in: NSRange(location: trimmed.location, length: 1), with: newAttachment)
        case .numbered:
          break
        }
      } else if !useSC,
        let rawType = attrs[.markdownListType] as? String,
        let listType = MarkdownListType(rawValue: rawType)
      {
        // Reset to global defaults when useSectionColor is off.
        switch listType {
        case .bullet:
          textStorage.addAttributes(
            [
              .foregroundColor: MarkdownStyler.bulletColor(for: appearanceSettings),
              .font: NSFont.systemFont(ofSize: appearanceSettings.bulletSize, weight: .bold),
            ], range: NSRange(location: trimmed.location, length: 1))
        case .checkboxChecked, .checkboxUnchecked:
          let checked = listType == .checkboxChecked
          let newAttachment = NSAttributedString(
            attachment: MarkdownStyler.checkboxAttachment(
              checked: checked, appearance: appearanceSettings))
          textStorage.replaceCharacters(
            in: NSRange(location: trimmed.location, length: 1), with: newAttachment)
        case .numbered:
          break
        }
      }

      lineStart = NSMaxRange(lineRange)
    }

    setNeedsDisplay(bounds)
  }
}

// MARK: - Section Color Popover

// Popover for picking section heading and bullet colors.
@MainActor private class SectionColorPopoverViewController: NSViewController {

  private let currentHeadingColorName: String?
  private let currentBulletColorName: String?
  private let currentUseSectionColor: Bool
  private let onApply: (String?, String?, Bool) -> Void

  private var selectedHeadingColor: String?
  private var selectedBulletColor: String?
  private var useSectionColorToggle: Bool

  init(
    headingColorName: String?,
    bulletColorName: String?,
    useSectionColor: Bool,
    onApply: @escaping (String?, String?, Bool) -> Void
  ) {
    self.currentHeadingColorName = headingColorName
    self.currentBulletColorName = bulletColorName
    self.currentUseSectionColor = useSectionColor
    self.onApply = onApply
    self.selectedHeadingColor = headingColorName
    self.selectedBulletColor = bulletColorName
    self.useSectionColorToggle = useSectionColor
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  override func loadView() {
    let container = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 240))

    var y: CGFloat = 220

    // Title
    let title = makeLabel("Section Colors", bold: true)
    title.frame.origin = NSPoint(x: 16, y: y - 18)
    container.addSubview(title)
    y -= 34

    // Heading Color
    let headingLabel = makeLabel("Heading Color")
    headingLabel.frame.origin = NSPoint(x: 16, y: y - 14)
    container.addSubview(headingLabel)
    y -= 28

    let headingSwatches = makeSwatchRow(
      selected: selectedHeadingColor,
      action: #selector(headingSwatchClicked(_:)),
      yOrigin: y - 22
    )
    for swatch in headingSwatches { container.addSubview(swatch) }
    y -= 36

    // Bullet Color
    let bulletLabel = makeLabel("Bullet Color")
    bulletLabel.frame.origin = NSPoint(x: 16, y: y - 14)
    container.addSubview(bulletLabel)
    y -= 28

    let bulletSwatches = makeSwatchRow(
      selected: selectedBulletColor,
      action: #selector(bulletSwatchClicked(_:)),
      yOrigin: y - 22
    )
    for swatch in bulletSwatches { container.addSubview(swatch) }
    y -= 36

    // Use section color toggle
    let toggle = NSButton(
      checkboxWithTitle: "Use section color for bullets & checkboxes",
      target: self,
      action: #selector(toggleChanged(_:))
    )
    toggle.state = useSectionColorToggle ? .on : .off
    toggle.font = NSFont.systemFont(ofSize: 11)
    toggle.sizeToFit()
    toggle.frame.origin = NSPoint(x: 16, y: y - 18)
    container.addSubview(toggle)
    y -= 32

    // Apply button
    let applyBtn = NSButton(title: "Apply", target: self, action: #selector(applyClicked(_:)))
    applyBtn.bezelStyle = .rounded
    applyBtn.keyEquivalent = "\r"
    applyBtn.sizeToFit()
    let swatchRowTrailingX =
      16 + 36 + 4 + CGFloat(ScealPalette.colors.count) * 20 + CGFloat(
        max(ScealPalette.colors.count - 1, 0)) * 4
    applyBtn.frame.origin = NSPoint(x: swatchRowTrailingX - applyBtn.frame.width, y: 8)
    container.addSubview(applyBtn)

    self.view = container
  }

  private func makeLabel(_ text: String, bold: Bool = false) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font =
      bold
      ? NSFont.systemFont(ofSize: 13, weight: .semibold)
      : NSFont.systemFont(ofSize: 11)
    label.sizeToFit()
    return label
  }

  private func makeSwatchRow(
    selected: String?,
    action: Selector,
    yOrigin: CGFloat
  ) -> [NSView] {
    var views: [NSView] = []
    let swatchSize: CGFloat = 20
    let spacing: CGFloat = 4
    var x: CGFloat = 16

    // "None" button
    let noneBtn = NSButton(frame: NSRect(x: x, y: yOrigin, width: 36, height: swatchSize))
    noneBtn.title = "–"
    noneBtn.bezelStyle = .rounded
    noneBtn.isBordered = selected == nil
    noneBtn.tag = -1
    noneBtn.target = self
    noneBtn.action = action
    noneBtn.toolTip = "None"
    views.append(noneBtn)
    x += 36 + spacing

    for (idx, preset) in ScealPalette.colors.enumerated() {
      let btn = NSButton(frame: NSRect(x: x, y: yOrigin, width: swatchSize, height: swatchSize))
      btn.wantsLayer = true
      btn.layer?.cornerRadius = swatchSize / 2
      btn.layer?.backgroundColor = preset.color.cgColor
      btn.isBordered = false
      btn.title = ""
      btn.tag = idx
      btn.target = self
      btn.action = action
      btn.toolTip = preset.name

      if preset.name == selected {
        btn.layer?.borderWidth = 2
        btn.layer?.borderColor = NSColor.controlAccentColor.cgColor
      }

      views.append(btn)
      x += swatchSize + spacing
    }

    return views
  }

  @objc private func headingSwatchClicked(_ sender: NSButton) {
    selectedHeadingColor = sender.tag == -1 ? nil : ScealPalette.colors[sender.tag].name
    rebuildSwatches()
  }

  @objc private func bulletSwatchClicked(_ sender: NSButton) {
    selectedBulletColor = sender.tag == -1 ? nil : ScealPalette.colors[sender.tag].name
    rebuildSwatches()
  }

  @objc private func toggleChanged(_ sender: NSButton) {
    useSectionColorToggle = sender.state == .on
  }

  @objc private func applyClicked(_ sender: NSButton) {
    onApply(selectedHeadingColor, selectedBulletColor, useSectionColorToggle)
  }

  private func rebuildSwatches() {
    // Rebuild view to update selection rings — simple and sufficient for a small popover.
    guard isViewLoaded else { return }
    let frame = view.frame
    loadView()
    view.frame = frame
  }
}
