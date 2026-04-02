//
//  MarkdownTextView.swift
//  dayra
//
//

import AppKit
import SwiftUI

struct MarkdownTextView: NSViewRepresentable {
  let noteID: DayNote.ID
  @Binding var text: String
  let appearanceSettings: NoteAppearanceSettings

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  func makeNSView(context: Context) -> NSScrollView {
    let textView = DayraTextView()
    textView.appearanceSettings = appearanceSettings
    textView.isRichText = true
    textView.isEditable = true
    textView.isSelectable = true
    textView.font = appearanceSettings.bodyFont
    textView.drawsBackground = false
    textView.allowsUndo = true
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isAutomaticTextReplacementEnabled = false
    textView.isAutomaticSpellingCorrectionEnabled = false
    // Keep the active selection visible without hiding attributed foreground colors.
    textView.selectedTextAttributes = [
      .backgroundColor: NSColor.selectedTextBackgroundColor.withAlphaComponent(0.28)
    ]
    textView.textContainerInset = NSSize(width: 22, height: 22)
    textView.typingAttributes = MarkdownStyler.baseTypingAttributes(for: appearanceSettings)
    textView.delegate = context.coordinator
    context.coordinator.toolbar.appearanceSettings = appearanceSettings

    textView.textContainer?.widthTracksTextView = true
    textView.textContainer?.heightTracksTextView = false
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.autoresizingMask = [.width]
    textView.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

    let scrollView = NSScrollView()
    scrollView.documentView = textView
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.drawsBackground = false

    // Load initial content
    let displayString = MarkdownStyler.formatForDisplay(text, appearance: appearanceSettings)
    textView.textStorage?.setAttributedString(displayString)
    context.coordinator.lastPushedMarkdown = text
    context.coordinator.lastAppliedAppearance = appearanceSettings
    context.coordinator.lastNoteID = noteID

    // Ensure text view fills at least the scroll view height
    textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)

    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    guard !context.coordinator.isUpdating else { return }
    guard let textView = scrollView.documentView as? NSTextView else { return }
    context.coordinator.parent = self
    context.coordinator.toolbar.appearanceSettings = appearanceSettings

    // Keep text view filling the scroll view height
    let minH = scrollView.contentSize.height
    if textView.minSize.height != minH {
      textView.minSize = NSSize(width: 0, height: minH)
    }

    let noteChanged = noteID != context.coordinator.lastNoteID
    let textChanged = text != context.coordinator.lastPushedMarkdown
    let appearanceChanged = appearanceSettings != context.coordinator.lastAppliedAppearance
    guard noteChanged || textChanged || appearanceChanged else { return }

