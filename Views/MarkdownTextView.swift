//
//  MarkdownTextView.swift
//  dayra
//
//

import AppKit
import SwiftUI

struct MarkdownTextView: NSViewRepresentable {
  @Binding var text: String

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  func makeNSView(context: Context) -> NSScrollView {
    let textView = DayraTextView()
    textView.isRichText = true
    textView.isEditable = true
    textView.isSelectable = true
    textView.font = NSFont.systemFont(ofSize: 15)
    textView.drawsBackground = false
    textView.allowsUndo = true
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isAutomaticTextReplacementEnabled = false
    textView.isAutomaticSpellingCorrectionEnabled = false
    textView.textContainerInset = NSSize(width: 22, height: 22)
    textView.delegate = context.coordinator

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
    let displayString = MarkdownStyler.formatForDisplay(
      text, defaultFont: NSFont.systemFont(ofSize: 15))
    textView.textStorage?.setAttributedString(displayString)
    context.coordinator.lastPushedMarkdown = text

    // Ensure text view fills at least the scroll view height
    textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)

    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    guard !context.coordinator.isUpdating else { return }
    guard let textView = scrollView.documentView as? NSTextView else { return }

    // Keep text view filling the scroll view height
    let minH = scrollView.contentSize.height
    if textView.minSize.height != minH {
      textView.minSize = NSSize(width: 0, height: minH)
    }

    guard text != context.coordinator.lastPushedMarkdown else { return }

    context.coordinator.isUpdating = true
    let displayString = MarkdownStyler.formatForDisplay(
      text, defaultFont: NSFont.systemFont(ofSize: 15))
    textView.textStorage?.setAttributedString(displayString)
    context.coordinator.lastPushedMarkdown = text
    context.coordinator.isUpdating = false
  }

  // MARK: - Coordinator

  class Coordinator: NSObject, NSTextViewDelegate {
    var parent: MarkdownTextView
    var isUpdating = false
    var lastPushedMarkdown = ""
    let toolbar = FormattingToolbar()

    init(parent: MarkdownTextView) {
      self.parent = parent
    }

    func textViewDidChangeSelection(_ notification: Notification) {
      guard let textView = notification.object as? NSTextView else { return }
      let range = textView.selectedRange()

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
    }

    func textView(
      _ textView: NSTextView,
      doCommandBy commandSelector: Selector
    ) -> Bool {
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

      // Slash commands FIRST so /section → --- is formatted in the same pass
      textStorage.beginEditing()
      let slashReplaced = SlashCommandHandler.detectAndReplace(
        in: textStorage, lineRange: lineRange)

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
        in: textStorage, lineRange: formatLineRange, defaultFont: NSFont.systemFont(ofSize: 15))
      textStorage.endEditing()

      // Position cursor at end of the formatted line, then insert newline
      let formattedLineEnd = min(
        NSMaxRange(
          (textStorage.string as NSString).lineRange(
            for: NSRange(location: lineRange.location, length: 0))),
        textStorage.string.utf16.count)

      textView.setSelectedRange(NSRange(location: formattedLineEnd, length: 0))
      textView.insertNewlineIgnoringFieldEditor(nil)

      // List continuation
      if let listType = listType {
        let marker = continuationMarker(for: listType, previousLineText: lineText)
        if !marker.isEmpty {
          let markerAttr = continuationAttributedMarker(
            for: listType, marker: marker, defaultFont: NSFont.systemFont(ofSize: 15))
          let insertRange = textView.selectedRange()
          textStorage.beginEditing()
          textStorage.insert(markerAttr, at: insertRange.location)
          textStorage.endEditing()
          textView.setSelectedRange(
            NSRange(location: insertRange.location + markerAttr.length, length: 0))
        }
      }

      // Set typing attributes for the new line
      if slashReplaced {
        // After a section divider, auto-start a heading 1
        textView.typingAttributes = [
          .font: NSFont.systemFont(ofSize: 22, weight: .bold),
          .foregroundColor: NSColor.labelColor,
          .paragraphStyle: NSParagraphStyle.default,
          .markdownHeadingLevel: 1,
        ]
      } else if listType == nil {
        textView.typingAttributes = [
          .font: NSFont.systemFont(ofSize: 15),
          .foregroundColor: NSColor.labelColor,
          .paragraphStyle: NSParagraphStyle.default,
        ]
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
      for listType: MarkdownListType, marker: String, defaultFont: NSFont
    ) -> NSAttributedString {
      switch listType {
      case .checkboxUnchecked, .checkboxChecked:
        let result = NSMutableAttributedString()
        result.append(MarkdownStyler.checkboxAttributedString(checked: false))
        result.append(NSAttributedString(
          string: " ",
          attributes: [.font: defaultFont, .foregroundColor: NSColor.labelColor]))
        let fullRange = NSRange(location: 0, length: result.length)
        result.addAttributes([
          .markdownListType: MarkdownListType.checkboxUnchecked.rawValue,
          .paragraphStyle: listParagraphStyle(),
        ], range: fullRange)
        return result

      default:
        let result = NSMutableAttributedString(
          string: marker,
          attributes: [
            .font: defaultFont,
            .foregroundColor: NSColor.labelColor,
            .markdownListType: listType.rawValue,
            .paragraphStyle: listParagraphStyle(),
          ])
        if listType == .bullet {
          result.addAttributes([
            .foregroundColor: MarkdownStyler.bulletColor,
            .font: NSFont.systemFont(ofSize: 11, weight: .bold),
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

    private func listParagraphStyle() -> NSMutableParagraphStyle {
      let style = NSMutableParagraphStyle()
      style.firstLineHeadIndent = 8
      style.headIndent = 28
      style.paragraphSpacing = 2
      return style
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

    // No dividers → one card covering everything
    if dividerLineRanges.isEmpty {
      drawSingleCard(in: rect)
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
      guard glyphRange.length > 0 else { continue }

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
  }

  private func drawSingleCard(in rect: NSRect) {
    let fullHeight = max(bounds.height, enclosingScrollView?.contentSize.height ?? bounds.height)
    let cardRect = NSRect(x: cardHInset, y: 0, width: bounds.width - cardHInset * 2, height: fullHeight)
    guard cardRect.intersects(rect) else { return }
    let path = NSBezierPath(roundedRect: cardRect, xRadius: cardRadius, yRadius: cardRadius)
    cardColor.setFill()
    path.fill()
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

    let newAttachment = MarkdownStyler.checkboxAttachment(checked: !isChecked)
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
