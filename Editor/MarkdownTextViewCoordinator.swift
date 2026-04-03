//
//  MarkdownTextViewCoordinator.swift
//

// NSTextViewDelegate handling text changes, Enter key, slash commands, and autoformat.

import AppKit
import SwiftUI

// MARK: - Coordinator

extension MarkdownTextView {

  class Coordinator: NSObject, NSTextViewDelegate {
    private struct PendingEditContext {
      let range: NSRange
      let replacementString: String?
    }

    var parent: MarkdownTextView
    var isUpdating = false
    var lastPushedMarkdown = ""
    var lastAppliedAppearance = NoteAppearanceSettings.default
    var lastDividerCount = 0
    var lastNoteID: DayNote.ID?
    let toolbar = FormattingToolbar()
    let slashPopup = SlashCommandPopup()
    private var slashTriggerLocation: Int?
    private var pendingEditContext: PendingEditContext?
    private var isApplyingSlashCommand = false

    init(parent: MarkdownTextView) {
      self.parent = parent
      toolbar.appearanceSettings = parent.appearanceSettings
    }

    // Captures the pending edit context before AppKit applies the change.
    func textView(
      _: NSTextView,
      shouldChangeTextIn affectedCharRange: NSRange,
      replacementString: String?
    ) -> Bool {
      pendingEditContext = PendingEditContext(
        range: affectedCharRange,
        replacementString: replacementString
      )
      return true
    }

    // Updates toolbar visibility and syncs typing attributes on selection change.
    func textViewDidChangeSelection(_ notification: Notification) {
      guard let textView = notification.object as? NSTextView else { return }
      if let scealTextView = textView as? ScealTextView,
        scealTextView.normalizeSelectionIfNeeded()
      {
        return
      }

      let range = textView.selectedRange()

      // Dismiss slash popup if cursor moved away from the trigger line
      if slashPopup.isVisible, let triggerLoc = slashTriggerLocation {
        let nsString = textView.string as NSString
        let triggerLine = nsString.lineRange(for: NSRange(location: triggerLoc, length: 0))
        let cursorLine = nsString.lineRange(for: NSRange(location: range.location, length: 0))
        if triggerLine != cursorLine || range.length > 0 {
          dismissSlashPopup()
        }
      }

      if range.length > 0, let scrollView = textView.enclosingScrollView {
        let glyphRange =
          textView.layoutManager?.glyphRange(
            forCharacterRange: range, actualCharacterRange: nil) ?? range
        guard let textContainer = textView.textContainer else { return }
        let selectionRect =
          textView.layoutManager?.boundingRect(
            forGlyphRange: glyphRange, in: textContainer) ?? .zero
        let rectInScrollView = textView.convert(selectionRect, to: scrollView)

        toolbar.textView = textView
        toolbar.show(relativeTo: rectInScrollView, in: scrollView)
      } else {
        toolbar.hide()
      }

      // Keep typing attributes in sync so new text inherits correct font/color,
      // not bare system defaults from unformatted newline characters.
      if range.length == 0, let textStorage = textView.textStorage {
        syncTypingAttributesToInsertionPoint(in: textView, textStorage: textStorage)
      }
    }

    // Converts display text back to markdown and pushes to the SwiftUI binding.
    func textDidChange(_ notification: Notification) {
      guard !isUpdating else { return }
      guard let textView = notification.object as? NSTextView,
        let textStorage = textView.textStorage
      else { return }

      isUpdating = true
      // Skip auto-formatting during slash command application to prevent cascading
      // text mutations that invalidate ranges between the two performEditorEdit calls.
      if !isApplyingSlashCommand {
        autoformatEditedLinesIfNeeded(in: textView, textStorage: textStorage)
      }
      let markdown = MarkdownStyler.convertToMarkdown(from: textStorage)
      lastPushedMarkdown = markdown
      parent.text = markdown
      isUpdating = false

      // Force full background redraw for section card updates (e.g., backspace deleting a divider)
      if let scealTextView = textView as? ScealTextView {
        let dividerCount = scealTextView.sectionDividerCount
        if dividerCount != lastDividerCount {
          scealTextView.refreshSectionLayout()
        } else {
          textView.setNeedsDisplay(textView.bounds)
        }
        lastDividerCount = dividerCount
      } else {
        textView.setNeedsDisplay(textView.bounds)
      }

      if isApplyingSlashCommand {
        dismissSlashPopup()
      } else {
        checkSlashCommandTrigger(in: textView)
      }
    }

