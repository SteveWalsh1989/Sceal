//
//  NSTextView+EditorInteractions.swift
//

// Shared editor interaction helpers for divider navigation and checkbox toggling.

import AppKit

enum DividerResolutionPreference {
  case previous
  case next
  case nearest
}

extension NSTextView {
  // Moves an insertion point out of a structural line to the nearest editable position.
  @discardableResult
  func editorNormalizeSelectionIfNeeded(
    prefer preference: DividerResolutionPreference = .nearest
  ) -> Bool {
    let currentSelection = selectedRange()
    guard currentSelection.length == 0 else { return false }

    let resolvedLocation = editorResolvedInsertionLocation(
      for: currentSelection.location,
      prefer: preference
    )
    guard resolvedLocation != currentSelection.location else { return false }

    setSelectedRange(NSRange(location: resolvedLocation, length: 0))
    return true
  }

  // Detects when a click lands on a divider line and resolves to the nearest editable side.
  func editorDividerSelectionLocation(
    for charIndex: Int,
    atViewPoint point: NSPoint
  ) -> Int? {
    guard let textStorage, textStorage.length > 0 else { return nil }

    let clampedIndex = min(max(charIndex, 0), textStorage.length - 1)
    let candidateIndexes = [clampedIndex, max(clampedIndex - 1, 0)]

    for candidateIndex in candidateIndexes {
      let lineRange = (string as NSString).lineRange(
        for: NSRange(location: candidateIndex, length: 0)
      )
      guard editorLineHasSectionDivider(lineRange) else { continue }

      guard let dividerRect = editorRectInViewCoordinates(forCharacterRange: lineRange) else {
        continue
      }
      guard dividerRect.insetBy(dx: -textContainerInset.width, dy: -6).contains(point) else {
        continue
      }

      let upperHalf = isFlipped ? point.y < dividerRect.midY : point.y > dividerRect.midY
      let preference: DividerResolutionPreference = upperHalf ? .previous : .next
      return editorResolvedInsertionLocation(for: candidateIndex, prefer: preference)
    }

    return nil
  }

  // Toggles a checkbox between checked and unchecked states.
  @discardableResult
  func editorToggleCheckbox(
    at charIndex: Int,
    appearanceSettings: NoteAppearanceSettings,
    markerColor: NSColor? = nil
  ) -> Bool {
    guard let textStorage else { return false }

    let nsString = textStorage.string as NSString
    let lineRange = nsString.lineRange(for: NSRange(location: charIndex, length: 0))
    var textRange = lineRange
    if textRange.length > 0,
      nsString.character(at: textRange.location + textRange.length - 1) == 0x0A
    {
      textRange.length -= 1
    }

    let indentLevel =
      textStorage.attribute(.markdownIndentLevel, at: textRange.location, effectiveRange: nil)
      as? Int ?? 0

    let currentTypeRaw =
      textStorage.attribute(.markdownListType, at: charIndex, effectiveRange: nil) as? String
    let isChecked = currentTypeRaw == MarkdownListType.checkboxChecked.rawValue

    let handled = performEditorEdit(
      affectedRange: textRange,
      actionName: isChecked ? "Uncheck Item" : "Check Item"
    ) { textStorage in
      let newAttachment =
        markerColor.map {
          MarkdownEditorFormatter.checkboxAttachment(checked: !isChecked, color: $0)
        }
        ?? MarkdownEditorFormatter.checkboxAttachment(
          checked: !isChecked,
          appearance: appearanceSettings
        )
      let attachmentString = NSAttributedString(attachment: newAttachment)
      textStorage.replaceCharacters(
        in: NSRange(location: charIndex, length: 1),
        with: attachmentString
      )

      let updatedString = textStorage.string as NSString
      let updatedLineRange = updatedString.lineRange(
        for: NSRange(location: charIndex, length: 0)
      )
      var updatedTextRange = updatedLineRange
      if updatedTextRange.length > 0,
        updatedString.character(
          at: updatedTextRange.location + updatedTextRange.length - 1
        ) == 0x0A
      {
        updatedTextRange.length -= 1
      }

      let newType: MarkdownListType = isChecked ? .checkboxUnchecked : .checkboxChecked
      textStorage.addAttribute(
        .markdownListType,
        value: newType.rawValue,
        range: updatedTextRange
      )
      let listStyle = MarkdownEditorFormatter.listParagraphStyle(
        for: appearanceSettings, indentLevel: indentLevel)
      textStorage.addAttribute(.paragraphStyle, value: listStyle, range: updatedTextRange)
      textStorage.addAttribute(.markdownIndentLevel, value: indentLevel, range: updatedTextRange)

      let contentStart = min(charIndex + 2, updatedTextRange.location + updatedTextRange.length)
      let contentLength = (updatedTextRange.location + updatedTextRange.length) - contentStart
      if contentLength > 0 {
        let contentRange = NSRange(location: contentStart, length: contentLength)
        if isChecked {
          textStorage.removeAttribute(.strikethroughStyle, range: contentRange)
        } else {
          textStorage.addAttribute(
            .strikethroughStyle,
            value: NSUnderlineStyle.single.rawValue,
            range: contentRange
          )
        }
      }

      return nil
    }

    return handled
  }

