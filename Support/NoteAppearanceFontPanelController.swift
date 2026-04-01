//
//  NoteAppearanceFontPanelController.swift
//  dayra
//

import AppKit

// Presents the system font panel and forwards font-name changes to a callback.
final class SettingsFontPanelController: NSObject {
  private var selectedFont = NoteAppearanceSettings.default.bodyFont
  private var onFontChange: ((String) -> Void)?

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

  func detachIfNeeded() {
    if (NSFontManager.shared.target as AnyObject?) === self {
      NSFontManager.shared.target = nil
    }
  }

  @objc private func changeFont(_ sender: NSFontManager) {
    let convertedFont = sender.convert(selectedFont)
    selectedFont =
      NSFont(name: convertedFont.fontName, size: selectedFont.pointSize)
      ?? NSFont.systemFont(ofSize: selectedFont.pointSize)
    onFontChange?(selectedFont.fontName)
  }
}
