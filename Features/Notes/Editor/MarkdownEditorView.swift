//
//  MarkdownEditorView.swift
//

// TextKit 2-backed NSViewRepresentable editor with coordinator-driven markdown behavior.

import AppKit
import SwiftUI

struct MarkdownEditorView: NSViewRepresentable {
  static let minimumBottomOverscroll: CGFloat = 300
  static let preferredBottomOverscrollViewportRatio: CGFloat = 0.75

  // Keeps enough trailing scroll room to lift the last lines into a comfortable reading zone.
  static func bottomOverscrollHeight(for viewportHeight: CGFloat) -> CGFloat {
    max(minimumBottomOverscroll, viewportHeight * preferredBottomOverscrollViewportRatio)
  }

  // Computes the editor document height needed to preserve scroll-past-end for any note length.
  static func targetEditorHeight(documentHeight: CGFloat, viewportHeight: CGFloat) -> CGFloat {
    let overscrollHeight = bottomOverscrollHeight(for: viewportHeight)
    return ceil(max(viewportHeight + overscrollHeight, documentHeight + overscrollHeight))
  }

  let noteID: DayNote.ID
  @Binding var text: String
  let appearanceSettings: NoteAppearanceSettings
  var continuousSpellCheckingEnabled: Bool = true
  var searchText: String = ""

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  func makeNSView(context: Context) -> NSScrollView {
    let textView = MarkdownEditorTextView(usingTextLayoutManager: true)
    configure(textView, coordinator: context.coordinator)

    let scrollView = EditorScrollView()
    scrollView.documentView = textView
    scrollView.hasVerticalScroller = appearanceSettings.showEditorScrollbar
    scrollView.hasHorizontalScroller = false
    scrollView.drawsBackground = false
    scrollView.automaticallyAdjustsContentInsets = false
    scrollView.autohidesScrollers = true
    scrollView.contentInsets = .init()
    scrollView.onViewportHeightChange = { [weak textView, weak scrollView] viewportHeight in
      guard let textView, let scrollView else { return }
      Self.applyBottomOverscroll(to: textView, in: scrollView, viewportHeight: viewportHeight)
    }

    applyDisplayString(
      MarkdownEditorFormatter.formatForDisplay(text, appearance: appearanceSettings),
      to: textView
    )
    Self.applyContinuousSpellChecking(
      to: textView,
      enabled: continuousSpellCheckingEnabled,
      refresh: continuousSpellCheckingEnabled
    )
    context.coordinator.syncTypingAttributesToCurrentSelection(in: textView)
    context.coordinator.lastPushedMarkdown = text
    context.coordinator.lastAppliedAppearance = appearanceSettings
    context.coordinator.lastContinuousSpellCheckingEnabled = continuousSpellCheckingEnabled
    context.coordinator.lastNoteID = noteID
    context.coordinator.lastSearchText = searchText
    context.coordinator.lastDividerCount = (textView as MarkdownEditorTextView).sectionDividerCount
    context.coordinator.toolbar.appearanceSettings = appearanceSettings

    Self.applySearchHighlights(
      to: textView, query: searchText.trimmingCharacters(in: .whitespacesAndNewlines),
      accentColor: appearanceSettings.accentColor)
    Self.applyBottomOverscroll(to: textView, in: scrollView)

    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    guard !context.coordinator.isUpdating else { return }
    guard let textView = scrollView.documentView as? NSTextView else { return }

    // Flush any pending debounced markdown push before switching notes so the
    // old note's final content is committed while the parent binding is still correct.
    if noteID != context.coordinator.lastNoteID,
      let textStorage = textView.textStorage
    {
      context.coordinator.flushPendingMarkdownPushIfNeeded(from: textStorage)
    }

    context.coordinator.parent = self
    configure(textView, coordinator: context.coordinator)
    context.coordinator.toolbar.appearanceSettings = appearanceSettings
    scrollView.hasVerticalScroller = appearanceSettings.showEditorScrollbar
    if let editorScrollView = scrollView as? EditorScrollView {
      editorScrollView.onViewportHeightChange = { [weak textView, weak scrollView] viewportHeight in
        guard let textView, let scrollView else { return }
        Self.applyBottomOverscroll(to: textView, in: scrollView, viewportHeight: viewportHeight)
      }
    }
    Self.applyBottomOverscroll(to: textView, in: scrollView)

    let noteChanged = noteID != context.coordinator.lastNoteID
    let textChanged = text != context.coordinator.lastPushedMarkdown
    let appearanceChanged = appearanceSettings != context.coordinator.lastAppliedAppearance
    let spellCheckingChanged =
      continuousSpellCheckingEnabled != context.coordinator.lastContinuousSpellCheckingEnabled
    let searchChanged = searchText != context.coordinator.lastSearchText
    let contentChanged = noteChanged || textChanged || appearanceChanged
    guard contentChanged || searchChanged || spellCheckingChanged else { return }

    if contentChanged {
      context.coordinator.isUpdating = true
      let visibleOrigin = scrollView.contentView.bounds.origin
      let wasFirstResponder = textView.window?.firstResponder === textView

      let displayString = MarkdownEditorFormatter.formatForDisplay(
        text, appearance: appearanceSettings)
      let selectedRange =
        noteChanged
        ? NSRange(location: 0, length: 0)
        : clampedRange(textView.selectedRange(), maxLength: text.utf16.count)
      applyDisplayString(displayString, to: textView)
      context.coordinator.lastPushedMarkdown = text
      context.coordinator.lastAppliedAppearance = appearanceSettings
      context.coordinator.lastNoteID = noteID
      if let interactiveTV = textView as? MarkdownEditorTextView {
        context.coordinator.lastDividerCount = interactiveTV.sectionDividerCount
      }
      textView.setSelectedRange(
        clampedRange(selectedRange, maxLength: textView.string.utf16.count)
      )
      context.coordinator.syncTypingAttributesToCurrentSelection(in: textView)

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

    Self.applyContinuousSpellChecking(
      to: textView,
      enabled: continuousSpellCheckingEnabled,
      refresh: contentChanged || spellCheckingChanged
    )
    context.coordinator.lastContinuousSpellCheckingEnabled = continuousSpellCheckingEnabled

    context.coordinator.lastSearchText = searchText
    Self.applySearchHighlights(
      to: textView, query: searchText.trimmingCharacters(in: .whitespacesAndNewlines),
      accentColor: appearanceSettings.accentColor)
  }

  private func configure(_ textView: NSTextView, coordinator: Coordinator) {
    Self.configureTextView(
      textView,
      appearanceSettings: appearanceSettings,
      continuousSpellCheckingEnabled: continuousSpellCheckingEnabled,
      delegate: coordinator
    )
  }

  static func configureTextView(
    _ textView: NSTextView,
    appearanceSettings: NoteAppearanceSettings,
    continuousSpellCheckingEnabled: Bool,
    delegate: NSTextViewDelegate?
  ) {
    if let interactiveTextView = textView as? MarkdownEditorTextView {
      interactiveTextView.appearanceSettings = appearanceSettings
    }
    textView.isRichText = true
    textView.isEditable = true
    textView.isSelectable = true
    textView.drawsBackground = false
    textView.allowsUndo = true
    textView.isContinuousSpellCheckingEnabled = continuousSpellCheckingEnabled
    textView.isGrammarCheckingEnabled = false
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isAutomaticTextReplacementEnabled = false
    textView.isAutomaticSpellingCorrectionEnabled = false
    textView.baseWritingDirection = .leftToRight
    textView.selectedTextAttributes = [
      .backgroundColor: NSColor.selectedTextBackgroundColor.withAlphaComponent(0.28)
    ]
    textView.textContainerInset = NSSize(width: 22, height: 22)
    textView.linkTextAttributes = [
      .foregroundColor: NSColor.linkColor,
      .cursor: NSCursor.pointingHand,
    ]
    textView.delegate = delegate
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
    if let scrollView = textView.enclosingScrollView {
      Self.applyBottomOverscroll(to: textView, in: scrollView)
    }
    textView.setNeedsDisplay(textView.bounds)
  }

  // Re-runs or clears native spell indicators after content or preference changes.
  private static func applyContinuousSpellChecking(
    to textView: NSTextView,
    enabled: Bool,
    refresh: Bool
  ) {
    textView.isContinuousSpellCheckingEnabled = enabled
    textView.isGrammarCheckingEnabled = false
    guard refresh else { return }

    let fullRange = NSRange(location: 0, length: textView.string.utf16.count)
    guard fullRange.length > 0 else { return }

    textView.setSpellingState(0, range: fullRange)
    guard enabled else { return }

    let checkingTypes = NSTextCheckingTypes(NSTextCheckingResult.CheckingType.spelling.rawValue)
    textView.checkText(in: fullRange, types: checkingTypes)
  }

  // Updates the document view height so the scroll view always offers trailing overscroll space.
  private static func applyBottomOverscroll(
    to textView: NSTextView,
    in scrollView: NSScrollView,
    viewportHeight: CGFloat? = nil
  ) {
    let resolvedViewportHeight = viewportHeight ?? scrollView.contentSize.height
    guard resolvedViewportHeight > 0 else { return }

    let targetHeight = targetEditorHeight(
      documentHeight: textView.editorDocumentHeight(),
      viewportHeight: resolvedViewportHeight
    )

    if textView.minSize.height != targetHeight {
      textView.minSize = NSSize(width: 0, height: targetHeight)
    }

    if textView.frame.height != targetHeight {
      var frame = textView.frame
      frame.size.height = targetHeight
      textView.frame = frame
    }
  }

  private func clampedRange(_ range: NSRange, maxLength: Int) -> NSRange {
    let safeLocation = min(range.location, maxLength)
    let safeLength = min(range.length, max(maxLength - safeLocation, 0))
    return NSRange(location: safeLocation, length: safeLength)
  }

  // Clears any previous search highlights then paints new ones using rendering attributes,
  // which are visual-only and do not touch the text storage or trigger the text delegate.
  static func applySearchHighlights(to textView: NSTextView, query: String, accentColor: NSColor) {
    guard let tlm = textView.textLayoutManager,
      let tcs = tlm.textContentManager as? NSTextContentStorage
    else { return }

    tlm.removeRenderingAttribute(.backgroundColor, for: tlm.documentRange)

    guard !query.isEmpty else {
      textView.setNeedsDisplay(textView.bounds)
      return
    }

    let highlightColor = accentColor.withAlphaComponent(0.3)
    let string = textView.string
    let docBase = tlm.documentRange.location
    var searchStart = string.startIndex

    while searchStart < string.endIndex,
      let matchRange = string.range(
        of: query, options: .caseInsensitive, range: searchStart..<string.endIndex)
    {
      let nsRange = NSRange(matchRange, in: string)
      if let startLoc = tcs.location(docBase, offsetBy: nsRange.location),
        let endLoc = tcs.location(startLoc, offsetBy: nsRange.length),
        let textRange = NSTextRange(location: startLoc, end: endLoc)
      {
        tlm.addRenderingAttribute(.backgroundColor, value: highlightColor, for: textRange)
      }
      searchStart = matchRange.upperBound
    }

    textView.setNeedsDisplay(textView.bounds)
  }
}

@MainActor
private final class EditorScrollView: NSScrollView {
  var onViewportHeightChange: ((CGFloat) -> Void)?

