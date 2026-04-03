//
//  NextInteractiveTextView.swift
//

// TextKit 2 text view subclass for divider-safe caret placement and checkbox clicks.

import AppKit

@MainActor
final class NextInteractiveTextView: NSTextView {
  var appearanceSettings = NoteAppearanceSettings.default

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func moveUp(_ sender: Any?) {
    super.moveUp(sender)
    _ = editorNormalizeSelectionIfNeeded(prefer: .previous)
  }

  override func moveDown(_ sender: Any?) {
    super.moveDown(sender)
    _ = editorNormalizeSelectionIfNeeded(prefer: .next)
  }

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

  override func paste(_ sender: Any?) {
    guard let plainText = NSPasteboard.general.string(forType: .string) else { return }
    insertText(plainText, replacementRange: selectedRange())
  }

  override func mouseDown(with event: NSEvent) {
    if window?.firstResponder !== self {
      window?.makeFirstResponder(self)
    }

    guard let textStorage else {
      super.mouseDown(with: event)
      return
    }

    let point = convert(event.locationInWindow, from: nil)
    guard let charIndex = editorCharacterIndex(forViewPoint: point) else {
      super.mouseDown(with: event)
      return
    }

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

    if editorToggleCheckbox(at: charIndex, appearanceSettings: appearanceSettings) {
      return
    }

    super.mouseDown(with: event)
  }
}
