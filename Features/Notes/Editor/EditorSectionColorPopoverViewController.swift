//
//  EditorSectionColorPopoverViewController.swift
//

// Popover for picking section heading and bullet colors.

import AppKit

@MainActor final class EditorSectionColorPopoverViewController: NSViewController {

  static func contentSize(useSectionColor: Bool) -> NSSize {
    NSSize(width: 264, height: useSectionColor ? 118 : 208)
  }

  private let onChange: (String?, String?, Bool) -> Void

  private var selectedHeadingColor: String?
  private var selectedBulletColor: String?
  private var useSectionColorToggle: Bool

  init(
    headingColorName: String?,
    bulletColorName: String?,
    useSectionColor: Bool,
    onChange: @escaping (String?, String?, Bool) -> Void
  ) {
    self.onChange = onChange
    self.selectedHeadingColor = headingColorName
    self.selectedBulletColor = bulletColorName
    self.useSectionColorToggle = useSectionColor
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  override func loadView() {
    let contentSize = Self.contentSize(useSectionColor: useSectionColorToggle)
    preferredContentSize = contentSize
    let container = NSView(
      frame: NSRect(origin: .zero, size: contentSize)
    )

    var y = contentSize.height - 20

    // Title
    let title = makeLabel("Section Colors", bold: true)
    title.frame.origin = NSPoint(x: 16, y: y - 18)
    container.addSubview(title)
    y -= 34

    if !useSectionColorToggle {
      let headingLabel = makeLabel("Heading Color")
      headingLabel.frame.origin = NSPoint(x: 16, y: y - 14)
      container.addSubview(headingLabel)
      y -= 28
    }

    let headingSwatches = makeSwatchRow(
      selected: selectedHeadingColor,
      action: #selector(headingSwatchClicked(_:)),
      yOrigin: y - 22
    )
    for swatch in headingSwatches { container.addSubview(swatch) }
    y -= 36

    if !useSectionColorToggle {
      let bulletLabel = makeLabel("Bullet Color")
      bulletLabel.frame.origin = NSPoint(x: 16, y: y - 14)
      container.addSubview(bulletLabel)
      y -= 28

      let bulletSwatches = makeSwatchRow(
        selected: selectedBulletColor,
        action: #selector(bulletSwatchClicked(_:)),
        yOrigin: y - 22
      )
      for swatch in bulletSwatches { container.addSubview(swatch) }
      y -= 36
    }

    let toggle = NSButton(
      checkboxWithTitle: "Use same color for bullets & checkboxes",
      target: self,
      action: #selector(toggleChanged(_:))
    )
    toggle.state = useSectionColorToggle ? .on : .off
    toggle.font = NSFont.systemFont(ofSize: 11)
    toggle.sizeToFit()
    toggle.frame.origin = NSPoint(x: 16, y: y - 18)
    container.addSubview(toggle)

    self.view = container
  }

  private func makeLabel(_ text: String, bold: Bool = false) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font =
      bold
      ? NSFont.systemFont(ofSize: 13, weight: .semibold)
      : NSFont.systemFont(ofSize: 11)
    label.sizeToFit()
    return label
  }

  private func makeSwatchRow(
    selected: String?,
    action: Selector,
    yOrigin: CGFloat
  ) -> [NSView] {
    var views: [NSView] = []
    let swatchSize: CGFloat = 20
    let spacing: CGFloat = 4
    var x: CGFloat = 16

    // "None" button
    let noneBtn = NSButton(frame: NSRect(x: x, y: yOrigin, width: 36, height: swatchSize))
    noneBtn.title = "–"
    noneBtn.bezelStyle = .rounded
    noneBtn.isBordered = selected == nil
    noneBtn.tag = -1
    noneBtn.target = self
    noneBtn.action = action
    noneBtn.toolTip = "None"
    views.append(noneBtn)
    x += 36 + spacing

    for (idx, preset) in ThemePalette.colors.enumerated() {
      let btn = NSButton(frame: NSRect(x: x, y: yOrigin, width: swatchSize, height: swatchSize))
      btn.wantsLayer = true
      btn.layer?.cornerRadius = swatchSize / 2
      btn.layer?.backgroundColor = preset.color.cgColor
      btn.isBordered = false
      btn.title = ""
      btn.tag = idx
      btn.target = self
      btn.action = action
      btn.toolTip = preset.name

      if preset.name == selected {
        btn.layer?.borderWidth = 2
        btn.layer?.borderColor = NSColor.controlAccentColor.cgColor
      }

      views.append(btn)
      x += swatchSize + spacing
    }

    return views
  }

  @objc private func headingSwatchClicked(_ sender: NSButton) {
    selectedHeadingColor = sender.tag == -1 ? nil : ThemePalette.colors[sender.tag].name
    rebuildSwatches()
    notifyChange()
  }

  @objc private func bulletSwatchClicked(_ sender: NSButton) {
    selectedBulletColor = sender.tag == -1 ? nil : ThemePalette.colors[sender.tag].name
    rebuildSwatches()
    notifyChange()
  }

  @objc private func toggleChanged(_ sender: NSButton) {
    useSectionColorToggle = sender.state == .on
    notifyChange()
    rebuildSwatches()
  }

  private func notifyChange() {
    let bulletColor = useSectionColorToggle ? nil : selectedBulletColor
    onChange(selectedHeadingColor, bulletColor, useSectionColorToggle)
  }

  private func rebuildSwatches() {
    // Rebuild view to update selection rings — simple and sufficient for a small popover.
    guard isViewLoaded else { return }
    let origin = view.frame.origin
    loadView()
    view.frame.origin = origin
    view.window?.setContentSize(Self.contentSize(useSectionColor: useSectionColorToggle))
  }
}