  override func tile() {
    super.tile()
    onViewportHeightChange?(contentSize.height)
  }
}

// MARK: - Spell Checking

enum MarkdownEditorSpellChecking {
  // Computes the markdown-sensitive ranges that native spell checking should ignore.
  static func ignoredRanges(
    in attributedString: NSAttributedString,
    within targetRange: NSRange? = nil
  ) -> [NSRange] {
    let fullLength = attributedString.length
    guard fullLength > 0 else { return [] }

    let resolvedRange = clampedRange(
      targetRange ?? NSRange(location: 0, length: fullLength), maxLength: fullLength)
    guard resolvedRange.length > 0 else { return [] }

    var ignoredRanges: [NSRange] = []
    attributedString.enumerateAttributes(in: resolvedRange, options: []) { attributes, range, _ in
      guard range.length > 0, shouldIgnore(attributes) else { return }
      ignoredRanges.append(range)
    }

    return mergeContiguousRanges(ignoredRanges)
  }

  // Returns true when the given character range overlaps a markdown-sensitive region.
  static func hasIgnoredOverlap(_ range: NSRange, in attributedString: NSAttributedString) -> Bool {
    let ignoredRanges = ignoredRanges(in: attributedString, within: range)
    return ignoredRanges.contains { NSIntersectionRange($0, range).length > 0 }
  }

