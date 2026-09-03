//
//  EditorSlashCommandPopup.swift
//
//

// Floating popup that shows filtered slash command options as the user types.

import AppKit

// Floating popup that shows available slash commands as the user types `/`.
@MainActor class EditorSlashCommandPopup: NSView {
  var onSelect: ((SlashCommandEntry) -> Void)?

  private let scrollView = NSScrollView()
  private let stackView = SlashCommandStackView()
  private weak var presentationPanel: NSPanel?
  private var filteredCommands: [SlashCommandEntry] = []
  private var selectedIndex = 0
  private var rowViews: [SlashCommandRowView] = []

  var isVisible: Bool {
    presentationPanel?.isVisible == true || (!isHidden && superview != nil)
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setup()
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  // MARK: - Setup

  // Builds the popup's visual shell and shadow.
  private func setup() {
    wantsLayer = true
    layer?.backgroundColor = NSColor(white: 0.15, alpha: 0.95).cgColor
    layer?.cornerRadius = 8

    shadow = NSShadow()
    layer?.shadowColor = NSColor.black.withAlphaComponent(0.3).cgColor
    layer?.shadowOpacity = 1
    layer?.shadowRadius = 8
    layer?.shadowOffset = CGSize(width: 0, height: -2)

    scrollView.drawsBackground = false
    scrollView.borderType = .noBorder
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    addSubview(scrollView)
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: topAnchor),
      scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
      scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
    ])

    stackView.orientation = .vertical
    stackView.spacing = 0
    stackView.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
    scrollView.documentView = stackView
  }

  // MARK: - Public API

  // Filters commands matching the typed prefix and rebuilds rows.
  func updateFilter(_ prefix: String, customTemplates: [NoteTemplate] = []) {
    filteredCommands = EditorSlashCommandHandler.filteredCommands(
      for: prefix,
      customTemplates: customTemplates
    )
    selectedIndex = 0
    rebuildRows()
  }

  // Presents the menu in an AppKit child panel so SwiftUI cannot clip or reorder it.
  func show(relativeTo cursorRect: NSRect, in anchorView: NSView) {
    guard !filteredCommands.isEmpty else {
      hide()
      return
    }
    let popupWidth: CGFloat = 210
    let rowHeight: CGFloat = 36
    let verticalPadding: CGFloat = 8
    let contentHeight = CGFloat(filteredCommands.count) * rowHeight + verticalPadding
    guard let parentWindow = anchorView.window else {
      showInDetachedAnchor(
        anchorView,
        cursorRect: cursorRect,
        width: popupWidth,
        contentHeight: contentHeight,
        minimumHeight: rowHeight + verticalPadding
      )
      return
    }
    let cursorRectInWindow = anchorView.convert(cursorRect, to: nil)
    let cursorRectOnScreen = parentWindow.convertToScreen(cursorRectInWindow)
    let visibleFrame = parentWindow.screen?.visibleFrame ?? parentWindow.frame
    let popupFrame = EditorSlashCommandPopupPlacement.frame(
      relativeTo: cursorRectOnScreen,
      visibleFrame: visibleFrame,
      width: popupWidth,
      contentHeight: contentHeight,
      minimumHeight: rowHeight + verticalPadding
    )

    let panel: NSPanel
    if let presentationPanel {
      panel = presentationPanel
    } else {
      panel = makePresentationPanel()
      presentationPanel = panel
    }
    if panel.parent !== parentWindow {
      panel.parent?.removeChildWindow(panel)
      parentWindow.addChildWindow(panel, ordered: .above)
    }
    frame = NSRect(origin: .zero, size: popupFrame.size)
    stackView.frame = NSRect(x: 0, y: 0, width: popupWidth, height: contentHeight)
    panel.setFrame(popupFrame, display: true)
    isHidden = false
    alphaValue = 1
    panel.orderFront(nil)
  }

  // Dismisses the child panel without disturbing editor focus.
  func hide() {
    isHidden = true
    if let presentationPanel {
      presentationPanel.parent?.removeChildWindow(presentationPanel)
      presentationPanel.orderOut(nil)
    } else {
      removeFromSuperview()
    }
    filteredCommands = []
    selectedIndex = 0
  }

  // Moves the highlight to the previous command.
  func moveSelectionUp() {
    guard !filteredCommands.isEmpty else { return }
    selectedIndex = max(selectedIndex - 1, 0)
    updateHighlight()
  }

  // Moves the highlight to the next command.
  func moveSelectionDown() {
    guard !filteredCommands.isEmpty else { return }
    selectedIndex = min(selectedIndex + 1, filteredCommands.count - 1)
    updateHighlight()
  }

  // Triggers the callback with the currently highlighted command.
  func confirmSelection() {
    selectCommand(at: selectedIndex)
  }

  // Uses the same selection path for mouse clicks and keyboard confirmation.
  func selectCommand(at index: Int) {
    guard filteredCommands.indices.contains(index) else { return }
    onSelect?(filteredCommands[index])
  }

  // MARK: - Row Management

  // Rebuilds the row subviews from the filtered command list.
  private func rebuildRows() {
    for rowView in rowViews {
      rowView.removeFromSuperview()
    }
    rowViews.removeAll()
    for arrangedSubview in stackView.arrangedSubviews {
      arrangedSubview.removeFromSuperview()
    }

    for (index, entry) in filteredCommands.enumerated() {
      let row = SlashCommandRowView(
        entry: entry,
        isSelected: index == selectedIndex,
        onHover: { [weak self] in self?.selectRow(at: index) },
        onSelect: { [weak self] in self?.selectCommand(at: index) }
      )
      row.translatesAutoresizingMaskIntoConstraints = false
      row.heightAnchor.constraint(equalToConstant: 36).isActive = true
      stackView.addArrangedSubview(row)
      rowViews.append(row)
    }
  }

  // Updates the visual highlight to the current selection index.
  private func updateHighlight() {
    for (index, row) in rowViews.enumerated() {
      row.setSelected(index == selectedIndex)
    }
    rowViews[selectedIndex].scrollToVisible(rowViews[selectedIndex].bounds)
  }

  // Updates keyboard selection as the pointer crosses menu rows.
  private func selectRow(at index: Int) {
    guard filteredCommands.indices.contains(index) else { return }
    selectedIndex = index
    updateHighlight()
  }

  // Builds a non-activating child window that leaves the insertion caret active.
  private func makePresentationPanel() -> NSPanel {
    let panel = SlashCommandPanel(
      contentRect: .zero,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.contentView = self
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = true
    panel.hidesOnDeactivate = true
    panel.level = .popUpMenu
    panel.collectionBehavior = [.transient, .fullScreenAuxiliary]
    return panel
  }

  // Keeps command state usable while an editor is being configured before it joins a window.
  private func showInDetachedAnchor(
    _ anchorView: NSView,
    cursorRect: NSRect,
    width: CGFloat,
    contentHeight: CGFloat,
    minimumHeight: CGFloat
  ) {
    let visibleFrame = anchorView.visibleRect.isEmpty ? anchorView.bounds : anchorView.visibleRect
    let popupFrame = EditorSlashCommandPopupPlacement.frame(
      relativeTo: cursorRect,
      visibleFrame: visibleFrame,
      width: min(width, max(visibleFrame.width, 1)),
      contentHeight: contentHeight,
      minimumHeight: min(minimumHeight, max(visibleFrame.height, 1))
    )
    if superview !== anchorView {
      removeFromSuperview()
      anchorView.addSubview(self, positioned: .above, relativeTo: nil)
    }
    frame = popupFrame
    stackView.frame = NSRect(
      origin: .zero, size: NSSize(width: popupFrame.width, height: contentHeight))
    isHidden = false
    alphaValue = 1
  }
}

