//
//  FormattingToolbar.swift
//  dayra
//
//

import AppKit

class FormattingToolbar: NSView {
  weak var textView: NSTextView?

  private let stackView = NSStackView()

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
    addSymbolButton(
      "chevron.left.forwardslash.chevron.right", action: #selector(toggleCode), tooltip: "Code")
    addSeparator()
    addTextButton("H1", action: #selector(applyH1), tooltip: "Heading 1", size: 11)
    addTextButton("H2", action: #selector(applyH2), tooltip: "Heading 2", size: 11)
    addTextButton("H3", action: #selector(applyH3), tooltip: "Heading 3", size: 11)
    addSeparator()
    addSymbolButton("list.bullet", action: #selector(toggleBullet), tooltip: "Bullet List")
    addSymbolButton("list.number", action: #selector(toggleNumbered), tooltip: "Numbered List")
    addSymbolButton("checklist", action: #selector(toggleCheckbox), tooltip: "Checkbox")
    addSeparator()
    for preset in MarkdownStyler.headingColorPresets {
      addColorSwatch(color: preset.color, name: preset.name)
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

  private func addSeparator() {
    let sep = NSView()
    sep.wantsLayer = true
    sep.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor
    sep.translatesAutoresizingMaskIntoConstraints = false
    sep.widthAnchor.constraint(equalToConstant: 1).isActive = true
    sep.heightAnchor.constraint(equalToConstant: 16).isActive = true
    stackView.addArrangedSubview(sep)
  }

  private func addColorSwatch(color: NSColor, name: String) {
    let button = NSButton()
    button.isBordered = false
    button.bezelStyle = .inline
    button.title = ""
    button.wantsLayer = true
    button.layer?.cornerRadius = 6
    button.layer?.backgroundColor = color.cgColor
    button.target = self
    button.action = #selector(applyHeadingColor(_:))
    button.toolTip = "Heading color: \(name)"
    button.tag = MarkdownStyler.headingColorPresets.firstIndex(where: { $0.name == name }) ?? 0
    button.widthAnchor.constraint(equalToConstant: 18).isActive = true
    button.heightAnchor.constraint(equalToConstant: 18).isActive = true
    stackView.addArrangedSubview(button)
  }

  // MARK: - Positioning

  func show(relativeTo selectionRect: NSRect, in parentView: NSView) {
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

    textStorage.beginEditing()
    if allBold {
      textStorage.removeAttribute(.markdownBold, range: range)
      let defaultFont = NSFont.systemFont(ofSize: 15)
      textStorage.addAttribute(.font, value: defaultFont, range: range)
    } else {
      let currentFont =
        textStorage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
        ?? NSFont.systemFont(ofSize: 15)
      let boldFont = NSFontManager.shared.convert(currentFont, toHaveTrait: .boldFontMask)
      textStorage.addAttribute(.font, value: boldFont, range: range)
      textStorage.addAttribute(.markdownBold, value: true, range: range)
    }
    textStorage.endEditing()
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

    textStorage.beginEditing()
    if allCode {
      textStorage.removeAttribute(.markdownInlineCode, range: range)
      textStorage.removeAttribute(.backgroundColor, range: range)
      textStorage.addAttribute(.font, value: NSFont.systemFont(ofSize: 15), range: range)
    } else {
      textStorage.addAttributes(
        [
          .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
          .backgroundColor: NSColor.quaternaryLabelColor,
          .markdownInlineCode: true,
        ], range: range)
    }
    textStorage.endEditing()
  }

  // MARK: - Heading Color Action

  @objc private func applyHeadingColor(_ sender: NSButton) {
    guard let textView, let textStorage = textView.textStorage else { return }
    let presetIndex = sender.tag
    guard presetIndex < MarkdownStyler.headingColorPresets.count else { return }
    let preset = MarkdownStyler.headingColorPresets[presetIndex]

    let (lineRange, _) = currentLineRange()
    guard lineRange.length > 0 else { return }

    let attrs = textStorage.attributes(at: lineRange.location, effectiveRange: nil)
    guard attrs[.markdownHeadingLevel] != nil else { return }

    textStorage.beginEditing()
    textStorage.addAttribute(.foregroundColor, value: preset.color, range: lineRange)
    textStorage.addAttribute(.markdownHeadingColor, value: preset.name, range: lineRange)
    textStorage.endEditing()
  }

  // MARK: - Line-Level Actions

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

    textStorage.beginEditing()
    if currentLevel == level {
      // Toggle off
      textStorage.removeAttribute(.markdownHeadingLevel, range: lineRange)
      textStorage.addAttribute(
        .font, value: NSFont.systemFont(ofSize: 15), range: lineRange)
    } else {
      let fontSize: CGFloat = level == 1 ? 22 : level == 2 ? 19 : 17
      textStorage.addAttribute(.markdownHeadingLevel, value: level, range: lineRange)
      textStorage.addAttribute(
        .font, value: NSFont.systemFont(ofSize: fontSize, weight: .bold), range: lineRange)
      textStorage.removeAttribute(.markdownListType, range: lineRange)
      textStorage.addAttribute(
        .paragraphStyle, value: NSParagraphStyle.default, range: lineRange)
    }
    textStorage.endEditing()
  }

  @objc private func toggleBullet() { toggleListType(.bullet) }
  @objc private func toggleNumbered() { toggleListType(.numbered) }
  @objc private func toggleCheckbox() { toggleListType(.checkboxUnchecked) }

  private func toggleListType(_ targetType: MarkdownListType) {
    guard let textView, let textStorage = textView.textStorage else { return }
    let (lineRange, lineText) = currentLineRange()

    let currentTypeRaw =
      lineRange.length > 0
      ? textStorage.attribute(.markdownListType, at: lineRange.location, effectiveRange: nil)
        as? String : nil
    let currentType = currentTypeRaw.flatMap { MarkdownListType(rawValue: $0) }

    textStorage.beginEditing()

    if currentType == targetType {
      // Toggle off — remove list prefix and attributes
      let cleanText = stripDisplayListPrefix(lineText, listType: targetType)
      let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 15),
        .foregroundColor: NSColor.labelColor,
        .paragraphStyle: NSParagraphStyle.default,
      ]
      textStorage.replaceCharacters(
        in: lineRange,
        with: NSAttributedString(string: cleanText, attributes: attrs))
    } else {
      // Apply — strip any existing list prefix, then add the new one
      let cleanText =
        currentType != nil ? stripDisplayListPrefix(lineText, listType: currentType!) : lineText
      let listStyle = listParagraphStyle()

      let result: NSMutableAttributedString

      if targetType == .checkboxUnchecked || targetType == .checkboxChecked {
        let checked = targetType == .checkboxChecked
        result = NSMutableAttributedString()
        result.append(MarkdownStyler.checkboxAttributedString(checked: checked))
        result.append(
          NSAttributedString(
            string: " \(cleanText)",
            attributes: [
              .font: NSFont.systemFont(ofSize: 15),
              .foregroundColor: NSColor.labelColor,
            ]))
        let fullRange = NSRange(location: 0, length: result.length)
        result.addAttributes(
          [
            .markdownListType: targetType.rawValue,
            .paragraphStyle: listStyle,
          ], range: fullRange)
      } else {
        let marker: String
        switch targetType {
        case .bullet: marker = "\(MarkdownStyler.bulletMarker) "
        case .numbered: marker = "1. "
        default: marker = ""
        }

        let newText = marker + cleanText
        result = NSMutableAttributedString(
          string: newText,
          attributes: [
            .font: NSFont.systemFont(ofSize: 15),
            .foregroundColor: NSColor.labelColor,
            .markdownListType: targetType.rawValue,
            .paragraphStyle: listStyle,
          ])

        styleListMarker(in: result, listType: targetType)
      }

      textStorage.replaceCharacters(in: lineRange, with: result)
    }

    textStorage.endEditing()
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
          .foregroundColor: MarkdownStyler.bulletColor,
          .font: NSFont.systemFont(ofSize: 11, weight: .bold),
        ], range: NSRange(location: 0, length: 1))
    case .checkboxUnchecked:
      attrStr.addAttributes(
        [
          .foregroundColor: MarkdownStyler.checkboxUncheckedColor,
          .font: NSFont.systemFont(ofSize: 15, weight: .medium),
        ], range: NSRange(location: 0, length: 1))
    case .checkboxChecked:
      attrStr.addAttributes(
        [
          .foregroundColor: MarkdownStyler.checkboxCheckedColor,
          .font: NSFont.systemFont(ofSize: 15, weight: .medium),
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

  private func listParagraphStyle() -> NSMutableParagraphStyle {
    let style = NSMutableParagraphStyle()
    style.firstLineHeadIndent = 8
    style.headIndent = 28
    style.paragraphSpacing = 2
    return style
  }
}
