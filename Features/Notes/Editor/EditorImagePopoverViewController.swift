//
//  EditorImagePopoverViewController.swift
//

// Small image editing popover for caption and width controls.

import AppKit

@MainActor
final class EditorImagePopoverViewController: NSViewController {
  private let titleField = NSTextField(string: "")
  private let widthLabel = NSTextField(labelWithString: "")
  private let onApply: (String, CGFloat?) -> Void
  private var width: CGFloat
  private let initialExplicitWidth: CGFloat?
  private var didChangeWidth = false

  init(title: String, explicitWidth: CGFloat?, onApply: @escaping (String, CGFloat?) -> Void) {
    self.width = MarkdownEditorFormatter.clampedImageWidth(
      explicitWidth ?? MarkdownEditorFormatter.imageDefaultWidth)
    self.initialExplicitWidth = explicitWidth
    self.onApply = onApply
    super.init(nibName: nil, bundle: nil)
    titleField.stringValue = title
  }

  required init?(coder: NSCoder) {
    nil
  }

  override func loadView() {
    let container = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 126))

    let titleLabel = NSTextField(labelWithString: "Title")
    titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
    titleLabel.textColor = .secondaryLabelColor
    titleLabel.frame = NSRect(x: 16, y: 92, width: 80, height: 18)
    container.addSubview(titleLabel)

    titleField.frame = NSRect(x: 16, y: 66, width: 248, height: 24)
    titleField.bezelStyle = .roundedBezel
    titleField.target = self
    titleField.action = #selector(applyAction)
    container.addSubview(titleField)

    let smallerButton = NSButton(
      title: "Smaller",
      target: self,
      action: #selector(makeSmaller)
    )
    smallerButton.frame = NSRect(x: 16, y: 28, width: 76, height: 28)
    container.addSubview(smallerButton)

    let largerButton = NSButton(
      title: "Bigger",
      target: self,
      action: #selector(makeBigger)
    )
    largerButton.frame = NSRect(x: 100, y: 28, width: 70, height: 28)
    container.addSubview(largerButton)

    widthLabel.alignment = .center
    widthLabel.frame = NSRect(x: 176, y: 32, width: 72, height: 18)
    container.addSubview(widthLabel)

    let updateButton = NSButton(
      title: "Update",
      target: self,
      action: #selector(applyAction)
    )
    updateButton.keyEquivalent = "\r"
    updateButton.frame = NSRect(x: 188, y: 4, width: 76, height: 28)
    container.addSubview(updateButton)

    view = container
    refreshWidthLabel()
  }

  @objc private func makeSmaller() {
    width = MarkdownEditorFormatter.clampedImageWidth(
      width - MarkdownEditorFormatter.imageResizeStep)
    didChangeWidth = true
    refreshWidthLabel()
  }

  @objc private func makeBigger() {
    width = MarkdownEditorFormatter.clampedImageWidth(
      width + MarkdownEditorFormatter.imageResizeStep)
    didChangeWidth = true
    refreshWidthLabel()
  }

  @objc private func applyAction() {
    let title = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let explicitWidth = didChangeWidth || initialExplicitWidth != nil ? width : nil
    onApply(title, explicitWidth)
    view.window?.performClose(nil)
  }

  private func refreshWidthLabel() {
    widthLabel.stringValue = "\(Int(width.rounded())) px"
  }
}