  // Resolves a divider-crossing insertion point to the nearest editable location.
  func editorResolvedInsertionLocation(
    for proposedLocation: Int,
    prefer preference: DividerResolutionPreference
  ) -> Int {
    if let promptBoundary = editorPromptBoundary(
      containingInsertionLocation: proposedLocation
    ) {
      if MarkdownEditorPromptBlockMarkdown.isStartBoundaryKind(promptBoundary.kind) {
        return editorNextEditableInsertionLocation(after: promptBoundary.lineRange)
          ?? promptBoundary.lineRange.location
      }

      return editorPreviousEditableInsertionLocation(before: promptBoundary.lineRange)
        ?? NSMaxRange(promptBoundary.lineRange)
    }

    guard
      let dividerLineRange = editorSectionDividerLineRange(
        containingInsertionLocation: proposedLocation
      )
    else {
      return min(max(proposedLocation, 0), textStorage?.length ?? 0)
    }

    let previousLocation = editorPreviousEditableInsertionLocation(before: dividerLineRange)
    let nextLocation = editorNextEditableInsertionLocation(after: dividerLineRange)

    switch preference {
    case .previous:
      return previousLocation ?? nextLocation ?? dividerLineRange.location
    case .next:
      return nextLocation ?? previousLocation ?? dividerLineRange.location
    case .nearest:
      let clampedLocation = min(max(proposedLocation, 0), textStorage?.length ?? 0)
      switch (previousLocation, nextLocation) {
      case (let previous?, let next?):
        return abs(clampedLocation - previous) <= abs(next - clampedLocation) ? previous : next
      case (let previous?, nil):
        return previous
      case (nil, let next?):
        return next
      default:
        return dividerLineRange.location
      }
    }
  }

  // Finds a hidden prompt boundary line containing the proposed insertion point.
  private func editorPromptBoundary(
    containingInsertionLocation location: Int
  ) -> (lineRange: NSRange, kind: String)? {
    guard let textStorage, textStorage.length > 0 else { return nil }

    let nsString = string as NSString
    let clampedLocation = min(max(location, 0), textStorage.length)
    if clampedLocation == textStorage.length,
      nsString.character(at: textStorage.length - 1) == 0x0A
    {
      return nil
    }
    let lineProbe = min(clampedLocation, textStorage.length - 1)

    let lineRange = nsString.lineRange(for: NSRange(location: lineProbe, length: 0))
    let trimmedRange = editorTrimmedLineRange(from: lineRange, in: nsString)
    guard trimmedRange.length > 0 else { return nil }

    var boundaryKind: String?
    textStorage.enumerateAttribute(
      .markdownPromptBoundaryKind,
      in: trimmedRange,
      options: []
    ) { value, _, stop in
      guard let kind = value as? String else { return }
      boundaryKind = kind
      stop.pointee = true
    }

    guard let boundaryKind else { return nil }

    return (lineRange, boundaryKind)
  }

  private func editorSectionDividerLineRange(
    containingInsertionLocation location: Int
  ) -> NSRange? {
    guard let textStorage, textStorage.length > 0 else { return nil }

    let nsString = string as NSString
    let clampedLocation = min(max(location, 0), textStorage.length)
    if clampedLocation == textStorage.length { return nil }

    let lineRange = nsString.lineRange(for: NSRange(location: clampedLocation, length: 0))
    return editorLineHasSectionDivider(lineRange) ? lineRange : nil
  }

  private func editorPreviousEditableInsertionLocation(before structuralLineRange: NSRange) -> Int?
  {
    guard structuralLineRange.location > 0 else { return nil }

    let nsString = string as NSString
    var searchLocation = structuralLineRange.location - 1

    while searchLocation >= 0 {
      let lineRange = nsString.lineRange(for: NSRange(location: searchLocation, length: 0))
      if editorLineHasSectionDivider(lineRange) {
        guard lineRange.location > 0 else { return nil }
        searchLocation = lineRange.location - 1
        continue
      }

      return NSMaxRange(editorTrimmedLineRange(from: lineRange, in: nsString))
    }

    return nil
  }

  private func editorNextEditableInsertionLocation(after structuralLineRange: NSRange) -> Int? {
    let nsString = string as NSString
    var searchLocation = NSMaxRange(structuralLineRange)

    while searchLocation < nsString.length {
      let lineRange = nsString.lineRange(for: NSRange(location: searchLocation, length: 0))
      if !editorLineHasSectionDivider(lineRange) {
        return lineRange.location
      }
      searchLocation = NSMaxRange(lineRange)
    }

    return nsString.length
  }

  private func editorLineHasSectionDivider(_ lineRange: NSRange) -> Bool {
    editorLineHasAttribute(.markdownSectionDivider, in: lineRange)
  }

  private func editorLineHasAttribute(
    _ key: NSAttributedString.Key,
    in lineRange: NSRange
  ) -> Bool {
    guard let textStorage else { return false }

    let trimmedRange = editorTrimmedLineRange(from: lineRange, in: string as NSString)
    guard trimmedRange.length > 0, trimmedRange.location < textStorage.length else { return false }

    return textStorage.attribute(key, at: trimmedRange.location, effectiveRange: nil) as? Bool
      == true
  }

  private func editorTrimmedLineRange(from lineRange: NSRange, in nsString: NSString) -> NSRange {
    var trimmedRange = lineRange
    if trimmedRange.length > 0,
      nsString.character(at: trimmedRange.location + trimmedRange.length - 1) == 0x0A
    {
      trimmedRange.length -= 1
    }
    return trimmedRange
  }
}
