//
//  MarkdownTextView.swift
//
//

import AppKit
import SwiftUI

struct MarkdownTextView: NSViewRepresentable {
  let noteID: DayNote.ID
  @Binding var text: String
  let appearanceSettings: NoteAppearanceSettings

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

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
    // Extra bottom space so the cursor area never gets stuck at the viewport edge.
    scrollView.automaticallyAdjustsContentInsets = false
    scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 300, right: 0)

    // Load initial content
    let displayString = MarkdownStyler.formatForDisplay(text, appearance: appearanceSettings)
    textView.textStorage?.setAttributedString(displayString)
    textView.refreshSectionLayout()
    context.coordinator.lastPushedMarkdown = text
    context.coordinator.lastAppliedAppearance = appearanceSettings
    context.coordinator.lastDividerCount = textView.sectionDividerCount
    context.coordinator.lastNoteID = noteID

    // Ensure text view fills at least the scroll view height
    textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)

    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    guard !context.coordinator.isUpdating else { return }
    guard let textView = scrollView.documentView as? NSTextView else { return }
    context.coordinator.parent = self
    context.coordinator.toolbar.appearanceSettings = appearanceSettings

    // Keep text view filling the scroll view height
    let minH = scrollView.contentSize.height
    if textView.minSize.height != minH {
      textView.minSize = NSSize(width: 0, height: minH)
    }

    let noteChanged = noteID != context.coordinator.lastNoteID
    let textChanged = text != context.coordinator.lastPushedMarkdown
    let appearanceChanged = appearanceSettings != context.coordinator.lastAppliedAppearance
    guard noteChanged || textChanged || appearanceChanged else { return }

    context.coordinator.isUpdating = true
    let selectedRange = noteChanged
      ? NSRange(location: 0, length: 0)
      : clampedRange(textView.selectedRange(), maxLength: text.utf16.count)
    let visibleOrigin = scrollView.contentView.bounds.origin
    if let scealTextView = textView as? ScealTextView {
      scealTextView.appearanceSettings = appearanceSettings
    }
    textView.font = appearanceSettings.bodyFont
    textView.typingAttributes = MarkdownStyler.baseTypingAttributes(for: appearanceSettings)
    let displayString = MarkdownStyler.formatForDisplay(text, appearance: appearanceSettings)
    textView.textStorage?.setAttributedString(displayString)
    context.coordinator.lastPushedMarkdown = text
    context.coordinator.lastAppliedAppearance = appearanceSettings
    context.coordinator.lastNoteID = noteID
    textView.setSelectedRange(clampedRange(selectedRange, maxLength: textView.string.utf16.count))
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
    }
    scrollView.reflectScrolledClipView(scrollView.contentView)
    context.coordinator.isUpdating = false
  }

  private func clampedRange(_ range: NSRange, maxLength: Int) -> NSRange {
    let safeLocation = min(range.location, maxLength)
    let safeLength = min(range.length, max(maxLength - safeLocation, 0))
    return NSRange(location: safeLocation, length: safeLength)
  }

  // MARK: - Coordinator

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
        let selectionRect =
          textView.layoutManager?.boundingRect(
            forGlyphRange: glyphRange, in: textView.textContainer!) ?? .zero
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
          let replacementRange = fullLineRange.length > lineRange.length ? fullLineRange : lineRange
          let dividerLine = NSMutableAttributedString(
            attributedString: MarkdownStyler.sectionDividerDisplayString())
          dividerLine.append(NSAttributedString(string: "\n"))

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
          for: NSRange(location: min(lineRange.location, max(formattedNS.length - 1, 0)), length: 0))
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
              appearance: parent.appearanceSettings
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

    private func removeListMarker(in textStorage: NSTextStorage, lineRange: NSRange) {
      textStorage.replaceCharacters(in: lineRange, with: "")
    }

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

    private func continuationAttributedMarker(
      for listType: MarkdownListType, marker: String, appearance: NoteAppearanceSettings
    ) -> NSAttributedString {
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
            .paragraphStyle: MarkdownStyler.listParagraphStyle(for: appearance),
          ], range: fullRange)
        return result

      default:
        let result = NSMutableAttributedString(
          string: marker,
          attributes: [
            .font: appearance.bodyFont,
            .foregroundColor: NSColor.labelColor,
            .markdownListType: listType.rawValue,
            .paragraphStyle: MarkdownStyler.listParagraphStyle(for: appearance),
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

    // MARK: - Slash Command Popup

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

    private func dismissSlashPopup() {
      slashPopup.hide()
      slashTriggerLocation = nil
    }

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

    private func replaceCurrentLine(
      in textStorage: NSTextStorage,
      lineRange: NSRange,
      with attributedString: NSAttributedString
    ) {
      textStorage.replaceCharacters(in: lineRange, with: attributedString)
    }

    private func headingTypingAttributes(level: Int) -> [NSAttributedString.Key: Any] {
      [
        .font: parent.appearanceSettings.boldBodyFont(ofSize: headingFontSize(for: level)),
        .foregroundColor: NSColor.labelColor,
        .paragraphStyle: MarkdownStyler.bodyParagraphStyle(for: parent.appearanceSettings),
        .markdownHeadingLevel: level,
      ]
    }

    private func codeBlockTypingAttributes() -> [NSAttributedString.Key: Any] {
      [
        .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
        .backgroundColor: NSColor.quaternaryLabelColor,
        .foregroundColor: NSColor.labelColor,
        .markdownCodeBlock: true,
      ]
    }

    private func headingFontSize(for level: Int) -> CGFloat {
      switch level {
      case 1:
        return 22
      case 2:
        return 19
      default:
        return 17
      }
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

      textView.setSelectedRange(
        clampedRange(updatedSelection, maxLength: textStorage.string.utf16.count)
      )
      if let scealTextView = textView as? ScealTextView {
        _ = scealTextView.normalizeSelectionIfNeeded()
      }
      syncTypingAttributesToInsertionPoint(in: textView, textStorage: textStorage)
    }

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

    private func trimmedLineRange(in nsString: NSString, containing location: Int) -> NSRange {
      let safeLocation = min(location, max(nsString.length - 1, 0))
      return trimmedLineRange(
        from: nsString.lineRange(for: NSRange(location: safeLocation, length: 0)),
        in: nsString
      )
    }

    private func trimmedLineRange(from lineRange: NSRange, in nsString: NSString) -> NSRange {
      var trimmedRange = lineRange
      if trimmedRange.length > 0,
        nsString.character(at: trimmedRange.location + trimmedRange.length - 1) == 0x0A
      {
        trimmedRange.length -= 1
      }
      return trimmedRange
    }

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

    private func clampedRange(_ range: NSRange, maxLength: Int) -> NSRange {
      let safeLocation = min(range.location, maxLength)
      let safeLength = min(range.length, max(maxLength - safeLocation, 0))
      return NSRange(location: safeLocation, length: safeLength)
    }

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

// MARK: - Custom NSTextView subclass

private enum DividerResolutionPreference {
  case previous
  case next
  case nearest
}

private class ScealTextView: NSTextView {

  var appearanceSettings = NoteAppearanceSettings.default
  private let cardColor = NSColor.labelColor.withAlphaComponent(0.04)
  private let cardRadius: CGFloat = 24
  private let cardHInset: CGFloat = 0
  private let cardVPad: CGFloat = 10

  var sectionDividerCount: Int {
    guard let textStorage else { return 0 }

    var dividerCount = 0
    textStorage.enumerateAttribute(
      .markdownSectionDivider,
      in: NSRange(location: 0, length: textStorage.length),
      options: []
    ) { value, _, _ in
      if value as? Bool == true {
        dividerCount += 1
      }
    }
    return dividerCount
  }

  func refreshSectionLayout() {
    let fullRange = NSRange(location: 0, length: textStorage?.length ?? 0)
    if fullRange.length > 0 {
      layoutManager?.ensureLayout(forCharacterRange: fullRange)
    }
    setNeedsDisplay(bounds)
    enclosingScrollView?.contentView.needsDisplay = true
  }

  @discardableResult
  func normalizeSelectionIfNeeded(prefer preference: DividerResolutionPreference = .nearest) -> Bool
  {
    let currentSelection = selectedRange()
    guard currentSelection.length == 0 else { return false }

    let resolvedLocation = resolvedInsertionLocation(
      for: currentSelection.location,
      prefer: preference
    )
    guard resolvedLocation != currentSelection.location else { return false }

    super.setSelectedRange(NSRange(location: resolvedLocation, length: 0))
    return true
  }

  func typingAttributeSourceLocation(forInsertionLocation location: Int) -> Int? {
    guard let textStorage, textStorage.length > 0 else { return nil }

    let clampedLocation = min(max(location, 0), textStorage.length)

    if clampedLocation > 0 {
      let backwardRange = stride(
        from: min(clampedLocation - 1, textStorage.length - 1),
        through: 0,
        by: -1
      )
      for candidate in backwardRange where canUseTypingAttributes(at: candidate) {
        return candidate
      }
    }

    guard clampedLocation < textStorage.length else { return nil }
    for candidate in clampedLocation..<textStorage.length
    where canUseTypingAttributes(at: candidate) {
      return candidate
    }

    return nil
  }

  // MARK: - Section Card Backgrounds

  override func drawBackground(in rect: NSRect) {
    // Don't call super — we draw all backgrounds ourselves so there's
    // no default background bleeding through between cards.

    guard let textStorage = textStorage, let layoutManager = layoutManager,
      let textContainer = textContainer, textStorage.length > 0
    else {
      // Empty: draw one full-height card
      drawSingleCard(in: rect)
      return
    }

    // Find section divider positions
    let fullRange = NSRange(location: 0, length: textStorage.length)
    var dividerLineRanges: [NSRange] = []

    textStorage.enumerateAttribute(.markdownSectionDivider, in: fullRange, options: []) {
      value, range, _ in
      if value as? Bool == true {
        let nsString = textStorage.string as NSString
        dividerLineRanges.append(nsString.lineRange(for: range))
      }
    }

    // Find horizontal rule positions (visible lines, not card-splitting)
    var hrLineRanges: [NSRange] = []
    textStorage.enumerateAttribute(.markdownHorizontalRule, in: fullRange, options: []) {
      value, range, _ in
      if value as? Bool == true {
        let nsString = textStorage.string as NSString
        hrLineRanges.append(nsString.lineRange(for: range))
      }
    }

    // No section dividers → one card covering everything
    if dividerLineRanges.isEmpty {
      drawSingleCard(in: rect)
      drawHorizontalRules(hrLineRanges, in: rect)
      return
    }

    // Build section content ranges (between dividers)
    var sections: [NSRange] = []
    var currentStart = 0

    for divRange in dividerLineRanges {
      if divRange.location > currentStart {
        sections.append(NSRange(location: currentStart, length: divRange.location - currentStart))
      }
      currentStart = NSMaxRange(divRange)
    }
    if currentStart < textStorage.length {
      sections.append(NSRange(location: currentStart, length: textStorage.length - currentStart))
    }

    // Calculate divider midpoints — these define where one card ends and the next begins
    var dividerMidYs: [CGFloat] = []
    for divRange in dividerLineRanges {
      let divGlyphs = layoutManager.glyphRange(
        forCharacterRange: divRange, actualCharacterRange: nil)
      let divRect = layoutManager.boundingRect(forGlyphRange: divGlyphs, in: textContainer)
      let midY = divRect.midY + textContainerOrigin.y
      dividerMidYs.append(midY)
    }

    let viewBottom = max(bounds.height, enclosingScrollView?.contentSize.height ?? bounds.height)

    // Draw a card for each section, bounded by divider midpoints
    for (index, sectionRange) in sections.enumerated() {
      let glyphRange = layoutManager.glyphRange(
        forCharacterRange: sectionRange, actualCharacterRange: nil)
      let isLastSection = (index == sections.count - 1)
      // Always draw the last section so the card gap appears immediately after a divider
      guard glyphRange.length > 0 || isLastSection else { continue }

      // Card top: y=0 for first section, divider midpoint for others
      let cardTop: CGFloat
      if index == 0 {
        cardTop = 0
      } else {
        let divIndex = min(index - 1, dividerMidYs.count - 1)
        cardTop = dividerMidYs[divIndex] + 6  // 6pt gap below midpoint
      }

      // Card bottom: divider midpoint for intermediate sections, view bottom for last
      let cardBottom: CGFloat
      if index == sections.count - 1 {
        cardBottom = viewBottom
      } else {
        let divIndex = min(index, dividerMidYs.count - 1)
        cardBottom = dividerMidYs[divIndex] - 6  // 6pt gap above midpoint
      }

      let cardRect = NSRect(
        x: cardHInset,
        y: cardTop,
        width: bounds.width - (cardHInset * 2),
        height: max(cardBottom - cardTop, 0)
      )

      guard cardRect.height > 0, cardRect.intersects(rect) else { continue }

      let path = NSBezierPath(roundedRect: cardRect, xRadius: cardRadius, yRadius: cardRadius)
      cardColor.setFill()
      path.fill()
    }

    drawHorizontalRules(hrLineRanges, in: rect)
  }

  private func drawSingleCard(in rect: NSRect) {
    let fullHeight = max(bounds.height, enclosingScrollView?.contentSize.height ?? bounds.height)
    let cardRect = NSRect(
      x: cardHInset, y: 0, width: bounds.width - cardHInset * 2, height: fullHeight)
    guard cardRect.intersects(rect) else { return }
    let path = NSBezierPath(roundedRect: cardRect, xRadius: cardRadius, yRadius: cardRadius)
    cardColor.setFill()
    path.fill()
  }

  // Draws a thin visible line for each standard markdown horizontal rule (`---`).
  private func drawHorizontalRules(_ ranges: [NSRange], in rect: NSRect) {
    guard let layoutManager = layoutManager, let textContainer = textContainer,
      !ranges.isEmpty
    else { return }

    let lineInset: CGFloat = 24
    NSColor.separatorColor.setFill()

    for range in ranges {
      let glyphRange = layoutManager.glyphRange(
        forCharacterRange: range, actualCharacterRange: nil)
      let lineRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
      let midY = lineRect.midY + textContainerOrigin.y

      let hrRect = NSRect(
        x: lineInset,
        y: midY,
        width: bounds.width - (lineInset * 2),
        height: 1
      )

      guard hrRect.intersects(rect) else { continue }
      hrRect.fill()
    }
  }

  // MARK: - Paste

  override func moveUp(_ sender: Any?) {
    super.moveUp(sender)
    skipSectionDividers(direction: .previous, sender: sender)
  }

  override func moveDown(_ sender: Any?) {
    super.moveDown(sender)
    skipSectionDividers(direction: .next, sender: sender)
  }

  override func insertText(_ insertString: Any, replacementRange: NSRange) {
    let targetRange = sanitizedReplacementRange(replacementRange)
    super.insertText(insertString, replacementRange: targetRange)
  }

  override func paste(_ sender: Any?) {
    guard let plainText = NSPasteboard.general.string(forType: .string) else { return }
    insertText(plainText, replacementRange: selectedRange())
  }

  // MARK: - Checkbox Click

  override func mouseDown(with event: NSEvent) {
    guard let textStorage = textStorage, let layoutManager = layoutManager,
      let textContainer = textContainer
    else {
      super.mouseDown(with: event)
      return
    }

    let point = convert(event.locationInWindow, from: nil)
    let textPoint = NSPoint(
      x: point.x - textContainerInset.width,
      y: point.y - textContainerInset.height)
    let charIndex = layoutManager.characterIndex(
      for: textPoint, in: textContainer,
      fractionOfDistanceBetweenInsertionPoints: nil)

    if let dividerSelectionLocation = dividerSelectionLocation(
      for: charIndex,
      at: textPoint,
      layoutManager: layoutManager,
      textContainer: textContainer
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

    toggleCheckbox(at: charIndex)
  }

  private func toggleCheckbox(at charIndex: Int) {
    guard let textStorage = textStorage else { return }
    let nsString = textStorage.string as NSString
    let lineRange = nsString.lineRange(for: NSRange(location: charIndex, length: 0))
    var textRange = lineRange
    if textRange.length > 0
      && nsString.character(at: textRange.location + textRange.length - 1) == 0x0A
    {
      textRange.length -= 1
    }

    let currentTypeRaw =
      textStorage.attribute(.markdownListType, at: charIndex, effectiveRange: nil) as? String
    let isChecked = currentTypeRaw == MarkdownListType.checkboxChecked.rawValue

    _ = performEditorEdit(
      affectedRange: textRange,
      actionName: isChecked ? "Uncheck Item" : "Check Item"
    ) { textStorage in
      let newAttachment = MarkdownStyler.checkboxAttachment(
        checked: !isChecked,
        appearance: appearanceSettings
      )
      let attachmentStr = NSAttributedString(attachment: newAttachment)
      textStorage.replaceCharacters(
        in: NSRange(location: charIndex, length: 1),
        with: attachmentStr
      )

      let updatedNSString = textStorage.string as NSString
      let updatedLineRange = updatedNSString.lineRange(
        for: NSRange(location: charIndex, length: 0))
      var updatedTextRange = updatedLineRange
      if updatedTextRange.length > 0
        && updatedNSString.character(
          at: updatedTextRange.location + updatedTextRange.length - 1) == 0x0A
      {
        updatedTextRange.length -= 1
      }

      let newType: MarkdownListType = isChecked ? .checkboxUnchecked : .checkboxChecked
      textStorage.addAttribute(
        .markdownListType,
        value: newType.rawValue,
        range: updatedTextRange
      )
      textStorage.addAttribute(
        .paragraphStyle,
        value: MarkdownStyler.listParagraphStyle(for: appearanceSettings),
        range: updatedTextRange
      )

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
  }

  private func skipSectionDividers(direction: DividerResolutionPreference, sender: Any?) {
    guard selectedRange().length == 0 else { return }

    var previousLocation = selectedRange().location
    var safetyCounter = 0

    while sectionDividerLineRange(containingInsertionLocation: selectedRange().location) != nil,
      safetyCounter < 8
    {
      if direction == .previous {
        super.moveUp(sender)
      } else {
        super.moveDown(sender)
      }

      let currentLocation = selectedRange().location
      if currentLocation == previousLocation { break }
      previousLocation = currentLocation
      safetyCounter += 1
    }

    _ = normalizeSelectionIfNeeded(prefer: direction)
  }

  private func sanitizedReplacementRange(_ replacementRange: NSRange) -> NSRange {
    let baseRange = replacementRange.location == NSNotFound ? selectedRange() : replacementRange
    guard baseRange.length == 0 else { return baseRange }

    let resolvedLocation = resolvedInsertionLocation(for: baseRange.location, prefer: .nearest)
    if resolvedLocation != baseRange.location {
      super.setSelectedRange(NSRange(location: resolvedLocation, length: 0))
    }
    return NSRange(location: resolvedLocation, length: 0)
  }

  private func dividerSelectionLocation(
    for charIndex: Int,
    at textPoint: NSPoint,
    layoutManager: NSLayoutManager,
    textContainer: NSTextContainer
  ) -> Int? {
    guard let textStorage, textStorage.length > 0 else { return nil }

    let clampedIndex = min(max(charIndex, 0), textStorage.length - 1)
    let candidateIndexes = [clampedIndex, max(clampedIndex - 1, 0)]

    for candidateIndex in candidateIndexes {
      let lineRange = (string as NSString).lineRange(
        for: NSRange(location: candidateIndex, length: 0))
      guard lineHasSectionDivider(lineRange) else { continue }

      let glyphRange = layoutManager.glyphRange(
        forCharacterRange: lineRange,
        actualCharacterRange: nil
      )
      let dividerRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
      guard dividerRect.insetBy(dx: -textContainerInset.width, dy: -6).contains(textPoint) else {
        continue
      }

      let upperHalf = isFlipped ? textPoint.y < dividerRect.midY : textPoint.y > dividerRect.midY
      let preference: DividerResolutionPreference = upperHalf ? .previous : .next
      return resolvedInsertionLocation(for: candidateIndex, prefer: preference)
    }

    return nil
  }

  private func resolvedInsertionLocation(
    for proposedLocation: Int,
    prefer preference: DividerResolutionPreference
  ) -> Int {
    guard
      let dividerLineRange = sectionDividerLineRange(containingInsertionLocation: proposedLocation)
    else {
      return min(max(proposedLocation, 0), textStorage?.length ?? 0)
    }

    let previousLocation = previousEditableInsertionLocation(before: dividerLineRange)
    let nextLocation = nextEditableInsertionLocation(after: dividerLineRange)

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

  private func previousEditableInsertionLocation(before dividerLineRange: NSRange) -> Int? {
    guard dividerLineRange.location > 0 else { return nil }

    let nsString = string as NSString
    var searchLocation = dividerLineRange.location - 1

    while searchLocation >= 0 {
      let lineRange = nsString.lineRange(for: NSRange(location: searchLocation, length: 0))
      if lineHasSectionDivider(lineRange) {
        guard lineRange.location > 0 else { return nil }
        searchLocation = lineRange.location - 1
        continue
      }

      return NSMaxRange(trimmedLineRange(from: lineRange, in: nsString))
    }

    return nil
  }

  private func nextEditableInsertionLocation(after dividerLineRange: NSRange) -> Int? {
    let nsString = string as NSString
    var searchLocation = NSMaxRange(dividerLineRange)

    while searchLocation < nsString.length {
      let lineRange = nsString.lineRange(for: NSRange(location: searchLocation, length: 0))
      if !lineHasSectionDivider(lineRange) {
        return lineRange.location
      }
      searchLocation = NSMaxRange(lineRange)
    }

    return nsString.length
  }

  private func sectionDividerLineRange(containingInsertionLocation location: Int) -> NSRange? {
    guard let textStorage, textStorage.length > 0 else { return nil }

    let nsString = string as NSString
    let clampedLocation = min(max(location, 0), textStorage.length)
    // Allow the caret to sit after a divider's trailing newline when the divider is the last line.
    if clampedLocation == textStorage.length { return nil }
    let lineRange = nsString.lineRange(for: NSRange(location: clampedLocation, length: 0))
    return lineHasSectionDivider(lineRange) ? lineRange : nil
  }

  private func lineHasSectionDivider(_ lineRange: NSRange) -> Bool {
    lineHasAttribute(.markdownSectionDivider, in: lineRange)
  }

  private func canUseTypingAttributes(at location: Int) -> Bool {
    guard let textStorage, location >= 0, location < textStorage.length else { return false }

    let attributes = textStorage.attributes(at: location, effectiveRange: nil)
    return attributes[.markdownSectionDivider] as? Bool != true
      && attributes[.markdownHorizontalRule] as? Bool != true
  }

  private func lineHasAttribute(_ key: NSAttributedString.Key, in lineRange: NSRange) -> Bool {
    guard let textStorage else { return false }

    let trimmedRange = trimmedLineRange(from: lineRange, in: string as NSString)
    guard trimmedRange.length > 0, trimmedRange.location < textStorage.length else { return false }

    return textStorage.attribute(key, at: trimmedRange.location, effectiveRange: nil) as? Bool
      == true
  }

  private func trimmedLineRange(from lineRange: NSRange, in nsString: NSString) -> NSRange {
    var trimmedRange = lineRange
    if trimmedRange.length > 0,
      nsString.character(at: trimmedRange.location + trimmedRange.length - 1) == 0x0A
    {
      trimmedRange.length -= 1
    }
    return trimmedRange
  }
}
