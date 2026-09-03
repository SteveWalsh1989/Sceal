//
//  EditorFormattingToolbar.swift
//
//

// Floating AppKit toolbar for inline and block-level text formatting.

import AppKit

enum EditorFormattingToolbarLayout {
  static let gap: CGFloat = 4
  static let edgeInset: CGFloat = 4

  // Places the toolbar visually above the selection for either AppKit coordinate direction.
  static func origin(
    selectionRect: NSRect,
    toolbarSize: NSSize,
    parentBounds: NSRect,
    parentIsFlipped: Bool
  ) -> NSPoint {
    let preferredAboveY: CGFloat
    let fallbackBelowY: CGFloat
    let hasSpaceAbove: Bool

    if parentIsFlipped {
      preferredAboveY = selectionRect.minY - toolbarSize.height - gap
      fallbackBelowY = selectionRect.maxY + gap
      hasSpaceAbove = preferredAboveY >= parentBounds.minY + edgeInset
    } else {
      preferredAboveY = selectionRect.maxY + gap
      fallbackBelowY = selectionRect.minY - toolbarSize.height - gap
      hasSpaceAbove =
        preferredAboveY + toolbarSize.height <= parentBounds.maxY - edgeInset
    }

    let minimumX = parentBounds.minX + edgeInset
    let maximumX = max(minimumX, parentBounds.maxX - toolbarSize.width - edgeInset)
    let minimumY = parentBounds.minY + edgeInset
    let maximumY = max(minimumY, parentBounds.maxY - toolbarSize.height - edgeInset)
    let centeredX = selectionRect.midX - toolbarSize.width / 2
    let preferredY = hasSpaceAbove ? preferredAboveY : fallbackBelowY

    return NSPoint(
      x: min(max(centeredX, minimumX), maximumX),
      y: min(max(preferredY, minimumY), maximumY)
    )
  }
}

@MainActor class EditorFormattingToolbar: NSView {
  private static weak var visibleToolbar: EditorFormattingToolbar?

  weak var textView: NSTextView?
  var appearanceSettings = NoteAppearanceSettings.default
  var listMarkerColor: NSColor?

  private let stackView = NSStackView()
  private var colorSeparator: NSView?
  private var colorSwatches: [NSView] = []
  private var lastKnownSelectionRange = NSRange(location: NSNotFound, length: 0)

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setup()
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  // MARK: - Setup

