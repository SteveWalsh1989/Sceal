//
//  MarkdownTextView.swift
//  dayra
//
//  Created by Steve Walsh on 01/04/2026.
//

import SwiftUI
import AppKit

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

    textView.string = text
    MarkdownStyler.applyFormatting(
      to: textView.textStorage!,
      defaultFont: NSFont.systemFont(ofSize: 15)
    )

    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    guard !context.coordinator.isUpdating else { return }
    guard let textView = scrollView.documentView as? NSTextView else { return }
    guard text != textView.string else { return }

    context.coordinator.isUpdating = true
    let selectedRange = textView.selectedRange()
    textView.string = text
    MarkdownStyler.applyFormatting(
      to: textView.textStorage!,
      defaultFont: NSFont.systemFont(ofSize: 15)
    )
    if selectedRange.location + selectedRange.length <= (text as NSString).length {
      textView.setSelectedRange(selectedRange)
    }
    context.coordinator.isUpdating = false
  }

  // MARK: - Coordinator

  class Coordinator: NSObject, NSTextViewDelegate {
    var parent: MarkdownTextView
    var isUpdating = false

    init(parent: MarkdownTextView) {
      self.parent = parent
    }

    func textDidChange(_ notification: Notification) {
      guard !isUpdating else { return }
      guard let textView = notification.object as? NSTextView else { return }
      isUpdating = true
      parent.text = textView.string
      isUpdating = false
    }

    func textView(
      _ textView: NSTextView,
      doCommandBy commandSelector: Selector
    ) -> Bool {
      guard commandSelector == #selector(NSResponder.insertNewline(_:)) else {
        return false
      }

      let nsString = textView.string as NSString
      let lineRange = nsString.lineRange(
        for: NSRange(location: textView.selectedRange().location, length: 0)
      )

      _ = SlashCommandHandler.detectAndReplace(
        in: textView.textStorage!,
        lineRange: lineRange
      )

      textView.insertNewlineIgnoringFieldEditor(nil)

      MarkdownStyler.applyFormatting(
        to: textView.textStorage!,
        defaultFont: NSFont.systemFont(ofSize: 15)
      )

      isUpdating = true
      parent.text = textView.string
      isUpdating = false

      return true
    }
  }
}

// MARK: - Plain-text paste subclass

private class DayraTextView: NSTextView {
  override func paste(_ sender: Any?) {
    guard let pasteboard = NSPasteboard.general.string(forType: .string) else { return }
    insertText(pasteboard, replacementRange: selectedRange())
  }
}
