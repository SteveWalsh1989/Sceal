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
    if let layoutManager {
      layoutManager.ensureLayout(forCharacterRange: range)
      return
    }

    guard
      let textLayoutManager,
      let textRange = editorTextRange(forCharacterRange: range)
    else { return }

    textLayoutManager.ensureLayout(for: textRange)
  }

  // Resolves the visual rect for a character range in text view coordinates.
  func editorRect(forCharacterRange range: NSRange) -> NSRect? {
    guard range.length > 0 else { return nil }

    if let layoutManager, let textContainer {
      let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
      return layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
    }

    guard
      let textLayoutManager,
      let textRange = editorTextRange(forCharacterRange: range)
    else { return nil }

    textLayoutManager.ensureLayout(for: textRange)
    var combinedRect: NSRect?
    textLayoutManager.enumerateTextSegments(
      in: textRange,
      type: .standard,
      options: []
    ) { _, textSegmentFrame, _, _ in
      combinedRect = combinedRect?.union(textSegmentFrame) ?? textSegmentFrame
      return true
    }
    return combinedRect
  }

  // Resolves the visual rect for a character range in text view coordinates.
  func editorRectInViewCoordinates(forCharacterRange range: NSRange) -> NSRect? {
    guard var rect = editorRect(forCharacterRange: range) else { return nil }
    rect.origin.x += textContainerOrigin.x
    rect.origin.y += textContainerOrigin.y
    return rect
  }

  // Reports whether the layout manager produced visible glyphs for the given range.
  func editorHasVisibleGlyphs(forCharacterRange range: NSRange) -> Bool {
    guard range.length > 0 else { return false }

    if let layoutManager {
      let glyphRange = layoutManager.glyphRange(
        forCharacterRange: range,
        actualCharacterRange: nil
      )
      return glyphRange.length > 0
    }

    return editorRect(forCharacterRange: range) != nil
  }

  // Resolves the midline position of a character range in text view coordinates.
  func editorMidYInViewCoordinates(forCharacterRange range: NSRange) -> CGFloat? {
    editorRectInViewCoordinates(forCharacterRange: range)?.midY
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

  // Resolves a character index for a point already converted into text-container coordinates.
  func editorCharacterIndex(forTextContainerPoint point: NSPoint) -> Int? {
    guard
      let layoutManager,
      let textContainer
    else { return nil }

    return layoutManager.characterIndex(
      for: point,
      in: textContainer,
      fractionOfDistanceBetweenInsertionPoints: nil
    )
  }

  private func editorTextRange(forCharacterRange range: NSRange) -> NSTextRange? {
    guard
      let textLayoutManager,
      let textContentManager = textLayoutManager.textContentManager
    else { return nil }

    let maxLength = string.utf16.count
    let safeLocation = min(max(range.location, 0), maxLength)
    let safeLength = min(max(range.length, 0), max(maxLength - safeLocation, 0))
    let documentRange = textContentManager.documentRange

    guard
      let startLocation = textContentManager.location(
        documentRange.location,
        offsetBy: safeLocation
      ),
      let endLocation = textContentManager.location(
        documentRange.location,
        offsetBy: safeLocation + safeLength
      )
    else { return nil }

    return NSTextRange(location: startLocation, end: endLocation)
  }
}