  // Removes native spell-check results that land inside ignored markdown regions.
  static func filterTextCheckingResults(
    _ results: [NSTextCheckingResult],
    ignoredRanges: [NSRange]
  ) -> [NSTextCheckingResult] {
    guard !ignoredRanges.isEmpty else { return results }

    return results.filter { result in
      ignoredRanges.allSatisfy { NSIntersectionRange($0, result.range).length == 0 }
    }
  }

  // Clamps external ranges to the bounds of the current attributed string.
  private static func clampedRange(_ range: NSRange, maxLength: Int) -> NSRange {
    let safeLocation = min(max(range.location, 0), maxLength)
    let safeLength = min(range.length, max(maxLength - safeLocation, 0))
    return NSRange(location: safeLocation, length: safeLength)
  }

  // Treats code, links, and structural markers as non-prose for spell-check purposes.
  private static func shouldIgnore(_ attributes: [NSAttributedString.Key: Any]) -> Bool {
    attributes[.markdownCodeFence] as? Bool == true
      || attributes[.markdownCodeBlock] as? Bool == true
      || attributes[.markdownInlineCode] as? Bool == true
      || attributes[.markdownLinkURL] != nil
      || attributes[.link] != nil
      || attributes[.markdownSectionDivider] as? Bool == true
      || attributes[.markdownHorizontalRule] as? Bool == true
  }

  // Coalesces adjacent ignored spans so result filtering stays cheap and deterministic.
  private static func mergeContiguousRanges(_ ranges: [NSRange]) -> [NSRange] {
    let sortedRanges = ranges.filter { $0.length > 0 }.sorted { $0.location < $1.location }
    guard let firstRange = sortedRanges.first else { return [] }

    var mergedRanges: [NSRange] = [firstRange]
    for range in sortedRanges.dropFirst() {
      let lastIndex = mergedRanges.count - 1
      let previousRange = mergedRanges[lastIndex]
      if range.location <= NSMaxRange(previousRange) {
        let mergedEnd = max(NSMaxRange(previousRange), NSMaxRange(range))
        mergedRanges[lastIndex] = NSRange(
          location: previousRange.location,
          length: mergedEnd - previousRange.location
        )
      } else {
        mergedRanges.append(range)
      }
    }

    return mergedRanges
  }
}

// MARK: - Coordinator

extension MarkdownEditorView {
  @MainActor
  final class Coordinator: NSObject, NSTextViewDelegate {
    private struct PendingEditContext {
      let range: NSRange
      let replacementString: String?
    }

