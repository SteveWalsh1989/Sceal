//
//  FormattingToolbar.swift
//
//

import AppKit

@MainActor class FormattingToolbar: NSView {
  weak var textView: NSTextView?
  var appearanceSettings = NoteAppearanceSettings.default

  private let stackView = NSStackView()
  private var colorSeparator: NSView?
  private var colorSwatches: [NSView] = []

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setup()
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  // MARK: - Setup

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
    for (index, entry) in ScealPalette.colors.enumerated() {
      let swatch = addColorSwatch(color: entry.color, name: entry.name, index: index)
      colorSwatches.append(swatch)
    }
  }

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

  func show(relativeTo selectionRect: NSRect, in parentView: NSView) {
    updateColorSwatchVisibility()
    // Force layout after visibility changes so fittingSize reflects the current state
    // and the autoresizing mask constraint doesn't conflict with the stack view.
    stackView.layoutSubtreeIfNeeded()
    let size = fittingSize
    let toolbarHeight = max(size.height, 34)
    let toolbarWidth = max(size.width, 100)
    let gap: CGFloat = 10

    // In flipped coordinates: minY is top, maxY is bottom.
    // Place toolbar above the selection.
    var origin = NSPoint(
      x: selectionRect.midX - toolbarWidth / 2,
      y: selectionRect.minY - toolbarHeight - gap
    )

    // Keep within parent bounds
    let parentBounds = parentView.bounds
    origin.x = max(4, min(origin.x, parentBounds.maxX - toolbarWidth - 4))
    // If toolbar would go above the visible area, flip to below
    if origin.y < 4 {
      origin.y = selectionRect.maxY + gap
    }

    frame = NSRect(x: origin.x, y: origin.y, width: toolbarWidth, height: toolbarHeight)

    if superview == nil {
      parentView.addSubview(self)
    }

    isHidden = false
    alphaValue = 1
  }

  func hide() {
    isHidden = true
  }

  // MARK: - Inline Actions

  @objc private func toggleBold() {
    guard let textView, let textStorage = textView.textStorage else { return }
    let range = textView.selectedRange()
    guard range.length > 0 else { return }

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
        textStorage.addAttribute(.font, value: appearanceSettings.bodyFont, range: range)
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
    guard let textView, let textStorage = textView.textStorage else { return }
    let range = textView.selectedRange()
    guard range.length > 0 else { return }

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
    guard let textView, let textStorage = textView.textStorage else { return }
    let range = textView.selectedRange()
    guard range.length > 0 else { return }

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

  @objc private func toggleCode() {
    guard let textView, let textStorage = textView.textStorage else { return }
    let range = textView.selectedRange()
    guard range.length > 0 else { return }

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
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
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

  @objc private func applyHeadingColor(_ sender: NSButton) {
    guard let textView, let textStorage = textView.textStorage else { return }
    let presetIndex = sender.tag
    guard presetIndex < ScealPalette.colors.count else { return }
    let preset = ScealPalette.colors[presetIndex]

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
        let fontSize = MarkdownStyler.headingFontSize(for: level)
        textStorage.addAttribute(.markdownHeadingLevel, value: level, range: lineRange)
        textStorage.addAttribute(
          .font, value: appearanceSettings.boldBodyFont(ofSize: fontSize), range: lineRange)
        textStorage.removeAttribute(.markdownBlockquote, range: lineRange)
        textStorage.removeAttribute(.markdownListType, range: lineRange)
        textStorage.addAttribute(
          .paragraphStyle, value: MarkdownStyler.bodyParagraphStyle(for: appearanceSettings),
          range: lineRange)
      }
      return nil
    }
    refreshToolbarPresentation()
  }

  @objc private func toggleBullet() { toggleListType(.bullet) }
  @objc private func toggleNumbered() { toggleListType(.numbered) }
  @objc private func toggleCheckbox() { toggleListType(.checkboxUnchecked) }

  // MARK: - Link Popover

  // Opens a popover to create or edit a markdown link on the selected text
  @objc private func showLinkPopover(_ sender: NSButton) {
    guard let textView, let textStorage = textView.textStorage else { return }
    let range = textView.selectedRange()
    guard range.length > 0 else { return }

    let selectedText = (textStorage.string as NSString).substring(with: range)
    let existingURL =
      textStorage.attribute(.markdownLinkURL, at: range.location, effectiveRange: nil) as? String

    let popover = NSPopover()
    popover.behavior = .transient
    popover.contentSize = NSSize(width: 280, height: 120)

    let controller = LinkPopoverViewController(
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
    guard lineRange.length >= 0 else { return }

    let isBlockquote =
      lineRange.length > 0
      ? textStorage.attribute(.markdownBlockquote, at: lineRange.location, effectiveRange: nil)
        as? Bool == true
      : false

    _ = textView.performEditorEdit(affectedRange: lineRange, actionName: "Blockquote") {
      textStorage in
      if isBlockquote {
        // Toggle off — remove blockquote styling, restore default attributes
        let attrs: [NSAttributedString.Key: Any] = [
          .font: appearanceSettings.bodyFont,
          .foregroundColor: NSColor.labelColor,
          .paragraphStyle: MarkdownStyler.bodyParagraphStyle(for: appearanceSettings),
        ]
        textStorage.replaceCharacters(
          in: lineRange,
          with: NSAttributedString(string: lineText, attributes: attrs))
      } else {
        // Apply blockquote — strip any existing list prefix first
        let currentTypeRaw =
          lineRange.length > 0
          ? textStorage.attribute(.markdownListType, at: lineRange.location, effectiveRange: nil)
            as? String
          : nil
        let cleanText: String
        if let rawType = currentTypeRaw, let listType = MarkdownListType(rawValue: rawType) {
          cleanText = stripDisplayListPrefix(lineText, listType: listType)
        } else {
          cleanText = lineText
        }

        let quoteStyle = MarkdownStyler.blockquoteParagraphStyle(for: appearanceSettings)
        let result = NSAttributedString(
          string: cleanText,
          attributes: [
            .font: appearanceSettings.bodyFont,
            .foregroundColor: NSColor.secondaryLabelColor,
            .markdownBlockquote: true,
            .paragraphStyle: quoteStyle,
          ])
        textStorage.replaceCharacters(in: lineRange, with: result)
      }
      return nil
    }
  }

  private func toggleListType(_ targetType: MarkdownListType) {
    guard let textView, let textStorage = textView.textStorage else { return }
    let nsString = textStorage.string as NSString

    // Collect individual line ranges covering the entire selection
    let selectedRange = textView.selectedRange()
    let fullRange = nsString.lineRange(for: selectedRange)
    var lines: [(range: NSRange, text: String)] = []
    var scanStart = fullRange.location
    while scanStart < NSMaxRange(fullRange) {
      var lineRange = nsString.lineRange(for: NSRange(location: scanStart, length: 0))
      // Trim trailing newline for the text range
      if lineRange.length > 0
        && nsString.character(at: lineRange.location + lineRange.length - 1) == 0x0A
      {
        lineRange.length -= 1
      }
      let lineText = nsString.substring(with: lineRange)
      lines.append((lineRange, lineText))
      scanStart = lineRange.location + lineRange.length + 1  // +1 to skip past newline
    }

    guard !lines.isEmpty else { return }

    _ = textView.performEditorEdit(affectedRange: fullRange, actionName: "List Style") {
      textStorage in
      // Process lines in reverse so replacements don't shift later ranges
      for (index, line) in lines.enumerated().reversed() {
        let currentTypeRaw =
          line.range.length > 0
          ? textStorage.attribute(
            .markdownListType, at: line.range.location, effectiveRange: nil
          ) as? String : nil
        let currentType = currentTypeRaw.flatMap { MarkdownListType(rawValue: $0) }
        // Preserve indent level when converting between list types
        let indentLevel: Int = line.range.length > 0
          ? textStorage.attribute(
            .markdownIndentLevel, at: line.range.location, effectiveRange: nil
          ) as? Int ?? 0 : 0

        if currentType == targetType {
          // Toggle off — remove list prefix and attributes
          let cleanText = stripDisplayListPrefix(line.text, listType: targetType)
          let attrs: [NSAttributedString.Key: Any] = [
            .font: appearanceSettings.bodyFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: MarkdownStyler.bodyParagraphStyle(for: appearanceSettings),
          ]
          textStorage.replaceCharacters(
            in: line.range,
            with: NSAttributedString(string: cleanText, attributes: attrs))
        } else {
          // Apply — strip any existing list prefix, then add the new one
          let cleanText =
            currentType != nil
            ? stripDisplayListPrefix(line.text, listType: currentType!) : line.text
          let listStyle = MarkdownStyler.listParagraphStyle(
            for: appearanceSettings, indentLevel: indentLevel)

          let result: NSMutableAttributedString

          if targetType == .checkboxUnchecked || targetType == .checkboxChecked {
            let checked = targetType == .checkboxChecked
            result = NSMutableAttributedString()
            result.append(
              MarkdownStyler.checkboxAttributedString(
                checked: checked,
                appearance: appearanceSettings
              ))
            result.append(
              NSAttributedString(
                string: " \(cleanText)",
                attributes: [
                  .font: appearanceSettings.bodyFont,
                  .foregroundColor: NSColor.labelColor,
                  .paragraphStyle: MarkdownStyler.bodyParagraphStyle(for: appearanceSettings),
                ]))
            let fullRange = NSRange(location: 0, length: result.length)
            result.addAttributes(
              [
                .markdownListType: targetType.rawValue,
                .paragraphStyle: listStyle,
                .markdownIndentLevel: indentLevel,
              ],
              range: fullRange
            )
          } else {
            let marker: String
            switch targetType {
            case .bullet: marker = "\(MarkdownStyler.bulletMarker) "
            case .numbered: marker = "\(index + 1). "
            default: marker = ""
            }

            let newText = marker + cleanText
            result = NSMutableAttributedString(
              string: newText,
              attributes: [
                .font: appearanceSettings.bodyFont,
                .foregroundColor: NSColor.labelColor,
                .markdownListType: targetType.rawValue,
                .paragraphStyle: listStyle,
                .markdownIndentLevel: indentLevel,
              ])

            styleListMarker(in: result, listType: targetType)
          }

          textStorage.replaceCharacters(in: line.range, with: result)
        }
      }
      return nil
    }
  }

  // MARK: - Helpers

  private func currentLineRange() -> (NSRange, String) {
    guard let textView else { return (NSRange(location: 0, length: 0), "") }
    let nsString = textView.string as NSString
    let fullRange = nsString.lineRange(for: textView.selectedRange())
    var textRange = fullRange
    if textRange.length > 0
      && nsString.character(at: textRange.location + textRange.length - 1) == 0x0A
    {
      textRange.length -= 1
    }
    return (textRange, nsString.substring(with: textRange))
  }

  private func currentSelectionRect(in textView: NSTextView, scrollView: NSScrollView) -> NSRect? {
    let range = textView.selectedRange()
    guard
      range.length > 0,
      let layoutManager = textView.layoutManager,
      let textContainer = textView.textContainer
    else { return nil }

    let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
    let selectionRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
    return textView.convert(selectionRect, to: scrollView)
  }

  private func applyParagraphAttributes(in textStorage: NSTextStorage, range: NSRange) {
    textStorage.removeAttribute(.markdownHeadingLevel, range: range)
    textStorage.removeAttribute(.markdownHeadingColor, range: range)
    textStorage.removeAttribute(.markdownBlockquote, range: range)
    textStorage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
    textStorage.addAttribute(.font, value: appearanceSettings.bodyFont, range: range)
    textStorage.addAttribute(
      .paragraphStyle, value: MarkdownStyler.bodyParagraphStyle(for: appearanceSettings),
      range: range)
  }

  private func stripDisplayListPrefix(_ text: String, listType: MarkdownListType) -> String {
    switch listType {
    case .bullet:
      if text.hasPrefix("\(MarkdownStyler.bulletMarker) ") { return String(text.dropFirst(2)) }
    case .checkboxUnchecked, .checkboxChecked:
      // Attachment character (U+FFFC) + space
      if text.hasPrefix("\(MarkdownStyler.attachmentChar) ") { return String(text.dropFirst(2)) }
    case .numbered:
      if let match = text.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
        return String(text[match.upperBound...])
      }
    }
    return text
  }

  private func styleListMarker(in attrStr: NSMutableAttributedString, listType: MarkdownListType) {
    guard attrStr.length > 0 else { return }
    switch listType {
    case .bullet:
      attrStr.addAttributes(
        [
          .foregroundColor: MarkdownStyler.bulletColor(for: appearanceSettings),
          .font: NSFont.systemFont(ofSize: appearanceSettings.bulletSize, weight: .bold),
        ], range: NSRange(location: 0, length: 1))
    case .checkboxUnchecked:
      attrStr.addAttributes(
        [
          .foregroundColor: MarkdownStyler.checkboxUncheckedColor(for: appearanceSettings),
          .font: appearanceSettings.bodyFont,
        ], range: NSRange(location: 0, length: 1))
    case .checkboxChecked:
      attrStr.addAttributes(
        [
          .foregroundColor: MarkdownStyler.checkboxCheckedColor(for: appearanceSettings),
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

// MARK: - Link Popover View Controller

// Compact form for creating or editing a markdown link (text + URL).
private class LinkPopoverViewController: NSViewController {

  private let initialText: String
  private let initialURL: String
  private let hasExistingLink: Bool
  private let onApply: (String, String, Bool) -> Void

  private let textField = NSTextField()
  private let urlField = NSTextField()

  init(
    linkText: String, url: String, hasExistingLink: Bool,
    onApply: @escaping (String, String, Bool) -> Void
  ) {
    self.initialText = linkText
    self.initialURL = url
    self.hasExistingLink = hasExistingLink
    self.onApply = onApply
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override func loadView() {
    let container = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 120))

    let textLabel = NSTextField(labelWithString: "Link Text")
    textLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
    textLabel.textColor = .secondaryLabelColor

    textField.stringValue = initialText
    textField.font = NSFont.systemFont(ofSize: 13)
    textField.placeholderString = "Display text"

    let urlLabel = NSTextField(labelWithString: "URL")
    urlLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
    urlLabel.textColor = .secondaryLabelColor

    urlField.stringValue = initialURL
    urlField.font = NSFont.systemFont(ofSize: 13)
    urlField.placeholderString = "https://example.com"

    let updateButton = NSButton(title: "Update", target: self, action: #selector(applyAction))
    updateButton.bezelStyle = .rounded
    updateButton.keyEquivalent = "\r"

    let buttonRow = NSStackView(views: [updateButton])

    if hasExistingLink {
      let removeButton = NSButton(
        title: "Remove Link", target: self, action: #selector(removeAction))
      removeButton.bezelStyle = .rounded
      removeButton.contentTintColor = .systemRed
      buttonRow.insertArrangedSubview(removeButton, at: 0)
    }

    buttonRow.distribution = .fill

    let stack = NSStackView(views: [textLabel, textField, urlLabel, urlField, buttonRow])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 4
    stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
    stack.translatesAutoresizingMaskIntoConstraints = false

    container.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: container.topAnchor),
      stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      textField.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24),
      urlField.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24),
    ])

    self.view = container
  }

  @objc private func applyAction() {
    let text = textField.stringValue.isEmpty ? initialText : textField.stringValue
    onApply(text, urlField.stringValue, false)
  }

  @objc private func removeAction() {
    onApply(initialText, "", true)
  }
}
