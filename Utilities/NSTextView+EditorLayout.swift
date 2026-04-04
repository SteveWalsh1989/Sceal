//
//  NSTextView+EditorLayout.swift
//

// Shared TextKit 2 layout helpers for editor geometry queries.

import AppKit

extension NSTextView {
  // Ensures the current text storage has layout through the end of the document.
  func ensureEditorLayoutForEntireDocument() {
    guard let textStorage, textStorage.length > 0 else { return }
    ensureEditorLayout(forCharacterRange: NSRange(location: 0, length: textStorage.length))
  }

  // Ensures layout is up to date for a specific character range.
  func ensureEditorLayout(forCharacterRange range: NSRange) {
    guard
      let textLayoutManager,
      let textRange = editorTextRange(forCharacterRange: range)
    else { return }

    textLayoutManager.ensureLayout(for: textRange)
  }

  // Invalidates layout and rendering state for a specific character range.
  func invalidateEditorLayout(forCharacterRange range: NSRange) {
    guard
      let textLayoutManager,
      let textRange = editorTextRange(forCharacterRange: range)
    else { return }

    textLayoutManager.invalidateLayout(for: textRange)
    textLayoutManager.invalidateRenderingAttributes(for: textRange)
  }

  // Resolves the visual rect for a character range in text view coordinates.
  func editorRect(forCharacterRange range: NSRange) -> NSRect? {
    guard range.length > 0 else { return nil }

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

    return editorRect(forCharacterRange: range) != nil
  }

  // Resolves the midline position of a character range in text view coordinates.
  func editorMidYInViewCoordinates(forCharacterRange range: NSRange) -> CGFloat? {
    editorRectInViewCoordinates(forCharacterRange: range)?.midY
  }

  // Resolves the used line fragment rect containing the given character location.
  func editorLineFragmentRect(forCharacterLocation location: Int) -> NSRect? {
    let clampedLocation = min(max(location, 0), string.utf16.count)

    guard
      let textLayoutManager,
      let textContentManager = textLayoutManager.textContentManager
    else { return nil }

    let charOffset = max(clampedLocation - 1, 0)
    guard
      let targetLocation = textContentManager.location(
        textContentManager.documentRange.location,
        offsetBy: charOffset
      ),
      let fragment = textLayoutManager.textLayoutFragment(for: targetLocation)
    else { return nil }

    let fragmentOriginY = fragment.layoutFragmentFrame.origin.y
    let fragmentCharStart = textContentManager.offset(
      from: textContentManager.documentRange.location,
      to: fragment.rangeInElement.location
    )
    let relativeOffset = charOffset - fragmentCharStart
    if let lineFragment = fragment.textLineFragments.first(where: { line in
      relativeOffset >= line.characterRange.location
        && relativeOffset < line.characterRange.location + line.characterRange.length
    }) ?? fragment.textLineFragments.first {
      var lineRect = NSRect(
        x: fragment.layoutFragmentFrame.origin.x + lineFragment.typographicBounds.origin.x,
        y: fragmentOriginY + lineFragment.typographicBounds.origin.y,
        width: lineFragment.typographicBounds.width,
        height: lineFragment.typographicBounds.height
      )
      lineRect.origin.x += textContainerOrigin.x
      lineRect.origin.y += textContainerOrigin.y
      if lineRect.width < 1 { lineRect.size.width = 1 }
      return lineRect
    }

    return nil
  }

  // Resolves a character index for a point already converted into text-container coordinates.
  func editorCharacterIndex(forTextContainerPoint point: NSPoint) -> Int? {
    guard
      let textLayoutManager,
      let textContentManager = textLayoutManager.textContentManager
    else { return nil }

    // Find the layout fragment containing the point by enumerating all fragments.
    var matchedFragment: NSTextLayoutFragment?
    textLayoutManager.enumerateTextLayoutFragments(
      from: textContentManager.documentRange.location,
      options: [.ensuresLayout]
    ) { fragment in
      if fragment.layoutFragmentFrame.contains(point) {
        matchedFragment = fragment
        return false
      }
      return fragment.layoutFragmentFrame.origin.y <= point.y
    }

    guard let fragment = matchedFragment else { return nil }

    let localPoint = NSPoint(
      x: point.x - fragment.layoutFragmentFrame.origin.x,
      y: point.y - fragment.layoutFragmentFrame.origin.y
    )

    let resolvedLocation: NSTextLocation
    if let lineFragment = fragment.textLineFragments.first(where: {
      $0.typographicBounds.contains(localPoint)
    }) {
      let charOffset = lineFragment.characterIndex(for: localPoint)
      resolvedLocation =
        textContentManager.location(fragment.rangeInElement.location, offsetBy: charOffset)
        ?? fragment.rangeInElement.location
    } else {
      resolvedLocation = fragment.rangeInElement.location
    }

    return textContentManager.offset(
      from: textContentManager.documentRange.location,
      to: resolvedLocation
    )
  }

  // Resolves a character index for a point in text-view coordinates.
  func editorCharacterIndex(forViewPoint point: NSPoint) -> Int? {
    let characterIndex = characterIndexForInsertion(at: point)
    guard characterIndex != NSNotFound else { return nil }
    return min(max(characterIndex, 0), string.utf16.count)
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