    var parent: MarkdownEditorView
    var isUpdating = false
    var lastPushedMarkdown = ""
    var lastAppliedAppearance = NoteAppearanceSettings.default
    var lastContinuousSpellCheckingEnabled = true
    var lastDividerCount = 0
    var lastNoteID: DayNote.ID?
    var lastSearchText = ""
    let toolbar = EditorFormattingToolbar()
    let slashPopup = EditorSlashCommandPopup()
    private var slashTriggerLocation: Int?
    private var pendingEditContext: PendingEditContext?
    private var pendingSlashHeadingLineLocation: Int?
    private var pendingSlashHeadingTypingAttributes: [NSAttributedString.Key: Any]?
    private var isApplyingSlashCommand = false
    private var pendingMarkdownTask: Task<Void, Never>?

    init(parent: MarkdownEditorView) {
      self.parent = parent
      super.init()
      toolbar.appearanceSettings = parent.appearanceSettings
    }

    // Captures the pending edit context before AppKit applies the change.
    func textView(
      _ textView: NSTextView,
      shouldChangeTextIn affectedCharRange: NSRange,
      replacementString: String?
    ) -> Bool {
      if let pendingSlashHeadingLineLocation,
        let pendingSlashHeadingTypingAttributes
      {
        let pendingLineStart = lineStartLocation(
          for: pendingSlashHeadingLineLocation,
          in: textView.textStorage
        )
        let currentLineStart = lineStartLocation(
          for: affectedCharRange.location,
          in: textView.textStorage
        )
        if currentLineStart == pendingLineStart {
          textView.typingAttributes = pendingSlashHeadingTypingAttributes
          if let replacementString, !replacementString.isEmpty {
            clearPendingSlashHeadingOverride()
          }
        } else {
          clearPendingSlashHeadingOverride()
        }
      }

      pendingEditContext = PendingEditContext(
        range: affectedCharRange,
        replacementString: replacementString
      )
      return true
    }

    // Updates toolbar visibility and syncs typing attributes on selection change.
    func textViewDidChangeSelection(_ notification: Notification) {
      guard let textView = notification.object as? NSTextView else { return }

      if let editorTextView = textView as? MarkdownEditorTextView,
        editorTextView.editorNormalizeSelectionIfNeeded()
      {
        return
      }

      let range = textView.selectedRange()

      if slashPopup.isVisible, let triggerLoc = slashTriggerLocation {
        let nsString = textView.string as NSString
        let triggerLine = nsString.lineRange(for: NSRange(location: triggerLoc, length: 0))
        let cursorLine = nsString.lineRange(for: NSRange(location: range.location, length: 0))
        if triggerLine != cursorLine || range.length > 0 {
          dismissSlashPopup()
        }
      }

      if range.length > 0, let scrollView = textView.enclosingScrollView {
        let selectionRect = textView.editorRectInViewCoordinates(forCharacterRange: range) ?? .zero
        let rectInScrollView = textView.convert(selectionRect, to: scrollView)
        toolbar.textView = textView
        toolbar.show(relativeTo: rectInScrollView, in: scrollView)
      } else {
        toolbar.hide()
      }

      if range.length == 0, let textStorage = textView.textStorage {
        syncTypingAttributesToInsertionPoint(in: textView, textStorage: textStorage)
      }
    }