  // Builds the toolbar layout with formatting buttons, separators, and color swatches.
  private func setup() {
    wantsLayer = true
    layer?.backgroundColor = NSColor(white: 0.15, alpha: 0.95).cgColor
    layer?.cornerRadius = 8

    shadow = NSShadow()
    layer?.shadowColor = NSColor.black.withAlphaComponent(0.3).cgColor
    layer?.shadowOpacity = 1
    layer?.shadowRadius = 8
    layer?.shadowOffset = CGSize(width: 0, height: -2)

    stackView.orientation = .horizontal
    stackView.spacing = 1
    stackView.edgeInsets = NSEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
    addSubview(stackView)
    stackView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      stackView.topAnchor.constraint(equalTo: topAnchor),
      stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
      stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
      stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
    ])

    addTextButton("B", action: #selector(toggleBold), tooltip: "Bold", weight: .bold)
    addItalicButton()
    addStrikethroughButton()
    addSymbolButton(
      "chevron.left.forwardslash.chevron.right", action: #selector(toggleCode), tooltip: "Code")
    addSeparator()
    addTextButton("H1", action: #selector(applyH1), tooltip: "Heading 1", size: 11)
    addTextButton("H2", action: #selector(applyH2), tooltip: "Heading 2", size: 11)
    addTextButton("H3", action: #selector(applyH3), tooltip: "Heading 3", size: 11)
    addTextButton("P", action: #selector(applyParagraph), tooltip: "Paragraph", size: 11)
    addSeparator()
    addSymbolButton("list.bullet", action: #selector(toggleBullet), tooltip: "Bullet List")
    addSymbolButton("list.number", action: #selector(toggleNumbered), tooltip: "Numbered List")
    addSymbolButton("checklist", action: #selector(toggleCheckbox), tooltip: "Checkbox")
    addSymbolButton("text.quote", action: #selector(toggleBlockquote), tooltip: "Blockquote")
    addSymbolButton("link", action: #selector(showLinkPopover(_:)), tooltip: "Link")
    let sep = addSeparator()
    colorSeparator = sep
    for (index, entry) in ThemePalette.colors.enumerated() {
      let swatch = addColorSwatch(color: entry.color, name: entry.name, index: index)
      colorSwatches.append(swatch)
    }
  }

  // Creates a text-labeled formatting button.
  private func addTextButton(
    _ title: String, action: Selector, tooltip: String,
    weight: NSFont.Weight = .semibold, size: CGFloat = 13
  ) {
    let button = NSButton()
    button.attributedTitle = NSAttributedString(
      string: title,
      attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: NSColor.white,
      ])
    button.isBordered = false
    button.bezelStyle = .inline
    button.target = self
    button.action = action
    button.toolTip = tooltip
    button.widthAnchor.constraint(equalToConstant: title.count > 1 ? 30 : 26).isActive = true
    button.heightAnchor.constraint(equalToConstant: 26).isActive = true
    stackView.addArrangedSubview(button)
  }

  // Adds an italic-styled "I" button matching the bold "B" pattern
  private func addItalicButton() {
    let button = NSButton()
    let font = NSFontManager.shared.convert(
      NSFont.systemFont(ofSize: 13, weight: .semibold), toHaveTrait: .italicFontMask)
    button.attributedTitle = NSAttributedString(
      string: "I",
      attributes: [
        .font: font,
        .foregroundColor: NSColor.white,
      ])
    button.isBordered = false
    button.bezelStyle = .inline
    button.target = self
    button.action = #selector(toggleItalic)
    button.toolTip = "Italic"
    button.widthAnchor.constraint(equalToConstant: 26).isActive = true
    button.heightAnchor.constraint(equalToConstant: 26).isActive = true
    stackView.addArrangedSubview(button)
  }

  // Adds a strikethrough-styled "S" button matching the bold and italic pattern
  private func addStrikethroughButton() {
    let button = NSButton()
    button.attributedTitle = NSAttributedString(
      string: "S",
      attributes: [
        .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
        .foregroundColor: NSColor.white,
        .strikethroughStyle: NSUnderlineStyle.single.rawValue,
      ])
    button.isBordered = false
    button.bezelStyle = .inline
    button.target = self
    button.action = #selector(toggleStrikethrough)
    button.toolTip = "Strikethrough"
    button.widthAnchor.constraint(equalToConstant: 26).isActive = true
    button.heightAnchor.constraint(equalToConstant: 26).isActive = true
    stackView.addArrangedSubview(button)
  }

  // Creates an SF Symbol formatting button.
  private func addSymbolButton(_ symbolName: String, action: Selector, tooltip: String) {
    let button = NSButton()
    let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
    if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: tooltip)?
      .withSymbolConfiguration(config)
    {
      button.image = image
      button.imageScaling = .scaleProportionallyDown
    }
    button.isBordered = false
    button.bezelStyle = .inline
    button.target = self
    button.action = action
    button.toolTip = tooltip
    button.contentTintColor = .white
    button.widthAnchor.constraint(equalToConstant: 26).isActive = true
    button.heightAnchor.constraint(equalToConstant: 26).isActive = true
    stackView.addArrangedSubview(button)
  }

  // Inserts a thin vertical divider between button groups.
  @discardableResult
  private func addSeparator() -> NSView {
    let sep = NSView()
    sep.wantsLayer = true
    sep.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor
    sep.translatesAutoresizingMaskIntoConstraints = false
    sep.widthAnchor.constraint(equalToConstant: 1).isActive = true
    sep.heightAnchor.constraint(equalToConstant: 16).isActive = true
    stackView.addArrangedSubview(sep)
    return sep
  }

  // Adds a clickable color circle for heading colors.
  @discardableResult
  private func addColorSwatch(color: NSColor, name: String, index: Int) -> NSButton {
    let button = NSButton()
    button.isBordered = false
    button.bezelStyle = .inline
    button.title = ""
    button.wantsLayer = true
    button.layer?.cornerRadius = 6
    button.layer?.backgroundColor = color.cgColor
    // Add a subtle border so the "white" swatch is visible against the dark toolbar
    if name == "white" {
      button.layer?.borderWidth = 1
      button.layer?.borderColor = NSColor.white.withAlphaComponent(0.3).cgColor
    }
    button.target = self
    button.action = #selector(applyHeadingColor(_:))
    button.toolTip = "Heading color: \(name)"
    button.tag = index
    button.widthAnchor.constraint(equalToConstant: 18).isActive = true
    button.heightAnchor.constraint(equalToConstant: 18).isActive = true
    stackView.addArrangedSubview(button)
    return button
  }

  // Shows or hides the color swatches based on whether the current line is a heading
  func updateColorSwatchVisibility() {
    let isHeading: Bool = {
      guard let textView, let textStorage = textView.textStorage else { return false }
      let (lineRange, _) = currentLineRange()
      guard lineRange.length > 0 else { return false }
      return textStorage.attribute(
        .markdownHeadingLevel, at: lineRange.location, effectiveRange: nil) != nil
    }()

    colorSeparator?.isHidden = !isHeading
    for swatch in colorSwatches {
      swatch.isHidden = !isHeading
    }
  }

  // Refreshes the visible controls and toolbar frame after line-level formatting changes.
  private func refreshToolbarPresentation() {
    updateColorSwatchVisibility()

    guard
      !isHidden,
      let textView,
      let scrollView = textView.enclosingScrollView,
      let selectionRect = currentSelectionRect(in: textView, scrollView: scrollView)
    else { return }

    show(relativeTo: selectionRect, in: scrollView)
  }

  // MARK: - Positioning

  // Positions and shows the toolbar relative to the current selection.
  func show(relativeTo selectionRect: NSRect, in parentView: NSView) {
    updateColorSwatchVisibility()
    if let textView {
      lastKnownSelectionRange = textView.selectedRange()
    }
    // Force layout after visibility changes so fittingSize reflects the current state
    // and the autoresizing mask constraint doesn't conflict with the stack view.
    stackView.layoutSubtreeIfNeeded()
    let size = fittingSize
    let toolbarHeight = max(size.height, 34)
    let toolbarWidth = max(size.width, 100)
    let toolbarSize = NSSize(width: toolbarWidth, height: toolbarHeight)
    let origin = EditorFormattingToolbarLayout.origin(
      selectionRect: selectionRect,
      toolbarSize: toolbarSize,
      parentBounds: parentView.bounds,
      parentIsFlipped: parentView.isFlipped
    )

    frame = NSRect(x: origin.x, y: origin.y, width: toolbarWidth, height: toolbarHeight)

    if superview == nil {
      parentView.addSubview(self)
    }

    if let visibleToolbar = Self.visibleToolbar, visibleToolbar !== self {
      visibleToolbar.hide()
    }
    Self.visibleToolbar = self
    isHidden = false
    alphaValue = 1
  }

  // Hides the toolbar.
  func hide() {
    isHidden = true
    if Self.visibleToolbar === self {
      Self.visibleToolbar = nil
    }
  }

  // MARK: - Inline Actions

  // Toggles bold formatting on the selected text.
  @objc private func toggleBold() {
    guard let (textView, textStorage, range) = preparedEditorContext(requireSelectedText: true)
    else { return }

    var allBold = true
    textStorage.enumerateAttribute(.markdownBold, in: range, options: []) { value, _, stop in
      if value as? Bool != true {
        allBold = false
        stop.pointee = true
      }
    }

    _ = textView.performEditorEdit(
      affectedRange: range,
      actionName: allBold ? "Remove Bold" : "Bold"
    ) { textStorage in
      if allBold {
        textStorage.removeAttribute(.markdownBold, range: range)
        textStorage.enumerateAttribute(.font, in: range, options: []) { value, attrRange, _ in
          let font = value as? NSFont ?? appearanceSettings.bodyFont
          let unboldFont = NSFontManager.shared.convert(font, toNotHaveTrait: .boldFontMask)
          textStorage.addAttribute(.font, value: unboldFont, range: attrRange)
        }
      } else {
        let currentFont =
          textStorage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
          ?? appearanceSettings.bodyFont
        let boldFont = NSFontManager.shared.convert(currentFont, toHaveTrait: .boldFontMask)
        textStorage.addAttribute(.font, value: boldFont, range: range)
        textStorage.addAttribute(.markdownBold, value: true, range: range)
      }
      return nil
    }
  }

  // Toggles italic trait and markdownItalic attribute on the selected text
  @objc private func toggleItalic() {
    guard let (textView, textStorage, range) = preparedEditorContext(requireSelectedText: true)
    else { return }

    var allItalic = true
    textStorage.enumerateAttribute(.markdownItalic, in: range, options: []) { value, _, stop in
      if value as? Bool != true {
        allItalic = false
        stop.pointee = true
      }
    }

    _ = textView.performEditorEdit(
      affectedRange: range,
      actionName: allItalic ? "Remove Italic" : "Italic"
    ) { textStorage in
      if allItalic {
        textStorage.removeAttribute(.markdownItalic, range: range)
        let currentFont =
          textStorage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
          ?? appearanceSettings.bodyFont
        let unitalicFont = NSFontManager.shared.convert(
          currentFont, toNotHaveTrait: .italicFontMask)
        textStorage.addAttribute(.font, value: unitalicFont, range: range)
      } else {
        let currentFont =
          textStorage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
          ?? appearanceSettings.bodyFont
        let italicFont = NSFontManager.shared.convert(currentFont, toHaveTrait: .italicFontMask)
        textStorage.addAttribute(.font, value: italicFont, range: range)
        textStorage.addAttribute(.markdownItalic, value: true, range: range)
      }
      return nil
    }
  }

  // Toggles strikethrough style and markdownStrikethrough attribute on the selected text
  @objc private func toggleStrikethrough() {
    guard let (textView, textStorage, range) = preparedEditorContext(requireSelectedText: true)
    else { return }

    var allStrike = true
    textStorage.enumerateAttribute(.markdownStrikethrough, in: range, options: []) {
      value, _, stop in
      if value as? Bool != true {
        allStrike = false
        stop.pointee = true
      }
    }

    _ = textView.performEditorEdit(
      affectedRange: range,
      actionName: allStrike ? "Remove Strikethrough" : "Strikethrough"
    ) { textStorage in
      if allStrike {
        textStorage.removeAttribute(.markdownStrikethrough, range: range)
        textStorage.removeAttribute(.strikethroughStyle, range: range)
      } else {
        textStorage.addAttributes(
          [
            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
            .markdownStrikethrough: true,
          ],
          range: range
        )
      }
      return nil
    }
  }

  // Toggles inline code formatting on the selected text.
  @objc private func toggleCode() {
    guard let (textView, textStorage, range) = preparedEditorContext(requireSelectedText: true)
    else { return }
    let inlineCodeFont = NSFont.monospacedSystemFont(
      ofSize: appearanceSettings.bodyFont.pointSize,
      weight: .regular
    )

    var allCode = true
    textStorage.enumerateAttribute(.markdownInlineCode, in: range, options: []) {
      value, _, stop in
      if value as? Bool != true {
        allCode = false
        stop.pointee = true
      }
    }

    _ = textView.performEditorEdit(
      affectedRange: range,
      actionName: allCode ? "Remove Inline Code" : "Inline Code"
    ) { textStorage in
      if allCode {
        textStorage.removeAttribute(.markdownInlineCode, range: range)
        textStorage.removeAttribute(.backgroundColor, range: range)
        textStorage.addAttribute(.font, value: appearanceSettings.bodyFont, range: range)
      } else {
        textStorage.addAttributes(
          [
            .font: inlineCodeFont,
            .backgroundColor: NSColor.quaternaryLabelColor,
            .markdownInlineCode: true,
          ],
          range: range
        )
      }
      return nil
    }
  }

  // MARK: - Heading Color Action

  // Applies a named heading color to the current line.
  @objc private func applyHeadingColor(_ sender: NSButton) {
    guard let textView, let textStorage = textView.textStorage else { return }
    let presetIndex = sender.tag
    guard presetIndex < ThemePalette.colors.count else { return }
    let preset = ThemePalette.colors[presetIndex]

    let (lineRange, _) = currentLineRange()
    guard lineRange.length > 0 else { return }

    let attrs = textStorage.attributes(at: lineRange.location, effectiveRange: nil)
    guard attrs[.markdownHeadingLevel] != nil else { return }

    _ = textView.performEditorEdit(affectedRange: lineRange, actionName: "Heading Color") {
      textStorage in
      textStorage.addAttribute(.foregroundColor, value: preset.color, range: lineRange)
      textStorage.addAttribute(.markdownHeadingColor, value: preset.name, range: lineRange)
      return nil
    }
    refreshToolbarPresentation()
  }

  // MARK: - Line-Level Actions

  // Converts the current heading line back to a plain paragraph.
  @objc private func applyParagraph() {
    guard let textView else { return }
    let (lineRange, _) = currentLineRange()
    guard lineRange.length > 0 else { return }

    _ = textView.performEditorEdit(affectedRange: lineRange, actionName: "Paragraph") {
      textStorage in
      applyParagraphAttributes(in: textStorage, range: lineRange)
      return nil
    }
    refreshToolbarPresentation()
  }

  @objc private func applyH1() { applyHeading(level: 1) }
  @objc private func applyH2() { applyHeading(level: 2) }
  @objc private func applyH3() { applyHeading(level: 3) }

  // Applies heading formatting at the given level to the current line.
  private func applyHeading(level: Int) {
    guard let textView, let textStorage = textView.textStorage else { return }
    let (lineRange, _) = currentLineRange()

    let currentLevel =
      lineRange.length > 0
      ? textStorage.attribute(.markdownHeadingLevel, at: lineRange.location, effectiveRange: nil)
        as? Int : nil

    _ = textView.performEditorEdit(
      affectedRange: lineRange,
      actionName: currentLevel == level ? "Paragraph" : "Heading \(level)"
    ) { textStorage in
      if currentLevel == level {
        applyParagraphAttributes(in: textStorage, range: lineRange)
      } else {
        let fontSize = MarkdownEditorFormatter.headingFontSize(for: level)
        textStorage.addAttribute(.markdownHeadingLevel, value: level, range: lineRange)
        textStorage.addAttribute(
          .font, value: appearanceSettings.boldBodyFont(ofSize: fontSize), range: lineRange)
        textStorage.removeAttribute(.markdownBlockquote, range: lineRange)
        textStorage.removeAttribute(.markdownListType, range: lineRange)
        textStorage.addAttribute(
          .paragraphStyle,
          value: MarkdownEditorFormatter.bodyParagraphStyle(for: appearanceSettings),
          range: lineRange)
      }
      return nil
    }
    refreshToolbarPresentation()
  }

  // Toggles bullet list formatting on the current line.
  @objc private func toggleBullet() { toggleListType(.bullet) }
  // Toggles numbered list formatting on the current line.
  @objc private func toggleNumbered() { toggleListType(.numbered) }
  // Toggles checkbox formatting on the current line.
  @objc private func toggleCheckbox() { toggleListType(.checkboxUnchecked) }

  // MARK: - Link Popover

  // Opens a popover to create or edit a markdown link on the selected text
  @objc private func showLinkPopover(_ sender: NSButton) {
    guard let (_, textStorage, range) = preparedEditorContext(requireSelectedText: true)
    else { return }

    let selectedText = (textStorage.string as NSString).substring(with: range)
    let existingURL =
      textStorage.attribute(.markdownLinkURL, at: range.location, effectiveRange: nil) as? String

    let popover = NSPopover()
    popover.behavior = .transient
    popover.contentSize = NSSize(width: 280, height: 120)

    let controller = EditorLinkPopoverViewController(
      linkText: selectedText, url: existingURL ?? "", hasExistingLink: existingURL != nil
    ) { [weak self] newText, newURL, removeLink in
      popover.performClose(nil)
      self?.applyLinkChange(
        range: range, newText: newText, newURL: newURL, removeLink: removeLink)
    }

    popover.contentViewController = controller
    popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
  }

  // Applies link text/URL changes or removes a link from the given range
  private func applyLinkChange(range: NSRange, newText: String, newURL: String, removeLink: Bool) {
    guard let textView, let textStorage = textView.textStorage else { return }
    guard range.location + range.length <= textStorage.length else { return }

    _ = textView.performEditorEdit(
      affectedRange: range,
      replacementString: removeLink ? nil : newText,
      actionName: removeLink ? "Remove Link" : "Edit Link"
    ) { textStorage in
      if removeLink {
        // Strip link attributes but keep the text
        textStorage.removeAttribute(.markdownLinkURL, range: range)
        textStorage.removeAttribute(.link, range: range)
        textStorage.removeAttribute(.underlineStyle, range: range)
        textStorage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
      } else {
        // Replace text if changed, then apply link attributes
        let replacement = NSAttributedString(
          string: newText,
          attributes: textStorage.attributes(at: range.location, effectiveRange: nil))
        textStorage.replaceCharacters(in: range, with: replacement)

        let newRange = NSRange(location: range.location, length: newText.utf16.count)
        var attrs: [NSAttributedString.Key: Any] = [
          .foregroundColor: NSColor.linkColor,
          .markdownLinkURL: newURL,
        ]
        if let url = URL(string: newURL) { attrs[.link] = url }
        textStorage.addAttributes(attrs, range: newRange)
        return NSRange(location: newRange.location + newRange.length, length: 0)
      }
      return nil
    }
  }

  // Toggles blockquote attribute and visual styling on the current line
  @objc private func toggleBlockquote() {
    guard let textView, let textStorage = textView.textStorage else { return }
    let (lineRange, lineText) = currentLineRange()
    guard lineRange.location != NSNotFound, NSMaxRange(lineRange) <= textStorage.length else {
      return
    }

    let isBlockquote =
      lineRange.length > 0
      ? textStorage.attribute(.markdownBlockquote, at: lineRange.location, effectiveRange: nil)
        as? Bool == true
      : false

    _ = textView.performEditorEdit(affectedRange: lineRange, actionName: "Blockquote") {
      textStorage in
      if isBlockquote {
        // Toggle off — preserve inline attributes (links, bold, etc.), reset block-level attrs only
        let content = NSMutableAttributedString(
          attributedString: textStorage.attributedSubstring(from: lineRange))
        let fullRange = NSRange(location: 0, length: content.length)
        content.addAttribute(
          .paragraphStyle,
          value: MarkdownEditorFormatter.bodyParagraphStyle(for: appearanceSettings),
          range: fullRange)
        content.removeAttribute(.markdownBlockquote, range: fullRange)
        // Restore label color for non-link spans (blockquote uses secondaryLabelColor)
        content.enumerateAttribute(.markdownLinkURL, in: fullRange, options: []) {
          linkURL, spanRange, _ in
          if linkURL == nil {
            content.addAttribute(.foregroundColor, value: NSColor.labelColor, range: spanRange)
          }
        }
        textStorage.replaceCharacters(in: lineRange, with: content)
      } else {
        // Apply blockquote — strip any existing list prefix, preserve inline attrs
        let currentTypeRaw =
          lineRange.length > 0
          ? textStorage.attribute(.markdownListType, at: lineRange.location, effectiveRange: nil)
            as? String
          : nil
        let existingMarkerLen: Int = {
          if let rawType = currentTypeRaw, let listType = MarkdownListType(rawValue: rawType) {
            return displayMarkerUTF16Length(in: lineText, listType: listType)
          }
          return 0
        }()
        let contentLoc = lineRange.location + existingMarkerLen
        let contentLen = max(0, lineRange.length - existingMarkerLen)
        let content: NSMutableAttributedString =
          contentLen > 0
          ? NSMutableAttributedString(
            attributedString: textStorage.attributedSubstring(
              from: NSRange(location: contentLoc, length: contentLen)))
          : NSMutableAttributedString()

        let quoteStyle = MarkdownEditorFormatter.blockquoteParagraphStyle(for: appearanceSettings)
        let fullRange = NSRange(location: 0, length: content.length)
        content.addAttribute(.markdownBlockquote, value: true, range: fullRange)
        content.addAttribute(.paragraphStyle, value: quoteStyle, range: fullRange)
        content.removeAttribute(.markdownListType, range: fullRange)
        content.removeAttribute(.markdownIndentLevel, range: fullRange)
        // Apply secondaryLabelColor for non-link spans only
        content.enumerateAttribute(.markdownLinkURL, in: fullRange, options: []) {
          linkURL, spanRange, _ in
          if linkURL == nil {
            content.addAttribute(
              .foregroundColor, value: NSColor.secondaryLabelColor, range: spanRange)
          }
        }
        textStorage.replaceCharacters(in: lineRange, with: content)
      }
      return nil
    }
  }

  // Toggles a specific list type, removing it if already active.
  private func toggleListType(_ targetType: MarkdownListType) {
    guard let textView, let textStorage = textView.textStorage else { return }
    let nsString = textStorage.string as NSString

    let selectedRange = textView.selectedRange()
    let fullRange = nsString.lineRange(for: selectedRange)
    var lines: [(range: NSRange, text: String)] = []
    var scanStart = fullRange.location
    while scanStart < NSMaxRange(fullRange) {
      let fullLineRange = nsString.lineRange(for: NSRange(location: scanStart, length: 0))
      guard NSMaxRange(fullLineRange) > scanStart else { break }
      var lineRange = fullLineRange
      if lineRange.length > 0
        && nsString.character(at: lineRange.location + lineRange.length - 1) == 0x0A
      {
        lineRange.length -= 1
      }
      let lineText = nsString.substring(with: lineRange)
      lines.append((lineRange, lineText))
      scanStart = NSMaxRange(fullLineRange)
    }

    guard !lines.isEmpty else { return }
    let source = textStorage.attributedSubstring(from: fullRange)
    let removesTargetType = lines.allSatisfy { line in
      guard line.range.length > 0 else { return false }
      let localLocation = line.range.location - fullRange.location
      return source.attribute(.markdownListType, at: localLocation, effectiveRange: nil) as? String
        == targetType.rawValue
    }

    _ = textView.performEditorEdit(affectedRange: fullRange, actionName: "List Style") {
      textStorage in
      let replacement = NSMutableAttributedString(attributedString: source)

      // Build away from live TextKit storage so attachment conversion emits one layout update.
      for (index, line) in lines.enumerated().reversed() {
        let localRange = NSRange(
          location: line.range.location - fullRange.location,
          length: line.range.length
        )
        let currentTypeRaw =
          localRange.length > 0
          ? source.attribute(
            .markdownListType, at: localRange.location, effectiveRange: nil
          ) as? String : nil
        let currentType = currentTypeRaw.flatMap { MarkdownListType(rawValue: $0) }
        let indentLevel: Int =
          localRange.length > 0
          ? source.attribute(
            .markdownIndentLevel, at: localRange.location, effectiveRange: nil
          ) as? Int ?? 0 : 0

        if removesTargetType {
          let markerLength = displayMarkerUTF16Length(in: line.text, listType: targetType)
          let contentLocation = localRange.location + markerLength
          let contentLength = max(0, localRange.length - markerLength)
          let content: NSMutableAttributedString =
            contentLength > 0
            ? NSMutableAttributedString(
              attributedString: source.attributedSubstring(
                from: NSRange(location: contentLocation, length: contentLength)))
            : NSMutableAttributedString()
          let bodyRange = NSRange(location: 0, length: content.length)

          let newParagraphStyle: NSParagraphStyle = {
            if indentLevel > 0 {
              return MarkdownEditorFormatter.listParagraphStyle(
                for: appearanceSettings, indentLevel: indentLevel)
            } else {
              return MarkdownEditorFormatter.bodyParagraphStyle(for: appearanceSettings)
            }
          }()
          content.addAttribute(
            .paragraphStyle,
            value: newParagraphStyle,
            range: bodyRange)
          content.removeAttribute(.markdownListType, range: bodyRange)
          if indentLevel > 0 {
            content.addAttribute(.markdownIndentLevel, value: indentLevel, range: bodyRange)
          } else {
            content.removeAttribute(.markdownIndentLevel, range: bodyRange)
          }

          content.removeAttribute(.strikethroughStyle, range: bodyRange)
          replacement.replaceCharacters(in: localRange, with: content)
        } else {
          let existingMarkerLength =
            currentType.map { displayMarkerUTF16Length(in: line.text, listType: $0) } ?? 0
          let contentLocation = localRange.location + existingMarkerLength
          let contentLength = max(0, localRange.length - existingMarkerLength)
          let existingContent = NSMutableAttributedString(
            attributedString: contentLength > 0
              ? source.attributedSubstring(
                from: NSRange(location: contentLocation, length: contentLength))
              : NSAttributedString()
          )
          if currentType == .checkboxChecked {
            existingContent.removeAttribute(
              .strikethroughStyle,
              range: NSRange(location: 0, length: existingContent.length)
            )
          }

          let listStyle = MarkdownEditorFormatter.listParagraphStyle(
            for: appearanceSettings, indentLevel: indentLevel)

          let result: NSMutableAttributedString

          if targetType == .checkboxUnchecked || targetType == .checkboxChecked {
            let checked = targetType == .checkboxChecked
            result = NSMutableAttributedString()
            let checkbox =
              listMarkerColor.map {
                NSAttributedString(
                  attachment: MarkdownEditorFormatter.checkboxAttachment(
                    checked: checked,
                    color: $0
                  ))
              }
              ?? MarkdownEditorFormatter.checkboxAttributedString(
                checked: checked,
                appearance: appearanceSettings
              )
            result.append(checkbox)
            result.append(
              NSAttributedString(
                string: " ",
                attributes: [
                  .font: appearanceSettings.bodyFont,
                  .foregroundColor: NSColor.labelColor,
                ]))
            result.append(existingContent)
            result.addAttributes(
              [
                .markdownListType: targetType.rawValue,
                .paragraphStyle: listStyle,
                .markdownIndentLevel: indentLevel,
              ],
              range: NSRange(location: 0, length: result.length)
            )
          } else {
            let marker: String
            switch targetType {
            case .bullet: marker = "\(MarkdownEditorFormatter.bulletMarker) "
            case .numbered: marker = "\(index + 1). "
            default: marker = ""
            }

            result = NSMutableAttributedString(
              string: marker,
              attributes: [
                .font: appearanceSettings.bodyFont,
                .foregroundColor: NSColor.labelColor,
                .markdownListType: targetType.rawValue,
                .paragraphStyle: listStyle,
                .markdownIndentLevel: indentLevel,
              ])
            styleListMarker(in: result, listType: targetType)
            result.append(existingContent)
            let contentPartRange = NSRange(
              location: marker.utf16.count, length: existingContent.length)
            if contentPartRange.length > 0 {
              result.addAttributes(
                [
                  .markdownListType: targetType.rawValue,
                  .paragraphStyle: listStyle,
                  .markdownIndentLevel: indentLevel,
                ],
                range: contentPartRange)
            }
          }

          replacement.replaceCharacters(in: localRange, with: result)
        }
      }

      textStorage.replaceCharacters(in: fullRange, with: replacement)
      return NSRange(location: fullRange.location, length: replacement.length)
    }
  }

  // MARK: - Helpers

  // Returns the range of the line containing the cursor.
  private func currentLineRange() -> (NSRange, String) {
    guard let textView else { return (NSRange(location: 0, length: 0), "") }
    let selectionRange = resolvedSelectionRange(requireSelectedText: false)
    let nsString = textView.string as NSString
    let fullRange = nsString.lineRange(
      for: selectionRange ?? textView.selectedRange()
    )
    var textRange = fullRange
    if textRange.length > 0
      && nsString.character(at: textRange.location + textRange.length - 1) == 0x0A
    {
      textRange.length -= 1
    }
    return (textRange, nsString.substring(with: textRange))
  }

  // Restores the active editor selection before toolbar actions mutate the text view.
  private func preparedEditorContext(
    requireSelectedText: Bool
  ) -> (textView: NSTextView, textStorage: NSTextStorage, range: NSRange)? {
    guard
      let textView,
      let textStorage = textView.textStorage,
      let range = resolvedSelectionRange(requireSelectedText: requireSelectedText)
    else { return nil }

    return (textView, textStorage, range)
  }

  // Resolves the selection range the toolbar should operate on, restoring the previous selection
  // if clicking the toolbar caused the text view to resign first responder.
  private func resolvedSelectionRange(requireSelectedText: Bool) -> NSRange? {
    guard let textView else { return nil }

    if textView.window?.firstResponder !== textView {
      textView.window?.makeFirstResponder(textView)
    }

    var selectionRange = textView.selectedRange()
    let shouldRestoreStoredSelection =
      (requireSelectedText && selectionRange.length == 0 && lastKnownSelectionRange.length > 0)
      || selectionRange.location == NSNotFound

    if shouldRestoreStoredSelection, lastKnownSelectionRange.location != NSNotFound {
      textView.setSelectedRange(lastKnownSelectionRange)
      selectionRange = textView.selectedRange()
    }

    lastKnownSelectionRange = selectionRange
    guard !requireSelectedText || selectionRange.length > 0 else { return nil }
    return selectionRange
  }

  // Computes the selection rect in scroll view coordinates.
  private func currentSelectionRect(in textView: NSTextView, scrollView: NSScrollView) -> NSRect? {
    let range = textView.selectedRange()
    guard let selectionRect = textView.editorRectInViewCoordinates(forCharacterRange: range)
    else { return nil }
    return textView.convert(selectionRect, to: scrollView)
  }

  // Strips list/heading attributes and resets to body paragraph style.
  private func applyParagraphAttributes(in textStorage: NSTextStorage, range: NSRange) {
    textStorage.removeAttribute(.markdownHeadingLevel, range: range)
    textStorage.removeAttribute(.markdownHeadingColor, range: range)
    textStorage.removeAttribute(.markdownBlockquote, range: range)
    textStorage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
    textStorage.addAttribute(.font, value: appearanceSettings.bodyFont, range: range)
    textStorage.addAttribute(
      .paragraphStyle, value: MarkdownEditorFormatter.bodyParagraphStyle(for: appearanceSettings),
      range: range)
  }

  // Returns the UTF-16 length of the visible list marker/prefix for a given line and list type.
  // This mirrors how markers are constructed elsewhere:
  // - Bullet: "• " (bullet marker + space) => length 2
  // - Numbered: "<digits>. " (one or more digits, a dot, and a space)
  // - Checkbox: attachment character (U+FFFC) + space => length 2
  private func displayMarkerUTF16Length(in text: String, listType: MarkdownListType) -> Int {
    switch listType {
    case .bullet:
      let marker = "\(MarkdownEditorFormatter.bulletMarker) "
      return text.hasPrefix(marker) ? marker.utf16.count : 0

    case .checkboxUnchecked, .checkboxChecked:
      // Attachment character (U+FFFC) + space
      let marker = "\(MarkdownEditorFormatter.attachmentChar) "
      return text.hasPrefix(marker) ? marker.utf16.count : 0

    case .numbered:
      // Match one or more digits, a dot, and a following space at the start of the line
      if let range = text.range(of: "^\\d+\\.\\s+", options: .regularExpression) {
        let prefix = String(text[range])
        return prefix.utf16.count
      }
      return 0
    }
  }

  // Applies the correct color and font to a list marker character.
  private func styleListMarker(in attrStr: NSMutableAttributedString, listType: MarkdownListType) {
    guard attrStr.length > 0 else { return }
    switch listType {
    case .bullet:
      attrStr.addAttributes(
        [
          .foregroundColor: listMarkerColor
            ?? MarkdownEditorFormatter.bulletColor(for: appearanceSettings),
          .font: NSFont.systemFont(ofSize: appearanceSettings.bulletSize, weight: .bold),
        ], range: NSRange(location: 0, length: 1))
    case .checkboxUnchecked:
      attrStr.addAttributes(
        [
          .foregroundColor: MarkdownEditorFormatter.checkboxUncheckedColor(for: appearanceSettings),
          .font: appearanceSettings.bodyFont,
        ], range: NSRange(location: 0, length: 1))
    case .checkboxChecked:
      attrStr.addAttributes(
        [
          .foregroundColor: MarkdownEditorFormatter.checkboxCheckedColor(for: appearanceSettings),
          .font: appearanceSettings.bodyFont,
        ], range: NSRange(location: 0, length: 1))
    case .numbered:
      let text = attrStr.string
      if let numMatch = text.range(of: #"^\d+\."#, options: .regularExpression) {
        let len = text.distance(from: numMatch.lowerBound, to: numMatch.upperBound)
        attrStr.addAttribute(
          .foregroundColor, value: NSColor.secondaryLabelColor,
          range: NSRange(location: 0, length: len))
      }
    }
  }

}