    // Handles Enter, Tab, Backspace, and slash popup navigation.
    func textView(
      _ textView: NSTextView,
      doCommandBy commandSelector: Selector
    ) -> Bool {
      // Intercept navigation keys while slash command popup is visible
      if slashPopup.isVisible {
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)):
          slashPopup.moveSelectionUp()
          return true
        case #selector(NSResponder.moveDown(_:)):
          slashPopup.moveSelectionDown()
          return true
        case #selector(NSResponder.insertNewline(_:)):
          slashPopup.confirmSelection()
          return true
        case #selector(NSResponder.cancelOperation(_:)):
          dismissSlashPopup()
          return true
        default:
          break
        }
      }

      // Handle Tab/Shift-Tab for list indentation
      if commandSelector == #selector(NSResponder.insertTab(_:)) {
        return handleListIndent(textView: textView, increase: true)
      }
      if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
        return handleListIndent(textView: textView, increase: false)
      }
      if commandSelector == #selector(NSResponder.deleteBackward(_:)),
        let textStorage = textView.textStorage,
        handleSectionDividerBackspace(in: textView, textStorage: textStorage)
      {
        return true
      }

      guard commandSelector == #selector(NSResponder.insertNewline(_:)),
        let textStorage = textView.textStorage
      else {
        return false
      }

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
        return textView.performEditorEdit(
          affectedRange: lineRange,
          replacementString: "",
          actionName: "Remove List Marker"
        ) { textStorage in
          removeListMarker(in: textStorage, lineRange: lineRange)
          return NSRange(location: lineRange.location, length: 0)
        }
      }

      // Check if the line is an empty blockquote → cancel continuation
      if isEmptyBlockquoteLine(lineText, in: textStorage, at: lineRange) {
        return textView.performEditorEdit(
          affectedRange: lineRange,
          replacementString: "",
          actionName: "Remove Blockquote"
        ) { textStorage in
          textStorage.replaceCharacters(in: lineRange, with: "")
          return NSRange(location: lineRange.location, length: 0)
        }
      }

      let slashCommand = SlashCommandHandler.matchedCommand(in: textStorage, lineRange: lineRange)
      if let slashCommand {
        switch slashCommand.action {
        case .sectionDivider:
          // Insert the final divider display directly so AppKit never sees the raw marker length.
          // Adds a blank line after the divider so the heading starts visually separated.
          let replacementRange = fullLineRange.length > lineRange.length ? fullLineRange : lineRange
          let baseAttrs = MarkdownStyler.baseTypingAttributes(for: parent.appearanceSettings)
          let dividerLine = NSMutableAttributedString(
            attributedString: MarkdownStyler.sectionDividerDisplayString(
              appearance: parent.appearanceSettings))
          dividerLine.append(NSAttributedString(string: "\n", attributes: baseAttrs))
          dividerLine.append(NSAttributedString(string: "\n", attributes: baseAttrs))

          let handled = textView.performEditorEdit(
            affectedRange: replacementRange,
            replacementString: dividerLine.string,
            actionName: "Insert Section Divider"
          ) { textStorage in
            textStorage.replaceCharacters(in: replacementRange, with: dividerLine)
            return NSRange(location: replacementRange.location + dividerLine.length, length: 0)
          }

          guard handled else { return false }

          if let scealTextView = textView as? ScealTextView {
            _ = scealTextView.normalizeSelectionIfNeeded(prefer: .next)
            scealTextView.refreshSectionLayout()
          } else {
            textView.layoutManager?.ensureLayout(
              forCharacterRange: NSRange(location: 0, length: textStorage.length))
            textView.setNeedsDisplay(textView.bounds)
          }

          textView.typingAttributes = headingTypingAttributes(level: 1)
          return true
        case .heading(let level):
          let handled = textView.performEditorEdit(
            affectedRange: lineRange,
            replacementString: "",
            actionName: "Insert Heading"
          ) { textStorage in
            replaceCurrentLine(in: textStorage, lineRange: lineRange, with: NSAttributedString())
            return NSRange(location: lineRange.location, length: 0)
          }
          if handled {
            textView.typingAttributes = headingTypingAttributes(level: level)
          }
          return handled
        case .codeBlock:
          let snippet = "```\n\n\n```"
          let displaySnippet = MarkdownStyler.formatForDisplay(
            snippet, appearance: parent.appearanceSettings)
          let handled = textView.performEditorEdit(
            affectedRange: lineRange,
            replacementString: snippet,
            actionName: "Insert Code Block"
          ) { textStorage in
            replaceCurrentLine(in: textStorage, lineRange: lineRange, with: displaySnippet)
            return NSRange(location: lineRange.location + 4, length: 0)
          }
          if handled {
            textView.typingAttributes = codeBlockTypingAttributes()
            textView.setNeedsDisplay(textView.bounds)
          }
          return handled
        }
      }
      var continuedListType: MarkdownListType?
      var continuedBlockquote = false
      // Carry forward indent level from the current line
      let currentIndentLevel: Int = {
        guard lineRange.length > 0 else { return 0 }
        return textStorage.attribute(
          .markdownIndentLevel, at: lineRange.location, effectiveRange: nil)
          as? Int ?? 0
      }()
      // Track whether the cursor is mid-line so we split there instead of at line end.
      let cursorOffsetInLine = cursorLocation - lineRange.location
      let cursorAtLineEnd = cursorOffsetInLine >= lineRange.length

      let handled = textView.performEditorEdit(
        affectedRange: lineRange,
        replacementString: "\n",
        actionName: "Insert Newline"
      ) { textStorage in
        let priorLineLength = lineRange.length
        continuedListType = MarkdownStyler.formatCurrentLine(
          in: textStorage,
          lineRange: lineRange,
          appearance: parent.appearanceSettings
        )

        let formattedNS = textStorage.string as NSString
        let formattedFullRange = formattedNS.lineRange(
          for: NSRange(location: min(lineRange.location, max(formattedNS.length - 1, 0)), length: 0)
        )
        let formattedLineEnd = min(NSMaxRange(formattedFullRange), formattedNS.length)
        var formattedLineLength = formattedLineEnd - lineRange.location
        if formattedLineLength > 0,
          formattedNS.character(at: lineRange.location + formattedLineLength - 1) == 0x0A
        {
          formattedLineLength -= 1
        }

        // Determine split point: end of line or mapped cursor position
        let splitPoint: Int
        if cursorAtLineEnd {
          splitPoint = lineRange.location + formattedLineLength
        } else {
          let delta = formattedLineLength - priorLineLength
          let adjustedOffset = max(0, min(cursorOffsetInLine + delta, formattedLineLength))
          splitPoint = lineRange.location + adjustedOffset
        }

        let newlineAttrs = MarkdownStyler.baseTypingAttributes(for: parent.appearanceSettings)
        textStorage.insert(
          NSAttributedString(string: "\n", attributes: newlineAttrs), at: splitPoint)
        var nextInsertionLocation = splitPoint + 1

        let updatedNS = textStorage.string as NSString
        let updatedLine = updatedNS.lineRange(
          for: NSRange(location: min(lineRange.location, max(updatedNS.length - 1, 0)), length: 0))
        if updatedLine.length > 0, updatedLine.location < textStorage.length {
          continuedBlockquote =
            textStorage.attribute(
              .markdownBlockquote,
              at: updatedLine.location,
              effectiveRange: nil
            ) as? Bool == true
        }

        if let listType = continuedListType {
          let marker = continuationMarker(for: listType, previousLineText: lineText)
          if !marker.isEmpty {
            let markerAttr = continuationAttributedMarker(
              for: listType,
              marker: marker,
              appearance: parent.appearanceSettings,
              indentLevel: currentIndentLevel
            )
            textStorage.insert(markerAttr, at: nextInsertionLocation)
            nextInsertionLocation += markerAttr.length
          }
        }

        return NSRange(location: nextInsertionLocation, length: 0)
      }

      guard handled else { return false }

      if let scealTextView = textView as? ScealTextView {
        _ = scealTextView.normalizeSelectionIfNeeded(prefer: .previous)
      }

      // Blockquote continuation — set typing attributes so the next line inherits blockquote style
      if continuedBlockquote, continuedListType == nil {
        textView.typingAttributes = [
          .font: parent.appearanceSettings.bodyFont,
          .foregroundColor: NSColor.secondaryLabelColor,
          .paragraphStyle: MarkdownStyler.blockquoteParagraphStyle(for: parent.appearanceSettings),
          .markdownBlockquote: true,
        ]
      } else if continuedListType == nil {
        textView.typingAttributes = MarkdownStyler.baseTypingAttributes(
          for: parent.appearanceSettings)
      }

      // Force immediate redraw so section card backgrounds update on this frame
      if let scealTextView = textView as? ScealTextView {
        scealTextView.refreshSectionLayout()
      } else {
        textView.layoutManager?.ensureLayout(
          forCharacterRange: NSRange(location: 0, length: textStorage.length))
        textView.setNeedsDisplay(textView.bounds)
      }

      return true
    }

    // MARK: - List Continuation Helpers

    // Checks if a blockquote line has no content (just the blockquote attribute with empty text)
    private func isEmptyBlockquoteLine(
      _ lineText: String, in textStorage: NSTextStorage, at lineRange: NSRange
    ) -> Bool {
      guard lineRange.length >= 0, lineRange.location < textStorage.length else { return false }
      let isQuote =
        lineRange.length > 0
        ? textStorage.attribute(.markdownBlockquote, at: lineRange.location, effectiveRange: nil)
          as? Bool == true
        : false
      guard isQuote else { return false }
      return lineText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // Checks if a line contains only a list marker with no content.
    private func isEmptyListItem(_ lineText: String) -> Bool {
      let trimmed = lineText.trimmingCharacters(in: .whitespaces)
      let emptyMarkers = [
        "\(MarkdownStyler.bulletMarker) ",
        "\(MarkdownStyler.bulletMarker)",
        "\(MarkdownStyler.attachmentChar) ",
        "\(MarkdownStyler.attachmentChar)",
        "- ",
        "-",
      ]
      if emptyMarkers.contains(trimmed) { return true }
      if trimmed.range(of: #"^\d+\.\s*$"#, options: .regularExpression) != nil { return true }
      return false
    }

    // Deletes the divider above when Backspace is pressed from the next line start.
    private func handleSectionDividerBackspace(in textView: NSTextView, textStorage: NSTextStorage)
      -> Bool
    {
      let selection = textView.selectedRange()
      guard selection.length == 0 else { return false }

      let nsString = textStorage.string as NSString
      guard selection.location > 0, nsString.length > 0 else { return false }

      let currentLocation = min(selection.location, nsString.length)
      let currentLineProbe = min(currentLocation, max(nsString.length - 1, 0))
      let currentLineRange = nsString.lineRange(
        for: NSRange(location: currentLineProbe, length: 0))
      guard currentLocation == currentLineRange.location else { return false }

      let previousLineRange = nsString.lineRange(
        for: NSRange(location: currentLocation - 1, length: 0))
      guard lineHasSectionDivider(previousLineRange, in: textStorage, string: nsString) else {
        return false
      }

      let handled = textView.performEditorEdit(
        affectedRange: previousLineRange,
        replacementString: "",
        actionName: "Delete Section Divider"
      ) { textStorage in
        textStorage.replaceCharacters(in: previousLineRange, with: "")
        return NSRange(location: previousLineRange.location, length: 0)
      }

      guard handled else { return false }

      if let scealTextView = textView as? ScealTextView {
        scealTextView.refreshSectionLayout()
      } else {
        textView.setNeedsDisplay(textView.bounds)
      }

      return true
    }

    // Checks if a line carries the section divider attribute.
    private func lineHasSectionDivider(
      _ lineRange: NSRange,
      in textStorage: NSTextStorage,
      string nsString: NSString
    ) -> Bool {
      var trimmedRange = lineRange
      if trimmedRange.length > 0,
        nsString.character(at: trimmedRange.location + trimmedRange.length - 1) == 0x0A
      {
        trimmedRange.length -= 1
      }

      guard trimmedRange.length > 0, trimmedRange.location < textStorage.length else {
        return false
      }
      return textStorage.attribute(
        .markdownSectionDivider, at: trimmedRange.location, effectiveRange: nil)
        as? Bool == true
    }

    // Deletes a list marker line when Enter cancels continuation.
    private func removeListMarker(in textStorage: NSTextStorage, lineRange: NSRange) {
      textStorage.replaceCharacters(in: lineRange, with: "")
    }

    // Returns the display marker for continuing a list on the next line.
    private func continuationMarker(for listType: MarkdownListType, previousLineText: String)
      -> String
    {
      switch listType {
      case .bullet:
        return "\(MarkdownStyler.bulletMarker) "
      case .checkboxUnchecked, .checkboxChecked:
        return "\(MarkdownStyler.uncheckedMarker) "
      case .numbered:
        if let match = previousLineText.range(of: #"^(\d+)\."#, options: .regularExpression) {
          let numStr = previousLineText[match].dropLast()
          if let num = Int(numStr) { return "\(num + 1). " }
        }
        return "1. "
      }
    }

    // Builds a styled attributed string for a list continuation marker.
    private func continuationAttributedMarker(
      for listType: MarkdownListType, marker: String, appearance: NoteAppearanceSettings,
      indentLevel: Int = 0
    ) -> NSAttributedString {
      let listStyle = MarkdownStyler.listParagraphStyle(for: appearance, indentLevel: indentLevel)
      switch listType {
      case .checkboxUnchecked, .checkboxChecked:
        let result = NSMutableAttributedString()
        result.append(
          MarkdownStyler.checkboxAttributedString(checked: false, appearance: appearance))
        result.append(
          NSAttributedString(
            string: " ",
            attributes: [
              .font: appearance.bodyFont,
              .foregroundColor: NSColor.labelColor,
              .paragraphStyle: MarkdownStyler.bodyParagraphStyle(for: appearance),
            ]))
        let fullRange = NSRange(location: 0, length: result.length)
        result.addAttributes(
          [
            .markdownListType: MarkdownListType.checkboxUnchecked.rawValue,
            .paragraphStyle: listStyle,
            .markdownIndentLevel: indentLevel,
          ], range: fullRange)
        return result

      default:
        let result = NSMutableAttributedString(
          string: marker,
          attributes: [
            .font: appearance.bodyFont,
            .foregroundColor: NSColor.labelColor,
            .markdownListType: listType.rawValue,
            .paragraphStyle: listStyle,
            .markdownIndentLevel: indentLevel,
          ])
        if listType == .bullet {
          result.addAttributes(
            [
              .foregroundColor: MarkdownStyler.bulletColor(for: appearance),
              .font: NSFont.systemFont(ofSize: appearance.bulletSize, weight: .bold),
            ], range: NSRange(location: 0, length: 1))
        } else if listType == .numbered {
          if let numEnd = marker.firstIndex(of: ".") {
            let numLength = marker.distance(from: marker.startIndex, to: numEnd) + 1
            result.addAttribute(
              .foregroundColor, value: NSColor.secondaryLabelColor,
              range: NSRange(location: 0, length: numLength))
          }
        }
        return result
      }
    }

    // MARK: - List Indentation

    // Increases or decreases indent level on list lines covered by the selection
    private func handleListIndent(textView: NSTextView, increase: Bool) -> Bool {
      guard let textStorage = textView.textStorage else { return false }
      let nsString = textStorage.string as NSString
      let selectedRange = textView.selectedRange()
      let fullRange = nsString.lineRange(for: selectedRange)

      // Check if any line in the selection is a list item
      var hasListLine = false
      var scanStart = fullRange.location
      while scanStart < NSMaxRange(fullRange) {
        let lineRange = nsString.lineRange(for: NSRange(location: scanStart, length: 0))
        if lineRange.length > 0 {
          let attrs = textStorage.attributes(at: lineRange.location, effectiveRange: nil)
          if attrs[.markdownListType] as? String != nil {
            hasListLine = true
            break
          }
        }
        scanStart = NSMaxRange(lineRange)
      }

      guard hasListLine else { return false }

      let appearance = (textView as? ScealTextView)?.appearanceSettings ?? .default
      return textView.performEditorEdit(
        affectedRange: fullRange,
        actionName: increase ? "Indent" : "Outdent"
      ) { textStorage in
        var scanStart = fullRange.location
        while scanStart < NSMaxRange(fullRange) {
          let lineRange = nsString.lineRange(for: NSRange(location: scanStart, length: 0))
          var textRange = lineRange
          if textRange.length > 0
            && nsString.character(at: textRange.location + textRange.length - 1) == 0x0A
          {
            textRange.length -= 1
          }
          if textRange.length > 0 {
            let attrs = textStorage.attributes(at: textRange.location, effectiveRange: nil)
            if attrs[.markdownListType] as? String != nil {
              let currentLevel = attrs[.markdownIndentLevel] as? Int ?? 0
              let newLevel = increase ? min(currentLevel + 1, 3) : max(currentLevel - 1, 0)
              if newLevel != currentLevel {
                let newStyle = MarkdownStyler.listParagraphStyle(
                  for: appearance, indentLevel: newLevel)
                textStorage.addAttribute(.markdownIndentLevel, value: newLevel, range: textRange)
                textStorage.addAttribute(.paragraphStyle, value: newStyle, range: textRange)
              }
            }
          }
          scanStart = NSMaxRange(lineRange)
        }
        return nil
      }
    }

    // MARK: - Slash Command Popup

    // Filters and shows the slash command popup as the user types.
    private func checkSlashCommandTrigger(in textView: NSTextView) {
      let cursorLocation = textView.selectedRange().location
      guard cursorLocation > 0 else {
        dismissSlashPopup()
        return
      }

      let nsString = textView.string as NSString
      let lineRange = nsString.lineRange(for: NSRange(location: cursorLocation, length: 0))

      // Get text from line start to cursor
      let prefixLength = cursorLocation - lineRange.location
      guard prefixLength > 0 else {
        dismissSlashPopup()
        return
      }
      let prefixRange = NSRange(location: lineRange.location, length: prefixLength)
      let prefixText = nsString.substring(with: prefixRange)
      let trimmed = prefixText.trimmingCharacters(in: .whitespaces)

      // Must start with "/" and only have whitespace before it
      guard trimmed.hasPrefix("/") else {
        dismissSlashPopup()
        return
      }

      let filtered = SlashCommandHandler.filteredCommands(for: trimmed)
      guard !filtered.isEmpty else {
        dismissSlashPopup()
        return
      }

      // Track where the "/" character starts
      if slashTriggerLocation == nil {
        let whitespaceCount = prefixText.count - trimmed.count
        slashTriggerLocation = lineRange.location + whitespaceCount
      }

      slashPopup.updateFilter(trimmed)

      guard
        let scrollView = textView.enclosingScrollView,
        let lineRect = currentSlashCommandLineRect(in: textView, cursorLocation: cursorLocation)
      else { return }

      let rectInScrollView = textView.convert(lineRect, to: scrollView)
      slashPopup.show(relativeTo: rectInScrollView, in: scrollView)

      // Wire up selection callback (idempotent — closure captures current textView)
      slashPopup.onSelect = { [weak self, weak textView] entry in
        guard let self, let textView else { return }
        self.applySlashCommand(entry, in: textView)
      }
    }

    // Hides the slash command popup and clears the trigger location.
    private func dismissSlashPopup() {
      slashPopup.hide()
      slashTriggerLocation = nil
    }

    // Calculates the line rect for positioning the slash popup.
    private func currentSlashCommandLineRect(in textView: NSTextView, cursorLocation: Int)
      -> NSRect?
    {
      guard
        let layoutManager = textView.layoutManager,
        let textContainer = textView.textContainer
      else { return nil }

      layoutManager.ensureLayout(for: textContainer)
      let glyphCharacterLocation = max(cursorLocation - 1, 0)
      let glyphIndex = layoutManager.glyphIndexForCharacter(at: glyphCharacterLocation)
      var lineRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil)
      lineRect.origin.x += textView.textContainerOrigin.x
      lineRect.origin.y += textView.textContainerOrigin.y

      if lineRect.width < 1 {
        lineRect.size.width = 1
      }

      return lineRect
    }

    // Replaces a line's content in the text storage.
    private func replaceCurrentLine(
      in textStorage: NSTextStorage,
      lineRange: NSRange,
      with attributedString: NSAttributedString
    ) {
      textStorage.replaceCharacters(in: lineRange, with: attributedString)
    }

    // Returns typing attributes for a heading at the given level.
    private func headingTypingAttributes(level: Int) -> [NSAttributedString.Key: Any] {
      [
        .font: parent.appearanceSettings.boldBodyFont(
          ofSize: MarkdownStyler.headingFontSize(for: level)),
        .foregroundColor: NSColor.labelColor,
        .paragraphStyle: MarkdownStyler.bodyParagraphStyle(for: parent.appearanceSettings),
        .markdownHeadingLevel: level,
      ]
    }

    // Returns typing attributes for code block content.
    private func codeBlockTypingAttributes() -> [NSAttributedString.Key: Any] {
      [
        .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
        .backgroundColor: NSColor.quaternaryLabelColor,
        .foregroundColor: NSColor.labelColor,
        .markdownCodeBlock: true,
      ]
    }

    // Expand the popup selection into its full slash command, then reuse the normal Enter path.
    private func applySlashCommand(_ entry: SlashCommandEntry, in textView: NSTextView) {
      guard let triggerLoc = slashTriggerLocation else { return }
      let cursorLoc = textView.selectedRange().location
      guard cursorLoc >= triggerLoc else { return }

      let replaceRange = NSRange(location: triggerLoc, length: cursorLoc - triggerLoc)
      let undoManager = textView.undoManager
      undoManager?.beginUndoGrouping()
      isApplyingSlashCommand = true
      dismissSlashPopup()

      let replaced = textView.performEditorEdit(
        affectedRange: replaceRange,
        replacementString: entry.command
      ) { textStorage in
        // The popup may confirm after other edits have shifted the line, so clamp before replacing.
        let safeLoc = min(replaceRange.location, textStorage.length)
        let safeLen = min(replaceRange.length, max(textStorage.length - safeLoc, 0))
        let safeRange = NSRange(location: safeLoc, length: safeLen)
        textStorage.replaceCharacters(in: safeRange, with: entry.command)
        return NSRange(location: safeLoc + entry.command.utf16.count, length: 0)
      }
      defer {
        isApplyingSlashCommand = false
        undoManager?.endUndoGrouping()
        undoManager?.setActionName("Insert Slash Command")
      }

      if replaced {
        _ = self.textView(textView, doCommandBy: #selector(NSResponder.insertNewline(_:)))
      }
    }

    // Formats pasted or newly prefixed list syntax so existing lines behave like Diarly.
    private func autoformatEditedLinesIfNeeded(in textView: NSTextView, textStorage: NSTextStorage)
    {
      defer { pendingEditContext = nil }
      guard let pendingEditContext else { return }

      let nsString = textStorage.string as NSString
      let lineRanges = affectedLineRanges(in: nsString, editContext: pendingEditContext)
      guard !lineRanges.isEmpty else { return }

      var updatedSelection = textView.selectedRange()

      for lineRange in lineRanges.sorted(by: { $0.location > $1.location }) {
        let lineText = nsString.substring(with: lineRange)
        guard let prefixMetrics = rawAutoformatPrefixMetrics(for: lineText) else { continue }

        let previousLineRange = lineRange
        let didFormat =
          MarkdownStyler.formatCurrentLine(
            in: textStorage,
            lineRange: lineRange,
            appearance: parent.appearanceSettings
          ) != nil

        guard didFormat else { continue }

        let updatedString = textStorage.string as NSString
        let updatedLineRange = trimmedLineRange(
          in: updatedString,
          containing: min(previousLineRange.location, max(updatedString.length - 1, 0))
        )

        updatedSelection = adjustedSelection(
          updatedSelection,
          previousLineRange: previousLineRange,
          updatedLineRange: updatedLineRange,
          prefixMetrics: prefixMetrics
        )
      }

      // Post-apply section colors to any lines that were just formatted.
      if let scealTV = textView as? ScealTextView {
        applySectionColorsToEditedLines(
          lineRanges, in: textStorage, scealTextView: scealTV)
      }

      textView.setSelectedRange(
        clampedRange(updatedSelection, maxLength: textStorage.string.utf16.count)
      )
      if let scealTextView = textView as? ScealTextView {
        _ = scealTextView.normalizeSelectionIfNeeded()
      }
      syncTypingAttributesToInsertionPoint(in: textView, textStorage: textStorage)
    }

    // Applies section-level colors to recently formatted lines so that live
    // edits inside a colored section pick up the section defaults immediately.
    private func applySectionColorsToEditedLines(
      _ lineRanges: [NSRange],
      in textStorage: NSTextStorage,
      scealTextView: ScealTextView
    ) {
      for lineRange in lineRanges {
        guard lineRange.location < textStorage.length else { continue }
        guard let sectionInfo = scealTextView.sectionColors(at: lineRange.location) else {
          continue
        }
        let nsString = textStorage.string as NSString
        let currentLineRange = nsString.lineRange(
          for: NSRange(location: lineRange.location, length: 0))
        var trimmed = currentLineRange
        if trimmed.length > 0,
          nsString.character(at: trimmed.location + trimmed.length - 1) == 0x0A
        {
          trimmed.length -= 1
        }
        guard trimmed.length > 0 else { continue }

        let attrs = textStorage.attributes(at: trimmed.location, effectiveRange: nil)

        // Heading without explicit hcolor → apply section heading color
        if attrs[.markdownHeadingLevel] != nil,
          attrs[.markdownHeadingColor] == nil,
          let colorName = sectionInfo.headingColorName,
          let color = MarkdownStyler.headingColor(named: colorName)
        {
          textStorage.addAttribute(.foregroundColor, value: color, range: trimmed)
          continue
        }

        // Bullet/checkbox with useSectionColor → apply section bullet color
        guard sectionInfo.useSectionColor,
          let rawType = attrs[.markdownListType] as? String,
          let listType = MarkdownListType(rawValue: rawType)
        else { continue }

        let color: NSColor? = {
          if let n = sectionInfo.bulletColorName { return MarkdownStyler.headingColor(named: n) }
          if let n = sectionInfo.headingColorName { return MarkdownStyler.headingColor(named: n) }
          return nil
        }()
        guard let bulletColor = color else { continue }

        switch listType {
        case .bullet:
          textStorage.addAttributes(
            [
              .foregroundColor: bulletColor,
              .font: NSFont.systemFont(
                ofSize: scealTextView.appearanceSettings.bulletSize, weight: .bold),
            ], range: NSRange(location: trimmed.location, length: 1))
        case .checkboxChecked, .checkboxUnchecked:
          let checked = listType == .checkboxChecked
          let newAttachment = NSAttributedString(
            attachment: MarkdownStyler.checkboxAttachment(checked: checked, color: bulletColor))
          textStorage.replaceCharacters(
            in: NSRange(location: trimmed.location, length: 1), with: newAttachment)
        case .numbered:
          break
        }
      }
    }

    // Computes the line ranges affected by a pending edit.
    private func affectedLineRanges(in nsString: NSString, editContext: PendingEditContext)
      -> [NSRange]
    {
      guard nsString.length > 0 else { return [] }

      let startLocation = min(editContext.range.location, max(nsString.length - 1, 0))
      let replacementLength = editContext.replacementString?.utf16.count ?? 0
      let endSeed = max(editContext.range.location + replacementLength - 1, startLocation)
      let endLocation = min(endSeed, max(nsString.length - 1, 0))

      var lineRanges: [NSRange] = []
      var currentRange = nsString.lineRange(for: NSRange(location: startLocation, length: 0))
      let finalRange = nsString.lineRange(for: NSRange(location: endLocation, length: 0))

      while true {
        lineRanges.append(trimmedLineRange(from: currentRange, in: nsString))
        if currentRange.location >= finalRange.location { break }
        let nextLocation = min(NSMaxRange(currentRange), max(nsString.length - 1, 0))
        currentRange = nsString.lineRange(for: NSRange(location: nextLocation, length: 0))
      }

      return lineRanges
    }

    // Returns the trimmed line range containing the given location.
    private func trimmedLineRange(in nsString: NSString, containing location: Int) -> NSRange {
      let safeLocation = min(location, max(nsString.length - 1, 0))
      return trimmedLineRange(
        from: nsString.lineRange(for: NSRange(location: safeLocation, length: 0)),
        in: nsString
      )
    }

    // Strips the trailing newline from a line range.
    private func trimmedLineRange(from lineRange: NSRange, in nsString: NSString) -> NSRange {
      var trimmedRange = lineRange
      if trimmedRange.length > 0,
        nsString.character(at: trimmedRange.location + trimmedRange.length - 1) == 0x0A
      {
        trimmedRange.length -= 1
      }
      return trimmedRange
    }

    // Detects raw markdown list prefixes and their display-width equivalents.
    private func rawAutoformatPrefixMetrics(for lineText: String)
      -> (rawPrefixLength: Int, displayPrefixLength: Int)?
    {
      if lineText.hasPrefix("- [ ] ") || lineText.hasPrefix("- [x] ")
        || lineText.hasPrefix("- [X] ")
      {
        return (6, 2)
      }

      if let prefixRange = lineText.range(of: #"^(?:-|•)\s+"#, options: .regularExpression) {
        let rawPrefixLength = lineText.distance(
          from: prefixRange.lowerBound, to: prefixRange.upperBound)
        return (rawPrefixLength, 2)
      }

      if let prefixRange = lineText.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
        let prefixLength = lineText.distance(
          from: prefixRange.lowerBound, to: prefixRange.upperBound)
        return (prefixLength, prefixLength)
      }

      return nil
    }

    // Remaps the selection after autoformat changes the line length.
    private func adjustedSelection(
      _ selection: NSRange,
      previousLineRange: NSRange,
      updatedLineRange: NSRange,
      prefixMetrics: (rawPrefixLength: Int, displayPrefixLength: Int)
    ) -> NSRange {
      var adjustedSelection = selection
      let delta = updatedLineRange.length - previousLineRange.length

      if adjustedSelection.location > NSMaxRange(previousLineRange) {
        adjustedSelection.location += delta
        return adjustedSelection
      }

      guard adjustedSelection.location >= previousLineRange.location else {
        return adjustedSelection
      }

      let offsetInLine = adjustedSelection.location - previousLineRange.location
      let adjustedOffset: Int
      if offsetInLine <= prefixMetrics.rawPrefixLength {
        adjustedOffset = min(prefixMetrics.displayPrefixLength, updatedLineRange.length)
      } else {
        adjustedOffset = min(
          prefixMetrics.displayPrefixLength + (offsetInLine - prefixMetrics.rawPrefixLength),
          updatedLineRange.length
        )
      }

      adjustedSelection.location = updatedLineRange.location + adjustedOffset
      return adjustedSelection
    }

    // Constrains a range to valid bounds within text storage.
    private func clampedRange(_ range: NSRange, maxLength: Int) -> NSRange {
      let safeLocation = min(range.location, maxLength)
      let safeLength = min(range.length, max(maxLength - safeLocation, 0))
      return NSRange(location: safeLocation, length: safeLength)
    }

    // Ensures typing attributes match the character context at the cursor.
    private func syncTypingAttributesToInsertionPoint(
      in textView: NSTextView,
      textStorage: NSTextStorage
    ) {
      guard textStorage.length > 0 else {
        textView.typingAttributes = MarkdownStyler.baseTypingAttributes(
          for: parent.appearanceSettings)
        return
      }

      if let scealTextView = textView as? ScealTextView,
        let sourceLocation = scealTextView.typingAttributeSourceLocation(
          forInsertionLocation: textView.selectedRange().location)
      {
        textView.typingAttributes = textStorage.attributes(
          at: sourceLocation,
          effectiveRange: nil
        )
        return
      }

      textView.typingAttributes = MarkdownStyler.baseTypingAttributes(
        for: parent.appearanceSettings)
    }
  }
}
