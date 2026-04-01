//
//  MarkdownTextView.swift
//  dayra
//
//  Created by Steve Walsh on 01/04/2026.
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
    textView.textContainerInset = NSSize(width: 10, height: 10)
    textView.delegate = context.coordinator

    textView.textContainer?.widthTracksTextView = true
    textView.textContainer?.heightTracksTextView = false
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.autoresizingMask = [.width]

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

    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    guard !context.coordinator.isUpdating else { return }
    guard text != context.coordinator.lastPushedMarkdown else { return }
    guard let textView = scrollView.documentView as? NSTextView else { return }

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
        let glyphRange = textView.layoutManager?.glyphRange(
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

      // Format the current line (strips markdown delimiters, applies attributes)
      textStorage.beginEditing()
      let listType = MarkdownStyler.formatCurrentLine(
        in: textStorage, lineRange: lineRange, defaultFont: NSFont.systemFont(ofSize: 15))

      // Also handle slash commands before inserting newline
      let updatedNSString = textStorage.string as NSString
      let updatedLineRange = updatedNSString.lineRange(
        for: NSRange(location: min(lineRange.location, updatedNSString.length - 1), length: 0))
      var updatedTextRange = updatedLineRange
      if updatedTextRange.length > 0
        && updatedNSString.character(
          at: updatedTextRange.location + updatedTextRange.length - 1) == 0x0A
      {
        updatedTextRange.length -= 1
      }
      _ = SlashCommandHandler.detectAndReplace(in: textStorage, lineRange: updatedTextRange)
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

      // Reset typing attributes for new line (unless list continuation set them)
      if listType == nil {
        textView.typingAttributes = [
          .font: NSFont.systemFont(ofSize: 15),
          .foregroundColor: NSColor.labelColor,
          .paragraphStyle: NSParagraphStyle.default,
        ]
      }

      syncToBinding(textView)
      isUpdating = false
      return true
    }

    // MARK: - List Continuation Helpers

    private func isEmptyListItem(_ lineText: String) -> Bool {
      let trimmed = lineText.trimmingCharacters(in: .whitespaces)
      let emptyMarkers = [
        "\(MarkdownStyler.bulletMarker) ",
        "\(MarkdownStyler.bulletMarker)",
        "\(MarkdownStyler.uncheckedMarker) ",
        "\(MarkdownStyler.uncheckedMarker)",
        "\(MarkdownStyler.checkedMarker) ",
        "\(MarkdownStyler.checkedMarker)",
        "- ",
        "-",
      ]
      if emptyMarkers.contains(trimmed) { return true }

      // Empty numbered list item: just "N. " or "N."
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
        if let match = previousLineText.range(
          of: #"^(\d+)\."#, options: .regularExpression)
        {
          let numStr = previousLineText[match].dropLast()
          if let num = Int(numStr) {
            return "\(num + 1). "
          }
        }
        return "1. "
      }
    }

    private func continuationAttributedMarker(
      for listType: MarkdownListType, marker: String, defaultFont: NSFont
    ) -> NSAttributedString {
      let result = NSMutableAttributedString(
        string: marker,
        attributes: [
          .font: defaultFont,
          .foregroundColor: NSColor.labelColor,
          .markdownListType: listType.rawValue,
          .paragraphStyle: listParagraphStyle(),
        ])

      switch listType {
      case .bullet:
        result.addAttributes([
          .foregroundColor: NSColor.controlAccentColor,
          .font: NSFont.systemFont(ofSize: defaultFont.pointSize - 2, weight: .regular),
        ], range: NSRange(location: 0, length: 1))
      case .checkboxUnchecked, .checkboxChecked:
        result.addAttributes([
          .foregroundColor: NSColor.secondaryLabelColor,
          .font: NSFont.systemFont(ofSize: defaultFont.pointSize, weight: .medium),
        ], range: NSRange(location: 0, length: 1))
      case .numbered:
        if let numEnd = marker.firstIndex(of: ".") {
          let numLength = marker.distance(from: marker.startIndex, to: numEnd) + 1
          result.addAttribute(
            .foregroundColor, value: NSColor.secondaryLabelColor,
            range: NSRange(location: 0, length: numLength))
        }
      }

      return result
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

// MARK: - Plain-text paste subclass

private class DayraTextView: NSTextView {
  override func paste(_ sender: Any?) {
    guard let plainText = NSPasteboard.general.string(forType: .string) else { return }
    insertText(plainText, replacementRange: selectedRange())
  }
}
