//
//  NSTextView+EditorEdit.swift
//

import AppKit

extension NSTextView {
  // Routes editor mutations through NSTextView's edit lifecycle so AppKit sees the final caret only.
  @discardableResult
  func performEditorEdit(
    affectedRange: NSRange? = nil,
    replacementString: String? = nil,
    actionName: String? = nil,
    edit: (NSTextStorage) -> NSRange?
  ) -> Bool {
    guard let textStorage else { return false }
    let targetRange = clampedEditorRange(
      affectedRange ?? selectedRange(), maxLength: textStorage.length)
    guard shouldChangeText(in: targetRange, replacementString: replacementString) else {
      return false
    }

    let initialSelection = clampedEditorRange(selectedRange(), maxLength: textStorage.length)
    textStorage.beginEditing()
    let desiredSelection = edit(textStorage) ?? initialSelection
    textStorage.endEditing()
    didChangeText()

    // Layout must reflect the final text storage before AppKit recomputes the insertion rect.
    if let layoutManager, textStorage.length > 0 {
      layoutManager.ensureLayout(
        forCharacterRange: NSRange(location: 0, length: textStorage.length))
    }
    setSelectedRange(clampedEditorRange(desiredSelection, maxLength: textStorage.length))

    if let actionName {
      undoManager?.setActionName(actionName)
    }

    return true
  }

  private func clampedEditorRange(_ range: NSRange, maxLength: Int) -> NSRange {
    let safeLocation = min(range.location, maxLength)
    let safeLength = min(range.length, max(maxLength - safeLocation, 0))
    return NSRange(location: safeLocation, length: safeLength)
  }
}
