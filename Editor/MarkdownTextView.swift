//
//  MarkdownTextView.swift
//
//

// NSViewRepresentable bridge between SwiftUI and the AppKit markdown editor.

import AppKit
import SwiftUI

struct MarkdownTextView: NSViewRepresentable {
  let noteID: DayNote.ID
  @Binding var text: String
  let appearanceSettings: NoteAppearanceSettings

  // Creates the coordinator that handles text view delegation and editing.
  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  // Builds the NSScrollView + ScealTextView with initial configuration.
  func makeNSView(context: Context) -> NSScrollView {
    let textView = ScealTextView()
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
    // Show links in blue without the default underline that NSTextView adds.
    textView.linkTextAttributes = [
      .foregroundColor: NSColor.linkColor,
      .cursor: NSCursor.pointingHand,
    ]
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
    scrollView.automaticallyAdjustsContentInsets = false
    scrollView.contentInsets = .init()

    // Load initial content
    let displayString = MarkdownStyler.formatForDisplay(text, appearance: appearanceSettings)
    textView.textStorage?.setAttributedString(displayString)
    textView.refreshSectionLayout()
    context.coordinator.lastPushedMarkdown = text
    context.coordinator.lastAppliedAppearance = appearanceSettings
    context.coordinator.lastDividerCount = textView.sectionDividerCount
    context.coordinator.lastNoteID = noteID

    // Ensure text view fills at least the visible area plus bottom padding so clicks
    // anywhere in the editor land on the text view rather than dead scroll-view space.
    textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height + 300)

    return scrollView
  }

  // Syncs SwiftUI state changes into the AppKit text view.
  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    guard !context.coordinator.isUpdating else { return }
    guard let textView = scrollView.documentView as? NSTextView else { return }
    context.coordinator.parent = self
    context.coordinator.toolbar.appearanceSettings = appearanceSettings

    // Keep text view filling the visible area plus bottom padding
    let minH = scrollView.contentSize.height + 300
    if textView.minSize.height != minH {
      textView.minSize = NSSize(width: 0, height: minH)
    }

    let noteChanged = noteID != context.coordinator.lastNoteID
    let textChanged = text != context.coordinator.lastPushedMarkdown
    let appearanceChanged = appearanceSettings != context.coordinator.lastAppliedAppearance
    guard noteChanged || textChanged || appearanceChanged else { return }

    context.coordinator.isUpdating = true
    let visibleOrigin = scrollView.contentView.bounds.origin

    // Capture first-responder status so we can restore it after programmatic edits.
    let wasFirstResponder = textView.window?.firstResponder === textView

    if let scealTextView = textView as? ScealTextView {
      scealTextView.appearanceSettings = appearanceSettings
    }
    textView.font = appearanceSettings.bodyFont
    textView.typingAttributes = MarkdownStyler.baseTypingAttributes(for: appearanceSettings)

    let contentChanged = noteChanged || textChanged
    let displayString = MarkdownStyler.formatForDisplay(text, appearance: appearanceSettings)

    if contentChanged {
      // Full replacement — note switched or text changed externally
      let selectedRange =
        noteChanged
        ? NSRange(location: 0, length: 0)
        : clampedRange(textView.selectedRange(), maxLength: text.utf16.count)
      textView.textStorage?.setAttributedString(displayString)
      context.coordinator.lastPushedMarkdown = text
      textView.setSelectedRange(
        clampedRange(selectedRange, maxLength: textView.string.utf16.count))
    } else if appearanceChanged, let textStorage = textView.textStorage {
      // Appearance-only change — re-apply attributes in place to preserve undo stack.
      let fullRange = NSRange(location: 0, length: textStorage.length)
      if textStorage.string == displayString.string {
        textStorage.beginEditing()
        displayString.enumerateAttributes(in: fullRange, options: []) { attrs, range, _ in
          textStorage.setAttributes(attrs, range: range)
        }
        textStorage.endEditing()
      } else {
        // Display text differs (shouldn't happen) — fall back to full replacement
        textView.textStorage?.setAttributedString(displayString)
        context.coordinator.lastPushedMarkdown = text
      }
    }

    context.coordinator.lastAppliedAppearance = appearanceSettings
    context.coordinator.lastNoteID = noteID
    if let scealTextView = textView as? ScealTextView {
      _ = scealTextView.normalizeSelectionIfNeeded()
      scealTextView.refreshSectionLayout()
      context.coordinator.lastDividerCount = scealTextView.sectionDividerCount
    }

    if noteChanged {
      // Scroll to top and resign first responder so the sidebar keeps keyboard focus.
      scrollView.contentView.scroll(to: .zero)
      textView.window?.makeFirstResponder(nil)
    } else {
      scrollView.contentView.scroll(to: visibleOrigin)
      // Restore first-responder if programmatic text storage edits caused it to resign.
      if wasFirstResponder, textView.window?.firstResponder !== textView {
        textView.window?.makeFirstResponder(textView)
      }
    }
    scrollView.reflectScrolledClipView(scrollView.contentView)
    context.coordinator.isUpdating = false
  }

  // Constrains a text range to valid bounds.
  private func clampedRange(_ range: NSRange, maxLength: Int) -> NSRange {
    let safeLocation = min(range.location, maxLength)
    let safeLength = min(range.length, max(maxLength - safeLocation, 0))
    return NSRange(location: safeLocation, length: safeLength)
  }
}
