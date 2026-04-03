//
//  ScealPalette.swift
//

// Shared muted color palette for headings, bullets, accents, and theme settings.

import AppKit

// Muted flat palette shared across headings, bullets, checkboxes, and appearance settings.
enum ScealPalette {

  struct Entry {
    let name: String
    let color: NSColor
  }

  static let colors: [Entry] = [
    Entry(name: "blue", color: NSColor(red: 0.35, green: 0.55, blue: 0.85, alpha: 1)),
    Entry(name: "turquoise", color: NSColor(red: 0.30, green: 0.72, blue: 0.68, alpha: 1)),
    Entry(name: "pink", color: NSColor(red: 0.85, green: 0.40, blue: 0.55, alpha: 1)),
    Entry(name: "red", color: NSColor(red: 0.82, green: 0.35, blue: 0.35, alpha: 1)),
    Entry(name: "purple", color: NSColor(red: 0.60, green: 0.42, blue: 0.78, alpha: 1)),
    Entry(name: "orange", color: NSColor(red: 0.90, green: 0.58, blue: 0.30, alpha: 1)),
    Entry(name: "grey", color: NSColor(red: 0.58, green: 0.58, blue: 0.60, alpha: 1)),
    Entry(
      name: "white",
      color: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
          ? .white : .black
      }),
  ]

  // Looks up a palette color by its string name.
  static func color(named name: String) -> NSColor? {
    colors.first(where: { $0.name == name })?.color
  }

  // Returns the palette name for an NSColor, or nil if not found.
  static func name(for color: NSColor) -> String? {
    colors.first(where: { $0.color == color })?.name
  }
}
