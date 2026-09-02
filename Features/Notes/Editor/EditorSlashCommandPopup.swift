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

  // Positions and displays the popup below the current line.
  func show(relativeTo cursorRect: NSRect, in parentView: NSView) {
    guard !filteredCommands.isEmpty else {
      hide()
      return
    }

    let popupWidth: CGFloat = 210
    let rowHeight: CGFloat = 36
    let verticalPadding: CGFloat = 8
    let contentHeight = CGFloat(filteredCommands.count) * rowHeight + verticalPadding
    let gap: CGFloat = 4

    let edgeInset: CGFloat = 4
    let clippedVisibleBounds = parentView.visibleRect.intersection(parentView.bounds)
    let visibleBounds = clippedVisibleBounds.isEmpty ? parentView.bounds : clippedVisibleBounds
    let popupHeight = min(
      contentHeight, max(rowHeight + verticalPadding, visibleBounds.height - 2 * edgeInset))
    let minimumX = visibleBounds.minX + edgeInset
    let maximumX = max(minimumX, visibleBounds.maxX - popupWidth - edgeInset)
    let minimumY = visibleBounds.minY + edgeInset
    let maximumY = max(minimumY, visibleBounds.maxY - popupHeight - edgeInset)

    let preferredY: CGFloat
    if parentView.isFlipped {
      let aboveY = cursorRect.minY - popupHeight - gap
      preferredY = aboveY >= minimumY ? aboveY : cursorRect.maxY + gap
    } else {
      let aboveY = cursorRect.maxY + gap
      preferredY =
        aboveY + popupHeight <= visibleBounds.maxY - edgeInset
        ? aboveY : cursorRect.minY - popupHeight - gap
    }

    let origin = NSPoint(
      x: min(max(cursorRect.minX, minimumX), maximumX),
      y: min(max(preferredY, minimumY), maximumY)
    )

    if superview == nil {
      parentView.addSubview(self, positioned: .above, relativeTo: nil)
    }

    translatesAutoresizingMaskIntoConstraints = true
    autoresizingMask = []
    frame = NSRect(x: origin.x, y: origin.y, width: popupWidth, height: popupHeight)
    stackView.frame = NSRect(x: 0, y: 0, width: popupWidth, height: contentHeight)
    isHidden = false
    alphaValue = 1
  }

  // Removes the popup from its parent view.
  func hide() {
    isHidden = true
    removeFromSuperview()
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
    guard selectedIndex < filteredCommands.count else { return }
    let entry = filteredCommands[selectedIndex]
    onSelect?(entry)
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
      let row = SlashCommandRowView(entry: entry, isSelected: index == selectedIndex)
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

  func setSelected(_ selected: Bool) {
    highlightLayer.backgroundColor =
      selected
      ? NSColor.white.withAlphaComponent(0.1).cgColor
      : NSColor.clear.cgColor
  }
}
