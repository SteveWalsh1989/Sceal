//
//  NextMarkdownTextView.swift
//

// TextKit 2 preview editor shell used for the staged migration away from the legacy editor.

import AppKit
import SwiftUI

struct NextMarkdownTextView: NSViewRepresentable {
  private static let minimumBottomPadding: CGFloat = 300

  let noteID: DayNote.ID
  @Binding var text: String
  let appearanceSettings: NoteAppearanceSettings

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  func makeNSView(context: Context) -> NSScrollView {
    let textView = NSTextView(usingTextLayoutManager: true)
    configure(textView, coordinator: context.coordinator)

    let scrollView = NSScrollView()
    scrollView.documentView = textView
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.drawsBackground = false
    scrollView.automaticallyAdjustsContentInsets = false
    scrollView.contentInsets = .init()

    applyDisplayString(
      MarkdownStyler.formatForDisplay(text, appearance: appearanceSettings),
      to: textView
    )
    context.coordinator.lastPushedMarkdown = text
    context.coordinator.lastAppliedAppearance = appearanceSettings
    context.coordinator.lastNoteID = noteID
    context.coordinator.toolbar.appearanceSettings = appearanceSettings

    textView.minSize = NSSize(
      width: 0,
      height: scrollView.contentSize.height + Self.minimumBottomPadding
    )

    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    guard !context.coordinator.isUpdating else { return }
    guard let textView = scrollView.documentView as? NSTextView else { return }

    context.coordinator.parent = self
    configure(textView, coordinator: context.coordinator)
    context.coordinator.toolbar.appearanceSettings = appearanceSettings

    let minHeight = scrollView.contentSize.height + Self.minimumBottomPadding
    if textView.minSize.height != minHeight {
      textView.minSize = NSSize(width: 0, height: minHeight)
    }

    let noteChanged = noteID != context.coordinator.lastNoteID
    let textChanged = text != context.coordinator.lastPushedMarkdown
    let appearanceChanged = appearanceSettings != context.coordinator.lastAppliedAppearance
    guard noteChanged || textChanged || appearanceChanged else { return }

    context.coordinator.isUpdating = true
    let visibleOrigin = scrollView.contentView.bounds.origin
    let wasFirstResponder = textView.window?.firstResponder === textView

    let displayString = MarkdownStyler.formatForDisplay(text, appearance: appearanceSettings)
    let selectedRange =
      noteChanged
      ? NSRange(location: 0, length: 0)
      : clampedRange(textView.selectedRange(), maxLength: text.utf16.count)
    applyDisplayString(displayString, to: textView)
    context.coordinator.lastPushedMarkdown = text
    context.coordinator.lastAppliedAppearance = appearanceSettings
    context.coordinator.lastNoteID = noteID
    textView.setSelectedRange(
      clampedRange(selectedRange, maxLength: textView.string.utf16.count)
    )

    if noteChanged {
      scrollView.contentView.scroll(to: .zero)
      textView.window?.makeFirstResponder(nil)
    } else {
      scrollView.contentView.scroll(to: visibleOrigin)
      if wasFirstResponder, textView.window?.firstResponder !== textView {
        textView.window?.makeFirstResponder(textView)
      }
    }

    scrollView.reflectScrolledClipView(scrollView.contentView)
    context.coordinator.isUpdating = false
    context.coordinator.refreshToolbarPresentation(in: textView)
  }

  private func configure(_ textView: NSTextView, coordinator: Coordinator) {
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
    textView.selectedTextAttributes = [
      .backgroundColor: NSColor.selectedTextBackgroundColor.withAlphaComponent(0.22)
    ]
    textView.textContainerInset = NSSize(width: 22, height: 22)
    textView.linkTextAttributes = [
      .foregroundColor: NSColor.linkColor,
      .cursor: NSCursor.pointingHand,
    ]
    textView.typingAttributes = MarkdownStyler.baseTypingAttributes(for: appearanceSettings)
    textView.delegate = coordinator
    textView.textContainer?.widthTracksTextView = true
    textView.textContainer?.heightTracksTextView = false
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.autoresizingMask = [.width]
    textView.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude,
      height: CGFloat.greatestFiniteMagnitude
    )
  }

  private func applyDisplayString(_ displayString: NSAttributedString, to textView: NSTextView) {
    textView.textStorage?.setAttributedString(displayString)
    textView.ensureEditorLayoutForEntireDocument()
    textView.setNeedsDisplay(textView.bounds)
  }

  private func clampedRange(_ range: NSRange, maxLength: Int) -> NSRange {
    let safeLocation = min(range.location, maxLength)
    let safeLength = min(range.length, max(maxLength - safeLocation, 0))
    return NSRange(location: safeLocation, length: safeLength)
  }
}

extension NextMarkdownTextView {
  @MainActor
  final class Coordinator: NSObject, NSTextViewDelegate {
    var parent: NextMarkdownTextView
    var isUpdating = false
    var lastPushedMarkdown = ""
    var lastAppliedAppearance = NoteAppearanceSettings.default
    var lastNoteID: DayNote.ID?
    let toolbar = FormattingToolbar()

    init(parent: NextMarkdownTextView) {
      self.parent = parent
      toolbar.appearanceSettings = parent.appearanceSettings
    }

    func textDidChange(_ notification: Notification) {
      guard !isUpdating else { return }
      guard let textView = notification.object as? NSTextView,
        let textStorage = textView.textStorage
      else { return }

      isUpdating = true
      textView.typingAttributes = MarkdownStyler.baseTypingAttributes(
        for: parent.appearanceSettings
      )
      let markdown = MarkdownStyler.convertToMarkdown(from: textStorage)
      lastPushedMarkdown = markdown
      parent.text = markdown
      isUpdating = false
    }

    func textViewDidChangeSelection(_ notification: Notification) {
      guard let textView = notification.object as? NSTextView else { return }
      refreshToolbarPresentation(in: textView)
    }

    func refreshToolbarPresentation(in textView: NSTextView) {
      let range = textView.selectedRange()
      guard
        range.length > 0,
        let scrollView = textView.enclosingScrollView,
        let selectionRect = textView.editorRect(forCharacterRange: range)
      else {
        toolbar.hide()
        return
      }

      toolbar.appearanceSettings = parent.appearanceSettings
      toolbar.textView = textView
      toolbar.show(relativeTo: textView.convert(selectionRect, to: scrollView), in: scrollView)
    }
  }
}