nonisolated enum EditorSlashCommandPopupPlacement {
  // Keeps the menu on-screen, preferring the space below the caret.
  static func frame(
    relativeTo cursorRect: NSRect,
    visibleFrame: NSRect,
    width: CGFloat,
    contentHeight: CGFloat,
    minimumHeight: CGFloat
  ) -> NSRect {
    let edgeInset: CGFloat = 4
    let gap: CGFloat = 4
    let availableHeight = max(minimumHeight, visibleFrame.height - edgeInset * 2)
    let height = min(contentHeight, availableHeight)
    let minimumX = visibleFrame.minX + edgeInset
    let maximumX = max(minimumX, visibleFrame.maxX - width - edgeInset)
    let belowY = cursorRect.minY - height - gap
    let aboveY = cursorRect.maxY + gap
    let preferredY = belowY >= visibleFrame.minY + edgeInset ? belowY : aboveY
    let minimumY = visibleFrame.minY + edgeInset
    let maximumY = max(minimumY, visibleFrame.maxY - height - edgeInset)

    return NSRect(
      x: min(max(cursorRect.minX, minimumX), maximumX),
      y: min(max(preferredY, minimumY), maximumY),
      width: width,
      height: height
    )
  }
}

private final class SlashCommandPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

// Keeps the command order top-to-bottom while the stack acts as a scroll view document.
private final class SlashCommandStackView: NSStackView {
  override var isFlipped: Bool { true }
}

