//
//  EditorLinkPopoverViewController.swift
//

// Popover view controller for creating and editing markdown links.

import AppKit

// Compact form for creating or editing a markdown link (text + URL).
class EditorLinkPopoverViewController: NSViewController {

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
