//
//  SlashCommandPopup.swift
//  dayra
//
//

import AppKit

/// Floating popup that shows available slash commands as the user types `/`.
class SlashCommandPopup: NSView {
  var onSelect: ((SlashCommandEntry) -> Void)?

  private let stackView = NSStackView()
  private var filteredCommands: [SlashCommandEntry] = []
  private var selectedIndex = 0
  private var rowViews: [SlashCommandRowView] = []

  var isVisible: Bool { !isHidden && superview != nil }

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

    stackView.orientation = .vertical
    stackView.spacing = 0
    stackView.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
    addSubview(stackView)
    stackView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      stackView.topAnchor.constraint(equalTo: topAnchor),
      stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
      stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
      stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
    ])
  }

  // MARK: - Public API

  func updateFilter(_ prefix: String) {
    filteredCommands = SlashCommandHandler.filteredCommands(for: prefix)
    selectedIndex = 0
    rebuildRows()
  }

  func show(relativeTo cursorRect: NSRect, in parentView: NSView) {
    guard !filteredCommands.isEmpty else {
      hide()
      return
    }

    let popupWidth: CGFloat = 210
    let rowHeight: CGFloat = 36
    let verticalPadding: CGFloat = 8
    let popupHeight = CGFloat(filteredCommands.count) * rowHeight + verticalPadding
    let gap: CGFloat = 4

    // In flipped coordinates: minY is top, maxY is bottom.
    // Prefer the space above the active line, matching the formatting toolbar.
    var origin = NSPoint(
      x: cursorRect.minX,
      y: cursorRect.minY - popupHeight - gap
    )

    // Keep within parent bounds
    let parentBounds = parentView.bounds
    origin.x = max(4, min(origin.x, parentBounds.maxX - popupWidth - 4))
    // If popup would go above the visible area, flip to below.
    if origin.y < 4 {
      origin.y = cursorRect.maxY + gap
    }

    frame = NSRect(x: origin.x, y: origin.y, width: popupWidth, height: popupHeight)

    if superview == nil {
      parentView.addSubview(self)
    }

    isHidden = false
    alphaValue = 1
  }

  func hide() {
    isHidden = true
    removeFromSuperview()
    filteredCommands = []
    selectedIndex = 0
  }

  func moveSelectionUp() {
    guard !filteredCommands.isEmpty else { return }
    selectedIndex = max(selectedIndex - 1, 0)
    updateHighlight()
  }

  func moveSelectionDown() {
    guard !filteredCommands.isEmpty else { return }
    selectedIndex = min(selectedIndex + 1, filteredCommands.count - 1)
    updateHighlight()
  }

  func confirmSelection() {
    guard selectedIndex < filteredCommands.count else { return }
    let entry = filteredCommands[selectedIndex]
    onSelect?(entry)
  }

  // MARK: - Row Management

  private func rebuildRows() {
    rowViews.forEach { $0.removeFromSuperview() }
    rowViews.removeAll()
    stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

    for (index, entry) in filteredCommands.enumerated() {
      let row = SlashCommandRowView(entry: entry, isSelected: index == selectedIndex)
      row.translatesAutoresizingMaskIntoConstraints = false
      row.heightAnchor.constraint(equalToConstant: 36).isActive = true
      stackView.addArrangedSubview(row)
      rowViews.append(row)
    }
  }

  private func updateHighlight() {
    for (index, row) in rowViews.enumerated() {
      row.setSelected(index == selectedIndex)
    }
  }
}

// MARK: - Row View

private class SlashCommandRowView: NSView {
  private let commandLabel = NSTextField(labelWithString: "")
  private let descLabel = NSTextField(labelWithString: "")
  private let highlightLayer = CALayer()

  init(entry: SlashCommandEntry, isSelected: Bool) {
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

  func setSelected(_ selected: Bool) {
    highlightLayer.backgroundColor =
      selected
      ? NSColor.white.withAlphaComponent(0.1).cgColor
      : NSColor.clear.cgColor
  }
}