    context.coordinator.isUpdating = true
    let selectedRange = clampedRange(textView.selectedRange(), maxLength: text.utf16.count)
    let visibleOrigin = scrollView.contentView.bounds.origin
    if let dayraTextView = textView as? DayraTextView {
      dayraTextView.appearanceSettings = appearanceSettings
    }
    textView.font = appearanceSettings.bodyFont
    textView.typingAttributes = MarkdownStyler.baseTypingAttributes(for: appearanceSettings)
    let displayString = MarkdownStyler.formatForDisplay(text, appearance: appearanceSettings)
    textView.textStorage?.setAttributedString(displayString)
    context.coordinator.lastPushedMarkdown = text
    context.coordinator.lastAppliedAppearance = appearanceSettings
    context.coordinator.lastNoteID = noteID
    textView.setSelectedRange(clampedRange(selectedRange, maxLength: textView.string.utf16.count))
    scrollView.contentView.scroll(to: visibleOrigin)
    scrollView.reflectScrolledClipView(scrollView.contentView)
    context.coordinator.isUpdating = false
  }

  private func clampedRange(_ range: NSRange, maxLength: Int) -> NSRange {
    let safeLocation = min(range.location, maxLength)
    let safeLength = min(range.length, max(maxLength - safeLocation, 0))
    return NSRange(location: safeLocation, length: safeLength)
  }

  // MARK: - Coordinator

  class Coordinator: NSObject, NSTextViewDelegate {
    var parent: MarkdownTextView
    var isUpdating = false
    var lastPushedMarkdown = ""
    var lastAppliedAppearance = NoteAppearanceSettings.default
    var lastNoteID: DayNote.ID?
    let toolbar = FormattingToolbar()
    let slashPopup = SlashCommandPopup()
    private var slashTriggerLocation: Int?

    init(parent: MarkdownTextView) {
      self.parent = parent
      toolbar.appearanceSettings = parent.appearanceSettings
    }

    func textViewDidChangeSelection(_ notification: Notification) {
      guard let textView = notification.object as? NSTextView else { return }
      let range = textView.selectedRange()

      // Dismiss slash popup if cursor moved away from the trigger line
      if slashPopup.isVisible, let triggerLoc = slashTriggerLocation {
        let nsString = textView.string as NSString
        let triggerLine = nsString.lineRange(for: NSRange(location: triggerLoc, length: 0))
        let cursorLine = nsString.lineRange(for: NSRange(location: range.location, length: 0))
        if triggerLine != cursorLine || range.length > 0 {
          dismissSlashPopup()
        }
      }

      if range.length > 0, let scrollView = textView.enclosingScrollView {
        let glyphRange =
          textView.layoutManager?.glyphRange(
            forCharacterRange: range, actualCharacterRange: nil) ?? range
        let selectionRect =
          textView.layoutManager?.boundingRect(
            forGlyphRange: glyphRange, in: textView.textContainer!) ?? .zero
        let rectInScrollView = textView.convert(selectionRect, to: scrollView)

        toolbar.textView = textView
        toolbar.show(relativeTo: rectInScrollView, in: scrollView)
      } else {
        toolbar.hide()
      }
    }

    func textDidChange(_ notification: Notification) {
      guard !isUpdating else { return }
      guard let textView = notification.object as? NSTextView,
        let textStorage = textView.textStorage
      else { return }

      isUpdating = true
      let markdown = MarkdownStyler.convertToMarkdown(from: textStorage)
      lastPushedMarkdown = markdown
      parent.text = markdown
      isUpdating = false

      // Force full background redraw for section card updates (e.g., backspace deleting a divider)
      textView.setNeedsDisplay(textView.bounds)

      checkSlashCommandTrigger(in: textView)
    }

    func textView(
      _ textView: NSTextView,
      doCommandBy commandSelector: Selector
    ) -> Bool {
      // Intercept navigation keys while slash command popup is visible
      if slashPopup.isVisible {
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)):
          slashPopup.moveSelectionUp()
          return true
        case #selector(NSResponder.moveDown(_:)):
          slashPopup.moveSelectionDown()
          return true
        case #selector(NSResponder.insertNewline(_:)):
          slashPopup.confirmSelection()
          return true
        case #selector(NSResponder.cancelOperation(_:)):
          dismissSlashPopup()
          return true
        default:
          break
        }
      }

      guard commandSelector == #selector(NSResponder.insertNewline(_:)),
        let textStorage = textView.textStorage
      else {
        return false
      }

      isUpdating = true

      let cursorLocation = textView.selectedRange().location
      let nsString = textStorage.string as NSString
      let fullLineRange = nsString.lineRange(
        for: NSRange(location: cursorLocation, length: 0))

      // Trim trailing newline for the content range
      var lineRange = fullLineRange
      if lineRange.length > 0
        && nsString.character(at: lineRange.location + lineRange.length - 1) == 0x0A
      {
        lineRange.length -= 1
      }

      // Check if the line is an empty list item (just the marker) → cancel continuation
      let lineText = nsString.substring(with: lineRange)
      if isEmptyListItem(lineText) {
        removeListMarker(in: textStorage, lineRange: lineRange)
        textView.setSelectedRange(NSRange(location: lineRange.location, length: 0))
        syncToBinding(textView)
        isUpdating = false
        return true
      }

      // Check if the line is an empty blockquote → cancel continuation
      if isEmptyBlockquoteLine(lineText, in: textStorage, at: lineRange) {
        textStorage.beginEditing()
        textStorage.replaceCharacters(in: lineRange, with: "")
        textStorage.endEditing()
        textView.setSelectedRange(NSRange(location: lineRange.location, length: 0))
        syncToBinding(textView)
        isUpdating = false
        return true
      }

      let slashCommand = SlashCommandHandler.matchedCommand(in: textStorage, lineRange: lineRange)
      if let slashCommand {
        switch slashCommand.action {
        case .sectionDivider:
          break
        case .heading(let level):
          replaceCurrentLine(in: textStorage, lineRange: lineRange, with: NSAttributedString())
          textView.setSelectedRange(NSRange(location: lineRange.location, length: 0))
          textView.typingAttributes = headingTypingAttributes(level: level)
          syncToBinding(textView)
          isUpdating = false
          return true
        case .codeBlock:
          let snippet = "```\n\n\n```"
          let displaySnippet = MarkdownStyler.formatForDisplay(
            snippet, appearance: parent.appearanceSettings)
          replaceCurrentLine(in: textStorage, lineRange: lineRange, with: displaySnippet)
          let insertionPoint = lineRange.location + 4
          textView.setSelectedRange(NSRange(location: insertionPoint, length: 0))
          textView.typingAttributes = codeBlockTypingAttributes()
          syncToBinding(textView)
          textView.layoutManager?.ensureLayout(
            forCharacterRange: NSRange(location: 0, length: textStorage.length))
          textView.setNeedsDisplay(textView.bounds)
          isUpdating = false
          return true
        }
      }

      // Slash commands FIRST so /section → divider is formatted in the same pass
      textStorage.beginEditing()
      let slashReplaced = slashCommand?.action == .sectionDivider
      if slashReplaced {
        textStorage.replaceCharacters(in: lineRange, with: "<!-- section -->")
      }

      // Recalculate line range if slash command changed the text
      let formatLineRange: NSRange
      if slashReplaced {
        let updatedNS = textStorage.string as NSString
        let updatedFull = updatedNS.lineRange(
          for: NSRange(
            location: min(lineRange.location, updatedNS.length - 1), length: 0))
        var trimmed = updatedFull
        if trimmed.length > 0
          && updatedNS.character(at: trimmed.location + trimmed.length - 1) == 0x0A
        {
          trimmed.length -= 1
        }
        formatLineRange = trimmed
      } else {
        formatLineRange = lineRange
      }

      // Format the line (original text or replaced slash command)
      let listType = MarkdownStyler.formatCurrentLine(
        in: textStorage, lineRange: formatLineRange, appearance: parent.appearanceSettings)
      textStorage.endEditing()

      // Position cursor at end of the formatted line, then insert newline
      let formattedLineEnd = min(
        NSMaxRange(
          (textStorage.string as NSString).lineRange(
            for: NSRange(location: lineRange.location, length: 0))),
        textStorage.string.utf16.count)

      textView.setSelectedRange(NSRange(location: formattedLineEnd, length: 0))
      textView.insertNewlineIgnoringFieldEditor(nil)

      // Detect if the formatted line is a blockquote for continuation
      let isBlockquoteLine: Bool = {
        let updatedNS = textStorage.string as NSString
        let updatedLine = updatedNS.lineRange(
          for: NSRange(location: min(lineRange.location, updatedNS.length - 1), length: 0))
        guard updatedLine.length > 0, updatedLine.location < textStorage.length else {
          return false
        }
        return textStorage.attribute(
          .markdownBlockquote, at: updatedLine.location, effectiveRange: nil) as? Bool == true
      }()

      // List continuation
      if let listType = listType {
        let marker = continuationMarker(for: listType, previousLineText: lineText)
        if !marker.isEmpty {
          let markerAttr = continuationAttributedMarker(
            for: listType, marker: marker, appearance: parent.appearanceSettings)
          let insertRange = textView.selectedRange()
          textStorage.beginEditing()
          textStorage.insert(markerAttr, at: insertRange.location)
          textStorage.endEditing()
          textView.setSelectedRange(
            NSRange(location: insertRange.location + markerAttr.length, length: 0))
        }
      }

      // Blockquote continuation — set typing attributes so the next line inherits blockquote style
      if isBlockquoteLine, listType == nil {
        textView.typingAttributes = [
          .font: parent.appearanceSettings.bodyFont,
          .foregroundColor: NSColor.secondaryLabelColor,
          .paragraphStyle: MarkdownStyler.blockquoteParagraphStyle(for: parent.appearanceSettings),
          .markdownBlockquote: true,
        ]
      } else if slashReplaced {
        // After a section divider, auto-start a heading 1
        textView.typingAttributes = headingTypingAttributes(level: 1)
      } else if listType == nil {
        textView.typingAttributes = MarkdownStyler.baseTypingAttributes(
          for: parent.appearanceSettings)
      }

      syncToBinding(textView)

      // Force immediate redraw so section card backgrounds update on this frame
      textView.layoutManager?.ensureLayout(
        forCharacterRange: NSRange(location: 0, length: textStorage.length))
      // Dispatch to next cycle so layout is fully committed before drawing
      DispatchQueue.main.async { [weak textView] in
        guard let textView else { return }
        textView.setNeedsDisplay(textView.bounds)
      }

      isUpdating = false
      return true
    }

    // MARK: - List Continuation Helpers

    // Checks if a blockquote line has no content (just the blockquote attribute with empty text)
    private func isEmptyBlockquoteLine(
      _ lineText: String, in textStorage: NSTextStorage, at lineRange: NSRange
    ) -> Bool {
      guard lineRange.length >= 0, lineRange.location < textStorage.length else { return false }
      let isQuote =
        lineRange.length > 0
        ? textStorage.attribute(.markdownBlockquote, at: lineRange.location, effectiveRange: nil)
          as? Bool == true
        : false
      guard isQuote else { return false }
      return lineText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func isEmptyListItem(_ lineText: String) -> Bool {
      let trimmed = lineText.trimmingCharacters(in: .whitespaces)
      let emptyMarkers = [
        "\(MarkdownStyler.bulletMarker) ",
        "\(MarkdownStyler.bulletMarker)",
        "\(MarkdownStyler.attachmentChar) ",
        "\(MarkdownStyler.attachmentChar)",
        "- ",
        "-",
      ]
      if emptyMarkers.contains(trimmed) { return true }
      if trimmed.range(of: #"^\d+\.\s*$"#, options: .regularExpression) != nil { return true }
      return false
    }

    private func removeListMarker(in textStorage: NSTextStorage, lineRange: NSRange) {
      textStorage.beginEditing()
      textStorage.replaceCharacters(in: lineRange, with: "")
      textStorage.endEditing()
    }

    private func continuationMarker(for listType: MarkdownListType, previousLineText: String)
      -> String
    {
      switch listType {
      case .bullet:
        return "\(MarkdownStyler.bulletMarker) "
      case .checkboxUnchecked, .checkboxChecked:
        return "\(MarkdownStyler.uncheckedMarker) "
      case .numbered:
        if let match = previousLineText.range(of: #"^(\d+)\."#, options: .regularExpression) {
          let numStr = previousLineText[match].dropLast()
          if let num = Int(numStr) { return "\(num + 1). " }
        }
        return "1. "
      }
    }

    private func continuationAttributedMarker(
      for listType: MarkdownListType, marker: String, appearance: NoteAppearanceSettings
    ) -> NSAttributedString {
      switch listType {
      case .checkboxUnchecked, .checkboxChecked:
        let result = NSMutableAttributedString()
        result.append(
          MarkdownStyler.checkboxAttributedString(checked: false, appearance: appearance))
        result.append(
          NSAttributedString(
            string: " ",
            attributes: [
              .font: appearance.bodyFont,
              .foregroundColor: NSColor.labelColor,
              .paragraphStyle: MarkdownStyler.bodyParagraphStyle(for: appearance),
            ]))
        let fullRange = NSRange(location: 0, length: result.length)
        result.addAttributes(
          [
            .markdownListType: MarkdownListType.checkboxUnchecked.rawValue,
            .paragraphStyle: MarkdownStyler.listParagraphStyle(for: appearance),
          ], range: fullRange)
        return result

      default:
        let result = NSMutableAttributedString(
          string: marker,
          attributes: [
            .font: appearance.bodyFont,
            .foregroundColor: NSColor.labelColor,
            .markdownListType: listType.rawValue,
            .paragraphStyle: MarkdownStyler.listParagraphStyle(for: appearance),
          ])
        if listType == .bullet {
          result.addAttributes(
            [
              .foregroundColor: MarkdownStyler.bulletColor(for: appearance),
              .font: NSFont.systemFont(ofSize: appearance.bulletSize, weight: .bold),
            ], range: NSRange(location: 0, length: 1))
        } else if listType == .numbered {
          if let numEnd = marker.firstIndex(of: ".") {
            let numLength = marker.distance(from: marker.startIndex, to: numEnd) + 1
            result.addAttribute(
              .foregroundColor, value: NSColor.secondaryLabelColor,
              range: NSRange(location: 0, length: numLength))
          }
        }
        return result
      }
    }

    // MARK: - Slash Command Popup

    private func checkSlashCommandTrigger(in textView: NSTextView) {
      let cursorLocation = textView.selectedRange().location
      guard cursorLocation > 0 else {
        dismissSlashPopup()
        return
      }

      let nsString = textView.string as NSString
      let lineRange = nsString.lineRange(for: NSRange(location: cursorLocation, length: 0))

      // Get text from line start to cursor
      let prefixLength = cursorLocation - lineRange.location
      guard prefixLength > 0 else {
        dismissSlashPopup()
        return
      }
      let prefixRange = NSRange(location: lineRange.location, length: prefixLength)
      let prefixText = nsString.substring(with: prefixRange)
      let trimmed = prefixText.trimmingCharacters(in: .whitespaces)

      // Must start with "/" and only have whitespace before it
      guard trimmed.hasPrefix("/") else {
        dismissSlashPopup()
        return
      }

      let filtered = SlashCommandHandler.filteredCommands(for: trimmed)
      guard !filtered.isEmpty else {
        dismissSlashPopup()
        return
      }

      // Track where the "/" character starts
      if slashTriggerLocation == nil {
        let whitespaceCount = prefixText.count - trimmed.count
        slashTriggerLocation = lineRange.location + whitespaceCount
      }

      slashPopup.updateFilter(trimmed)

      // Position popup near the cursor
      guard let layoutManager = textView.layoutManager,
        let scrollView = textView.enclosingScrollView
      else { return }

      let glyphIndex = layoutManager.glyphIndexForCharacter(at: cursorLocation)
      let lineFragment = layoutManager.lineFragmentRect(
        forGlyphAt: glyphIndex, effectiveRange: nil)
      let cursorRect = NSRect(
        x: lineFragment.minX + textView.textContainerOrigin.x,
        y: lineFragment.maxY + textView.textContainerOrigin.y,
        width: 1,
        height: lineFragment.height
      )
      let rectInScrollView = textView.convert(cursorRect, to: scrollView)
      slashPopup.show(relativeTo: rectInScrollView, in: scrollView)

      // Wire up selection callback (idempotent — closure captures current textView)
      slashPopup.onSelect = { [weak self, weak textView] entry in
        guard let self, let textView else { return }
        self.applySlashCommand(entry, in: textView)
      }
    }

    private func dismissSlashPopup() {
      slashPopup.hide()
      slashTriggerLocation = nil
    }

    private func replaceCurrentLine(
      in textStorage: NSTextStorage,
      lineRange: NSRange,
      with attributedString: NSAttributedString
    ) {
      textStorage.beginEditing()
      textStorage.replaceCharacters(in: lineRange, with: attributedString)
      textStorage.endEditing()
    }

    private func headingTypingAttributes(level: Int) -> [NSAttributedString.Key: Any] {
      [
        .font: parent.appearanceSettings.boldBodyFont(ofSize: headingFontSize(for: level)),
        .foregroundColor: NSColor.labelColor,
        .paragraphStyle: MarkdownStyler.bodyParagraphStyle(for: parent.appearanceSettings),
        .markdownHeadingLevel: level,
      ]
    }

    private func codeBlockTypingAttributes() -> [NSAttributedString.Key: Any] {
      [
        .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
        .backgroundColor: NSColor.quaternaryLabelColor,
        .foregroundColor: NSColor.labelColor,
        .markdownCodeBlock: true,
      ]
    }

    private func headingFontSize(for level: Int) -> CGFloat {
      switch level {
      case 1:
        return 22
      case 2:
        return 19
      default:
        return 17
      }
    }

    // Replaces the partially-typed command with the full command text, then fires Enter
    private func applySlashCommand(_ entry: SlashCommandEntry, in textView: NSTextView) {
      guard let triggerLoc = slashTriggerLocation else { return }
      let cursorLoc = textView.selectedRange().location
      guard cursorLoc >= triggerLoc else { return }

      let replaceRange = NSRange(location: triggerLoc, length: cursorLoc - triggerLoc)
      textView.textStorage?.beginEditing()
      textView.textStorage?.replaceCharacters(in: replaceRange, with: entry.command)
      textView.textStorage?.endEditing()

      let newCursorLoc = triggerLoc + entry.command.utf16.count
      textView.setSelectedRange(NSRange(location: newCursorLoc, length: 0))

      dismissSlashPopup()

      // Trigger the existing Enter key flow which handles slash command detection + formatting
      isUpdating = true
      let _ = self.textView(textView, doCommandBy: #selector(NSResponder.insertNewline(_:)))
    }

    private func syncToBinding(_ textView: NSTextView) {
      guard let textStorage = textView.textStorage else { return }
      let markdown = MarkdownStyler.convertToMarkdown(from: textStorage)
      lastPushedMarkdown = markdown
      parent.text = markdown
    }
  }
}

// MARK: - Custom NSTextView subclass

private class DayraTextView: NSTextView {

  var appearanceSettings = NoteAppearanceSettings.default
  private let cardColor = NSColor.labelColor.withAlphaComponent(0.04)
  private let cardRadius: CGFloat = 24
  private let cardHInset: CGFloat = 0
  private let cardVPad: CGFloat = 10

  // MARK: - Section Card Backgrounds

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
      // Always draw the last section so the card gap appears immediately after a divider
      guard glyphRange.length > 0 || isLastSection else { continue }

      // Card top: y=0 for first section, divider midpoint for others
      let cardTop: CGFloat
      if index == 0 {
        cardTop = 0
      } else {
        let divIndex = min(index - 1, dividerMidYs.count - 1)
        cardTop = dividerMidYs[divIndex] + 6  // 6pt gap below midpoint
      }

      // Card bottom: divider midpoint for intermediate sections, view bottom for last
      let cardBottom: CGFloat
      if index == sections.count - 1 {
        cardBottom = viewBottom
      } else {
        let divIndex = min(index, dividerMidYs.count - 1)
        cardBottom = dividerMidYs[divIndex] - 6  // 6pt gap above midpoint
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
    }

    drawHorizontalRules(hrLineRanges, in: rect)
  }

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
    NSColor.separatorColor.setFill()

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

  // MARK: - Paste

  override func paste(_ sender: Any?) {
    guard let plainText = NSPasteboard.general.string(forType: .string) else { return }
    insertText(plainText, replacementRange: selectedRange())
  }

  // MARK: - Checkbox Click

  override func mouseDown(with event: NSEvent) {
    guard let textStorage = textStorage, let layoutManager = layoutManager,
      let textContainer = textContainer
    else {
      super.mouseDown(with: event)
      return
    }

    let point = convert(event.locationInWindow, from: nil)
    let textPoint = NSPoint(
      x: point.x - textContainerInset.width,
      y: point.y - textContainerInset.height)
    let charIndex = layoutManager.characterIndex(
      for: textPoint, in: textContainer,
      fractionOfDistanceBetweenInsertionPoints: nil)

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

    textStorage.beginEditing()

    let newAttachment = MarkdownStyler.checkboxAttachment(
      checked: !isChecked,
      appearance: appearanceSettings
    )
    let attachmentStr = NSAttributedString(attachment: newAttachment)
    textStorage.replaceCharacters(
      in: NSRange(location: charIndex, length: 1), with: attachmentStr)

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
      .markdownListType, value: newType.rawValue, range: updatedTextRange)
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
          .strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: contentRange)
      }
    }

    textStorage.endEditing()
  }
}
