//
//  NoteAppearanceFontPanelController.swift
//

// Bridges the macOS system font panel to deliver font-name changes via callback.

import AppKit

// Presents the system font panel and forwards font-name changes to a callback.
@MainActor final class FontPanelController: NSObject {
  private var selectedFont = NoteAppearanceSettings.default.bodyFont
  private var onFontChange: ((String) -> Void)?

  // Shows the system font panel initialized with the given font name.
  func present(
    using appearanceSettings: NoteAppearanceSettings, onChange: @escaping (String) -> Void
  ) {
    selectedFont = appearanceSettings.bodyFont
    onFontChange = onChange

    let fontManager = NSFontManager.shared
    fontManager.target = self
    fontManager.action = #selector(changeFont(_:))
    fontManager.setSelectedFont(selectedFont, isMultiple: false)
    NSFontPanel.shared.setPanelFont(selectedFont, isMultiple: false)
    fontManager.orderFrontFontPanel(nil)
  }

  // Removes this controller as the font panel's target.
  func detachIfNeeded() {
    if (NSFontManager.shared.target as AnyObject?) === self {
      NSFontManager.shared.target = nil
    }
  }

  // Called by AppKit when the user picks a font; forwards the name to the callback.
  @objc private func changeFont(_ sender: NSFontManager) {
    let convertedFont = sender.convert(selectedFont)
    selectedFont =
      NSFont(name: convertedFont.fontName, size: selectedFont.pointSize)
      ?? NSFont.systemFont(ofSize: selectedFont.pointSize)
    onFontChange?(selectedFont.fontName)
  }
}