// MARK: - Row View

private class SlashCommandRowView: NSView {
  private let commandLabel = NSTextField(labelWithString: "")
  private let descLabel = NSTextField(labelWithString: "")
  private let highlightLayer = CALayer()
  private let onHover: () -> Void
  private let onSelect: () -> Void
  private var trackingArea: NSTrackingArea?

  init(
    entry: SlashCommandEntry,
    isSelected: Bool,
    onHover: @escaping () -> Void,
    onSelect: @escaping () -> Void
  ) {
    self.onHover = onHover
    self.onSelect = onSelect
    super.init(frame: .zero)

    wantsLayer = true
    highlightLayer.cornerRadius = 4
    layer?.addSublayer(highlightLayer)

    commandLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
    commandLabel.textColor = .white
    commandLabel.stringValue = entry.command
    commandLabel.isEditable = false
    commandLabel.isBordered = false
    commandLabel.drawsBackground = false

    descLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
    descLabel.textColor = NSColor(white: 0.6, alpha: 1)
    descLabel.stringValue = entry.description
    descLabel.isHidden = entry.description.isEmpty
    descLabel.isEditable = false
    descLabel.isBordered = false
    descLabel.drawsBackground = false

    addSubview(commandLabel)
    addSubview(descLabel)

    commandLabel.translatesAutoresizingMaskIntoConstraints = false
    descLabel.translatesAutoresizingMaskIntoConstraints = false

    NSLayoutConstraint.activate([
      commandLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
      commandLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

      descLabel.leadingAnchor.constraint(equalTo: commandLabel.trailingAnchor, constant: 8),
      descLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
      descLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
    ])

    setSelected(isSelected)
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override func layout() {
    super.layout()
    highlightLayer.frame = bounds.insetBy(dx: 4, dy: 1)
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let trackingArea {
      removeTrackingArea(trackingArea)
    }
    let replacement = NSTrackingArea(
      rect: bounds,
      options: [.activeAlways, .mouseEnteredAndExited],
      owner: self,
      userInfo: nil
    )
    addTrackingArea(replacement)
    trackingArea = replacement
  }

  override func mouseEntered(with _: NSEvent) {
    onHover()
  }

  override func mouseDown(with _: NSEvent) {
    onSelect()
  }

  override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
    true
  }

  func setSelected(_ selected: Bool) {
    highlightLayer.backgroundColor =
      selected
      ? NSColor.white.withAlphaComponent(0.1).cgColor
      : NSColor.clear.cgColor
  }
}