    // Formats the edited line immediately, then schedules the O(n) markdown conversion.
    func textDidChange(_ notification: Notification) {
      guard !isUpdating else { return }
      guard let textView = notification.object as? NSTextView,
        let textStorage = textView.textStorage
      else { return }

      isUpdating = true
      if !isApplyingSlashCommand {
        autoformatEditedLinesIfNeeded(in: textView, textStorage: textStorage)
      }
      isUpdating = false

      // Slash command operations require immediate push — the binding must be current before
      // the command handler returns. Regular typing is debounced for performance.
      if isApplyingSlashCommand {
        executePushMarkdown(from: textStorage)
      } else {
        scheduleMarkdownPush(from: textStorage)
      }

      if let editorTextView = textView as? MarkdownEditorTextView {
        let dividerCount = editorTextView.sectionDividerCount
        if dividerCount != lastDividerCount {
          editorTextView.refreshSectionLayout()
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

    // Drops spell-check matches that land inside code, links, or structural markdown markers.
    func textView(
      _ textView: NSTextView,
      didCheckTextIn range: NSRange,
      types checkingTypes: NSTextCheckingTypes,
      options: [NSSpellChecker.OptionKey: Any],
      results: [NSTextCheckingResult],
      orthography: NSOrthography,
      wordCount: Int
    ) -> [NSTextCheckingResult] {
      guard let textStorage = textView.textStorage else { return results }
      let ignoredRanges = MarkdownEditorSpellChecking.ignoredRanges(in: textStorage, within: range)
      return MarkdownEditorSpellChecking.filterTextCheckingResults(
        results,
        ignoredRanges: ignoredRanges
      )
    }

    // Blocks any spelling indicator that would otherwise bleed into ignored markdown regions.
    func textView(
      _ textView: NSTextView,
      shouldSetSpellingState value: Int,
      range affectedCharRange: NSRange
    ) -> Int {
      guard value != 0, let textStorage = textView.textStorage else { return value }
      return MarkdownEditorSpellChecking.hasIgnoredOverlap(affectedCharRange, in: textStorage)
        ? 0
        : value
    }

    // Debounces the full O(n) conversion so it runs once after a pause in typing.
    private func scheduleMarkdownPush(from textStorage: NSTextStorage) {
      pendingMarkdownTask?.cancel()
      pendingMarkdownTask = Task { [weak self, weak textStorage] in
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard !Task.isCancelled, let self, let textStorage else { return }
        self.executePushMarkdown(from: textStorage)
      }
    }

    // Runs the conversion and pushes the result to the SwiftUI binding.
    private func executePushMarkdown(from textStorage: NSTextStorage) {
      pendingMarkdownTask = nil
      let markdown = MarkdownEditorFormatter.convertToMarkdown(from: textStorage)
      lastPushedMarkdown = markdown
      parent.text = markdown
    }

    // Flushes any pending debounced push immediately. Must be called before the coordinator's
    // parent is updated so the conversion still targets the old note's binding.
    func flushPendingMarkdownPushIfNeeded(from textStorage: NSTextStorage) {
      guard pendingMarkdownTask != nil else { return }
      pendingMarkdownTask?.cancel()
      executePushMarkdown(from: textStorage)
    }

    // Re-applies insertion typing attributes to the active caret.
    func syncTypingAttributesToCurrentSelection(in textView: NSTextView) {
      guard textView.selectedRange().length == 0, let textStorage = textView.textStorage else {
        return
      }
      syncTypingAttributesToInsertionPoint(in: textView, textStorage: textStorage)
    }

    // Handles Enter, Tab, Backspace, and slash popup navigation.
    func textView(
      _ textView: NSTextView,
      doCommandBy commandSelector: Selector
    ) -> Bool {
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
        flushPendingMarkdownPushIfNeeded(from: textStorage)
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

      var lineRange = fullLineRange
      if lineRange.length > 0
        && nsString.character(at: lineRange.location + lineRange.length - 1) == 0x0A
      {
        lineRange.length -= 1
      }

      let lineText = nsString.substring(with: lineRange)

      // Empty list item → cancel continuation
      if isEmptyListItem(lineText) {
        return textView.performEditorEdit(
          affectedRange: lineRange,
          replacementString: "",
          actionName: "Remove List Marker"
        ) { textStorage in
          textStorage.replaceCharacters(in: lineRange, with: "")
          return NSRange(location: lineRange.location, length: 0)
        }
      }

      // Empty blockquote → cancel continuation
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

      // Slash command execution
      let slashCommand = EditorSlashCommandHandler.matchedCommand(
        in: textStorage, lineRange: lineRange)
      if let slashCommand {
        switch slashCommand.action {
        case .sectionDivider:
          let replacementRange =
            fullLineRange.length > lineRange.length ? fullLineRange : lineRange
          let baseAttrs = MarkdownEditorFormatter.baseTypingAttributes(
            for: parent.appearanceSettings)
          let dividerLine = NSMutableAttributedString(
            attributedString: MarkdownEditorFormatter.sectionDividerDisplayString(
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

          _ = textView.editorNormalizeSelectionIfNeeded(prefer: .next)
          if let editorTextView = textView as? MarkdownEditorTextView {
            editorTextView.refreshSectionLayout()
          } else {
            textView.ensureEditorLayoutForEntireDocument()
            textView.setNeedsDisplay(textView.bounds)
          }

          textView.typingAttributes = headingTypingAttributes(level: 1)
          // Flush the debounced push so the binding reflects the divider insertion immediately.
          if let textStorage = textView.textStorage {
            flushPendingMarkdownPushIfNeeded(from: textStorage)
          }
          return true

        case .heading(let level):
          let handled = textView.performEditorEdit(
            affectedRange: lineRange,
            replacementString: "",
            actionName: "Insert Heading"
          ) { textStorage in
            textStorage.replaceCharacters(in: lineRange, with: NSAttributedString())
            return NSRange(location: lineRange.location, length: 0)
          }
          if handled {
            let headingAttributes = headingTypingAttributes(level: level)
            textView.typingAttributes = headingAttributes
            pendingSlashHeadingLineLocation = lineRange.location
            pendingSlashHeadingTypingAttributes = headingAttributes
            flushPendingMarkdownPushIfNeeded(from: textStorage)
          }
          return handled

        case .codeBlock:
          let snippet = "```\n\n\n```"
          let displaySnippet = MarkdownEditorFormatter.formatForDisplay(
            snippet, appearance: parent.appearanceSettings)
          let handled = textView.performEditorEdit(
            affectedRange: lineRange,
            replacementString: snippet,
            actionName: "Insert Code Block"
          ) { textStorage in
            textStorage.replaceCharacters(in: lineRange, with: displaySnippet)
            return NSRange(location: lineRange.location + 4, length: 0)
          }
          if handled {
            textView.typingAttributes = codeBlockTypingAttributes()
            textView.setNeedsDisplay(textView.bounds)
            flushPendingMarkdownPushIfNeeded(from: textStorage)
          }
          return handled
        }
      }

      // Normal newline with list continuation
      var continuedListType: MarkdownListType?
      var continuedBlockquote = false
      let continuedCodeBlock =
        lineRange.length > 0
        && textStorage.attribute(.markdownCodeBlock, at: lineRange.location, effectiveRange: nil)
          as? Bool == true
      let currentIndentLevel: Int = {
        guard lineRange.length > 0 else { return 0 }
        return textStorage.attribute(
          .markdownIndentLevel, at: lineRange.location, effectiveRange: nil)
          as? Int ?? 0
      }()
      let cursorOffsetInLine = cursorLocation - lineRange.location
      let cursorAtLineEnd = cursorOffsetInLine >= lineRange.length

      let handled = textView.performEditorEdit(
        affectedRange: lineRange,
        replacementString: "\n",
        actionName: "Insert Newline"
      ) { textStorage in
        let priorLineLength = lineRange.length
        continuedListType = MarkdownEditorFormatter.formatCurrentLine(
          in: textStorage,
          lineRange: lineRange,
          appearance: parent.appearanceSettings
        )

        let formattedNS = textStorage.string as NSString
        let formattedFullRange = formattedNS.lineRange(
          for: NSRange(
            location: min(lineRange.location, max(formattedNS.length - 1, 0)), length: 0)
        )
        let formattedLineEnd = min(NSMaxRange(formattedFullRange), formattedNS.length)
        var formattedLineLength = formattedLineEnd - lineRange.location
        if formattedLineLength > 0,
          formattedNS.character(at: lineRange.location + formattedLineLength - 1) == 0x0A
        {
          formattedLineLength -= 1
        }

        let splitPoint: Int
        if cursorAtLineEnd {
          splitPoint = lineRange.location + formattedLineLength
        } else {
          let delta = formattedLineLength - priorLineLength
          let adjustedOffset = max(0, min(cursorOffsetInLine + delta, formattedLineLength))
          splitPoint = lineRange.location + adjustedOffset
        }

        let newlineAttrs = MarkdownEditorFormatter.baseTypingAttributes(
          for: parent.appearanceSettings)
        textStorage.insert(
          NSAttributedString(string: "\n", attributes: newlineAttrs), at: splitPoint)
        var nextInsertionLocation = splitPoint + 1

        let updatedNS = textStorage.string as NSString
        let updatedLine = updatedNS.lineRange(
          for: NSRange(
            location: min(lineRange.location, max(updatedNS.length - 1, 0)), length: 0))
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

      _ = textView.editorNormalizeSelectionIfNeeded(prefer: .previous)

      if continuedCodeBlock {
        textView.typingAttributes = codeBlockTypingAttributes()
      } else if continuedBlockquote, continuedListType == nil {
        textView.typingAttributes = [
          .font: parent.appearanceSettings.bodyFont,
          .foregroundColor: NSColor.secondaryLabelColor,
          .paragraphStyle: MarkdownEditorFormatter.blockquoteParagraphStyle(
            for: parent.appearanceSettings),
          .markdownBlockquote: true,
        ]
      } else if continuedListType == nil {
        textView.typingAttributes = MarkdownEditorFormatter.baseTypingAttributes(
          for: parent.appearanceSettings)
      }

      if let editorTextView = textView as? MarkdownEditorTextView {
        editorTextView.refreshSectionLayout()
      } else {
        textView.ensureEditorLayoutForEntireDocument()
        textView.setNeedsDisplay(textView.bounds)
      }

      return true
    }

    // MARK: - Toolbar

    func refreshToolbarPresentation(in textView: NSTextView) {
      let range = textView.selectedRange()
      guard
        range.length > 0,
        let scrollView = textView.enclosingScrollView,
        let selectionRect = textView.editorRectInViewCoordinates(forCharacterRange: range)
      else {
        toolbar.hide()
        return
      }

      toolbar.appearanceSettings = parent.appearanceSettings
      toolbar.textView = textView
      toolbar.show(relativeTo: textView.convert(selectionRect, to: scrollView), in: scrollView)
    }

    // MARK: - List Continuation Helpers

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
        "\(MarkdownEditorFormatter.bulletMarker) ",
        "\(MarkdownEditorFormatter.bulletMarker)",
        "\(MarkdownEditorFormatter.attachmentChar) ",
        "\(MarkdownEditorFormatter.attachmentChar)",
        "- ",
        "-",
      ]
      if emptyMarkers.contains(trimmed) { return true }
      if trimmed.range(of: #"^\d+\.\s*$"#, options: .regularExpression) != nil { return true }
      return false
    }

    private func continuationMarker(for listType: MarkdownListType, previousLineText: String)
      -> String
    {
      switch listType {
      case .bullet:
        return "\(MarkdownEditorFormatter.bulletMarker) "
      case .checkboxUnchecked, .checkboxChecked:
        return "\(MarkdownEditorFormatter.uncheckedMarker) "
      case .numbered:
        if let match = previousLineText.range(of: #"^(\d+)\."#, options: .regularExpression) {
          let numStr = previousLineText[match].dropLast()
          if let num = Int(numStr) { return "\(num + 1). " }
        }
        return "1. "
      }
    }

    private func continuationAttributedMarker(
      for listType: MarkdownListType, marker: String, appearance: NoteAppearanceSettings,
      indentLevel: Int = 0
    ) -> NSAttributedString {
      let listStyle = MarkdownEditorFormatter.listParagraphStyle(
        for: appearance, indentLevel: indentLevel)
      switch listType {
      case .checkboxUnchecked, .checkboxChecked:
        let result = NSMutableAttributedString()
        result.append(
          MarkdownEditorFormatter.checkboxAttributedString(checked: false, appearance: appearance))
        result.append(
          NSAttributedString(
            string: " ",
            attributes: [
              .font: appearance.bodyFont,
              .foregroundColor: NSColor.labelColor,
              .paragraphStyle: MarkdownEditorFormatter.bodyParagraphStyle(for: appearance),
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
              .foregroundColor: MarkdownEditorFormatter.bulletColor(for: appearance),
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

    // Changes the indent level of list lines covered by the selection.
    // Uses performEditorEdit for undo support, then immediately pushes
    // the updated markdown so the indent survives the round-trip.
    func handleListIndent(textView: NSTextView, increase: Bool) -> Bool {
      guard let textStorage = textView.textStorage else { return false }
      let nsString = textStorage.string as NSString
      let selectedRange = textView.selectedRange()
      let fullRange = nsString.lineRange(for: selectedRange)

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

      let appearance =
        (textView as? MarkdownEditorTextView)?.appearanceSettings ?? .default

      // Prevent textDidChange from reformatting the line and resetting the paragraph style.
      isUpdating = true
      let editSucceeded = textView.performEditorEdit(
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
                let newStyle = MarkdownEditorFormatter.listParagraphStyle(
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
      isUpdating = false

      if editSucceeded {
        // Push updated markdown immediately so the indent persists.
        executePushMarkdown(from: textStorage)
      }

      return true
    }

    // MARK: - Section Divider Backspace

    private func handleSectionDividerBackspace(
      in textView: NSTextView, textStorage: NSTextStorage
    ) -> Bool {
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

      if let editorTextView = textView as? MarkdownEditorTextView {
        editorTextView.refreshSectionLayout()
      } else {
        textView.setNeedsDisplay(textView.bounds)
      }

      return true
    }

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

    // MARK: - Slash Command Popup

    private func checkSlashCommandTrigger(in textView: NSTextView) {
      let cursorLocation = textView.selectedRange().location
      guard cursorLocation > 0 else {
        dismissSlashPopup()
        return
      }

      let nsString = textView.string as NSString
      let lineRange = nsString.lineRange(for: NSRange(location: cursorLocation, length: 0))

      let prefixLength = cursorLocation - lineRange.location
      guard prefixLength > 0 else {
        dismissSlashPopup()
        return
      }
      let prefixRange = NSRange(location: lineRange.location, length: prefixLength)
      let prefixText = nsString.substring(with: prefixRange)
      let trimmed = prefixText.trimmingCharacters(in: .whitespaces)

      guard trimmed.hasPrefix("/") else {
        dismissSlashPopup()
        return
      }

      let filtered = EditorSlashCommandHandler.filteredCommands(for: trimmed)
      guard !filtered.isEmpty else {
        dismissSlashPopup()
        return
      }

      if slashTriggerLocation == nil {
        let whitespaceCount = prefixText.count - trimmed.count
        slashTriggerLocation = lineRange.location + whitespaceCount
      }

      slashPopup.updateFilter(trimmed)

      guard
        let scrollView = textView.enclosingScrollView,
        let lineRect = textView.editorLineFragmentRect(forCharacterLocation: cursorLocation)
      else { return }

      let rectInScrollView = textView.convert(lineRect, to: scrollView)
      slashPopup.show(relativeTo: rectInScrollView, in: scrollView)

      slashPopup.onSelect = { [weak self, weak textView] entry in
        guard let self, let textView else { return }
        self.applySlashCommand(entry, in: textView)
      }
    }

    private func dismissSlashPopup() {
      slashPopup.hide()
      slashTriggerLocation = nil
    }

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

    // MARK: - Autoformat

    private func autoformatEditedLinesIfNeeded(
      in textView: NSTextView, textStorage: NSTextStorage
    ) {
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
          MarkdownEditorFormatter.formatCurrentLine(
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

      if let editorTextView = textView as? MarkdownEditorTextView {
        applySectionColorsToEditedLines(
          lineRanges, in: textStorage, editorTextView: editorTextView)
      }

      textView.setSelectedRange(
        clampedRange(updatedSelection, maxLength: textStorage.string.utf16.count)
      )
      if textView is MarkdownEditorTextView {
        _ = textView.editorNormalizeSelectionIfNeeded()
      }
      syncTypingAttributesToInsertionPoint(in: textView, textStorage: textStorage)
    }

    private func applySectionColorsToEditedLines(
      _ lineRanges: [NSRange],
      in textStorage: NSTextStorage,
      editorTextView: MarkdownEditorTextView
    ) {
      for lineRange in lineRanges {
        guard lineRange.location < textStorage.length else { continue }
        guard let sectionInfo = editorTextView.sectionColors(at: lineRange.location) else {
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

        if attrs[.markdownHeadingLevel] != nil,
          attrs[.markdownHeadingColor] == nil,
          let colorName = sectionInfo.headingColorName,
          let color = MarkdownEditorFormatter.headingColor(named: colorName)
        {
          textStorage.addAttribute(.foregroundColor, value: color, range: trimmed)
          continue
        }

        guard sectionInfo.useSectionColor,
          let rawType = attrs[.markdownListType] as? String,
          let listType = MarkdownListType(rawValue: rawType)
        else { continue }

        let color: NSColor? = {
          if let n = sectionInfo.bulletColorName {
            return MarkdownEditorFormatter.headingColor(named: n)
          }
          if let n = sectionInfo.headingColorName {
            return MarkdownEditorFormatter.headingColor(named: n)
          }
          return nil
        }()
        guard let bulletColor = color else { continue }

        switch listType {
        case .bullet:
          textStorage.addAttributes(
            [
              .foregroundColor: bulletColor,
              .font: NSFont.systemFont(
                ofSize: editorTextView.appearanceSettings.bulletSize, weight: .bold),
            ], range: NSRange(location: trimmed.location, length: 1))
        case .checkboxChecked, .checkboxUnchecked:
          let checked = listType == .checkboxChecked
          let newAttachment = NSAttributedString(
            attachment: MarkdownEditorFormatter.checkboxAttachment(
              checked: checked, color: bulletColor))
          let preservedParagraphStyle = attrs[.paragraphStyle]
          let preservedIndentLevel = attrs[.markdownIndentLevel]
          textStorage.replaceCharacters(
            in: NSRange(location: trimmed.location, length: 1), with: newAttachment)
          textStorage.addAttribute(
            .markdownListType, value: listType.rawValue,
            range: NSRange(location: trimmed.location, length: 1))
          if let preservedParagraphStyle {
            textStorage.addAttribute(
              .paragraphStyle,
              value: preservedParagraphStyle,
              range: NSRange(location: trimmed.location, length: 1)
            )
          }
          if let preservedIndentLevel {
            textStorage.addAttribute(
              .markdownIndentLevel,
              value: preservedIndentLevel,
              range: NSRange(location: trimmed.location, length: 1)
            )
          }
        case .numbered:
          break
        }
      }
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

    // MARK: - Typing Attributes

    private func syncTypingAttributesToInsertionPoint(
      in textView: NSTextView,
      textStorage: NSTextStorage
    ) {
      if let pendingSlashHeadingLineLocation,
        let pendingSlashHeadingTypingAttributes
      {
        let pendingLineStart = lineStartLocation(
          for: pendingSlashHeadingLineLocation,
          in: textStorage
        )
        let currentLineStart = lineStartLocation(
          for: textView.selectedRange().location,
          in: textStorage
        )
        if currentLineStart == pendingLineStart {
          textView.typingAttributes = pendingSlashHeadingTypingAttributes
          return
        }
        clearPendingSlashHeadingOverride()
      }

      guard textStorage.length > 0 else {
        textView.typingAttributes = MarkdownEditorFormatter.baseTypingAttributes(
          for: parent.appearanceSettings)
        return
      }

      if let editorTextView = textView as? MarkdownEditorTextView,
        let sourceLocation = editorTextView.typingAttributeSourceLocation(
          forInsertionLocation: textView.selectedRange().location)
      {
        textView.typingAttributes = textStorage.attributes(
          at: sourceLocation,
          effectiveRange: nil
        )
        return
      }

      textView.typingAttributes = MarkdownEditorFormatter.baseTypingAttributes(
        for: parent.appearanceSettings)
    }

    private func clearPendingSlashHeadingOverride() {
      pendingSlashHeadingLineLocation = nil
      pendingSlashHeadingTypingAttributes = nil
    }

    private func lineStartLocation(for location: Int, in textStorage: NSTextStorage?) -> Int {
      guard let textStorage else { return 0 }
      let nsString = textStorage.string as NSString
      if nsString.length == 0 { return 0 }
      let safeLocation = min(max(location, 0), nsString.length)

      if safeLocation == nsString.length {
        let previousCharacter = nsString.character(at: nsString.length - 1)
        // Caret is on the trailing empty line after a newline.
        if previousCharacter == 0x0A {
          return safeLocation
        }
        return nsString.lineRange(
          for: NSRange(location: nsString.length - 1, length: 0)
        ).location
      }

      return nsString.lineRange(for: NSRange(location: safeLocation, length: 0)).location
    }

    // MARK: - Typing Attribute Helpers

    private func headingTypingAttributes(level: Int) -> [NSAttributedString.Key: Any] {
      [
        .font: parent.appearanceSettings.boldBodyFont(
          ofSize: MarkdownEditorFormatter.headingFontSize(for: level)),
        .foregroundColor: NSColor.labelColor,
        .paragraphStyle: MarkdownEditorFormatter.bodyParagraphStyle(for: parent.appearanceSettings),
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

    // MARK: - Utility

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

    private func clampedRange(_ range: NSRange, maxLength: Int) -> NSRange {
      let safeLocation = min(range.location, maxLength)
      let safeLength = min(range.length, max(maxLength - safeLocation, 0))
      return NSRange(location: safeLocation, length: safeLength)
    }
  }
}
