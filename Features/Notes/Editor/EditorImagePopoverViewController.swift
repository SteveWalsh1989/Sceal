//
//  EditorImagePopoverViewController.swift
//

// Small image editing popover for caption and width controls.

import AppKit

@MainActor
final class EditorImagePopoverViewController: NSViewController, NSTextFieldDelegate {
  private let titleField = NSTextField(string: "")
  private let widthLabel = NSTextField(labelWithString: "")
  private let widthSlider = NSSlider()
  private let onChange: (String, CGFloat?) -> Void
  private let onRemove: () -> Void
  private var width: CGFloat
  private var hasExplicitWidth: Bool
  private var lastAppliedTitle: String
  private var lastAppliedWidth: CGFloat?

  init(
    title: String,
    explicitWidth: CGFloat?,
    onChange: @escaping (String, CGFloat?) -> Void,
    onRemove: @escaping () -> Void
  ) {
    self.width = MarkdownEditorFormatter.clampedImageWidth(
      explicitWidth ?? MarkdownEditorFormatter.imageDefaultWidth)
    self.hasExplicitWidth = explicitWidth != nil
    self.lastAppliedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    self.lastAppliedWidth = explicitWidth.flatMap { width in
      let resolvedWidth = MarkdownEditorFormatter.clampedImageWidth(width)
      if Int(resolvedWidth.rounded()) == Int(MarkdownEditorFormatter.imageDefaultWidth.rounded()) {
        return nil
      }
      return resolvedWidth
    }
    self.onChange = onChange
    self.onRemove = onRemove
    super.init(nibName: nil, bundle: nil)
    titleField.stringValue = title
  }

  required init?(coder: NSCoder) {
    nil
  }

  override func loadView() {
    let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 144))

    let titleLabel = NSTextField(labelWithString: "Title")
    titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
    titleLabel.textColor = .secondaryLabelColor
    titleLabel.frame = NSRect(x: 16, y: 116, width: 80, height: 18)
    container.addSubview(titleLabel)

    titleField.frame = NSRect(x: 16, y: 90, width: 268, height: 24)
    titleField.bezelStyle = .roundedBezel
    titleField.target = self
    titleField.action = #selector(commitTitleAction)
    titleField.delegate = self
    container.addSubview(titleField)

    let sizeLabel = NSTextField(labelWithString: "Size")
    sizeLabel.font = .systemFont(ofSize: 11, weight: .semibold)
    sizeLabel.textColor = .secondaryLabelColor
    sizeLabel.frame = NSRect(x: 16, y: 64, width: 80, height: 18)
    container.addSubview(sizeLabel)

    widthLabel.alignment = .right
    widthLabel.frame = NSRect(x: 216, y: 64, width: 68, height: 18)
    container.addSubview(widthLabel)

    let smallerButton = symbolButton(
      systemName: "minus",
      accessibilityDescription: "Make image smaller",
      action: #selector(makeSmaller)
    )
    smallerButton.frame = NSRect(x: 16, y: 32, width: 28, height: 26)
    container.addSubview(smallerButton)

    widthSlider.minValue = Double(MarkdownEditorFormatter.imageMinimumWidth)
    widthSlider.maxValue = Double(MarkdownEditorFormatter.imageMaximumWidth)
    widthSlider.doubleValue = Double(width)
    widthSlider.isContinuous = true
    widthSlider.target = self
    widthSlider.action = #selector(sliderChanged(_:))
    widthSlider.frame = NSRect(x: 52, y: 33, width: 174, height: 24)
    container.addSubview(widthSlider)

    let largerButton = symbolButton(
      systemName: "plus",
      accessibilityDescription: "Make image larger",
      action: #selector(makeBigger)
    )
    largerButton.frame = NSRect(x: 234, y: 32, width: 28, height: 26)
    container.addSubview(largerButton)

    let removeButton = NSButton(
      title: "Remove",
      target: self,
      action: #selector(removeAction)
    )
    removeButton.bezelStyle = .rounded
    removeButton.contentTintColor = .systemRed
    removeButton.frame = NSRect(x: 16, y: 4, width: 84, height: 24)
    container.addSubview(removeButton)

    view = container
    refreshWidthLabel()
  }

  func controlTextDidChange(_: Notification) {
    applyCurrentChange()
  }

  func controlTextDidEndEditing(_: Notification) {
    applyCurrentChange()
  }

  @objc private func makeSmaller() {
    setWidth(width - MarkdownEditorFormatter.imageResizeStep)
  }

  @objc private func makeBigger() {
    setWidth(width + MarkdownEditorFormatter.imageResizeStep)
  }

  @objc private func sliderChanged(_ sender: NSSlider) {
    setWidth(CGFloat(sender.doubleValue))
  }

  @objc private func commitTitleAction() {
    applyCurrentChange()
    view.window?.makeFirstResponder(nil)
  }

  @objc private func removeAction() {
    onRemove()
    view.window?.performClose(nil)
  }

  private func setWidth(_ newWidth: CGFloat) {
    width = roundedSliderWidth(MarkdownEditorFormatter.clampedImageWidth(newWidth))
    hasExplicitWidth = true
    widthSlider.doubleValue = Double(width)
    refreshWidthLabel()
    applyCurrentChange()
  }

  private func applyCurrentChange() {
    let title = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let width = explicitWidth()
    guard title != lastAppliedTitle || width != lastAppliedWidth else { return }

    lastAppliedTitle = title
    lastAppliedWidth = width
    onChange(title, width)
  }

  private func explicitWidth() -> CGFloat? {
    guard hasExplicitWidth else { return nil }
    let resolvedWidth = MarkdownEditorFormatter.clampedImageWidth(width)
    if Int(resolvedWidth.rounded()) == Int(MarkdownEditorFormatter.imageDefaultWidth.rounded()) {
      return nil
    }
    return resolvedWidth
  }

  private func refreshWidthLabel() {
    widthLabel.stringValue = "\(Int(width.rounded())) px"
  }

  private func roundedSliderWidth(_ width: CGFloat) -> CGFloat {
    (width / 10).rounded() * 10
  }

  private func symbolButton(
    systemName: String,
    accessibilityDescription: String,
    action: Selector
  ) -> NSButton {
    let button = NSButton()
    let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
    button.image = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)?
      .withSymbolConfiguration(config)
    button.imagePosition = .imageOnly
    button.bezelStyle = .rounded
    button.target = self
    button.action = action
    button.toolTip = accessibilityDescription
    button.setAccessibilityLabel(accessibilityDescription)
    return button
  }
}
