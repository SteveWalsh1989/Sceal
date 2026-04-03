//
//  NSTextView+EditorLayout.swift
//

// Shared legacy layout helpers used to centralize TextKit 1 geometry queries.

import AppKit

extension NSTextView {
  // Ensures the current text storage has layout through the end of the document.
  func ensureEditorLayoutForEntireDocument() {
    guard let textStorage, textStorage.length > 0 else { return }
    ensureEditorLayout(forCharacterRange: NSRange(location: 0, length: textStorage.length))
  }

  // Ensures layout is up to date for a specific character range.
  func ensureEditorLayout(forCharacterRange range: NSRange) {
    layoutManager?.ensureLayout(forCharacterRange: range)
  }

  // Resolves the visual rect for a character range in text view coordinates.
  func editorRect(forCharacterRange range: NSRange) -> NSRect? {
    guard
      range.length > 0,
      let layoutManager,
      let textContainer
    else { return nil }

    let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
    return layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
  }

  // Resolves the used line fragment rect containing the given character location.
  func editorLineFragmentRect(forCharacterLocation location: Int) -> NSRect? {
    guard
      let layoutManager,
      let textContainer
    else { return nil }

    layoutManager.ensureLayout(for: textContainer)
    let clampedLocation = min(max(location, 0), string.utf16.count)
    let glyphCharacterLocation = max(clampedLocation - 1, 0)
    let glyphIndex = layoutManager.glyphIndexForCharacter(at: glyphCharacterLocation)
    var lineRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil)
    lineRect.origin.x += textContainerOrigin.x
    lineRect.origin.y += textContainerOrigin.y

    if lineRect.width < 1 {
      lineRect.size.width = 1
    }

    return lineRect
  }
}
