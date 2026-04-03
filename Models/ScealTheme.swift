//
//  ScealTheme.swift
//

// Theme model defining color tokens, modes, and 10 built-in light/dark themes.

import AppKit
import SwiftUI

// Codable RGBA color that bridges AppKit NSColor and SwiftUI Color.
struct ThemeColor: Codable, Equatable, Sendable {
  let red: CGFloat
  let green: CGFloat
  let blue: CGFloat
  let alpha: CGFloat

  init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
    self.red = red
    self.green = green
    self.blue = blue
    self.alpha = alpha
  }

  // Converts an AppKit NSColor to stored RGBA components.
  init(nsColor: NSColor) {
    let converted = nsColor.usingColorSpace(.sRGB) ?? nsColor
    self.red = converted.redComponent
    self.green = converted.greenComponent
    self.blue = converted.blueComponent
    self.alpha = converted.alphaComponent
  }

  // Converts back to an AppKit NSColor.
  var nsColor: NSColor {
    NSColor(red: red, green: green, blue: blue, alpha: alpha)
  }

  // Converts to a SwiftUI Color.
  var color: Color {
    Color(red: red, green: green, blue: blue, opacity: alpha)
  }
}

// The complete set of color tokens that define a theme's appearance.
struct ThemeColorSet: Codable, Equatable, Sendable {
  var sidebarBackground: ThemeColor
  var editorBackground: ThemeColor
  var selectedCard: ThemeColor
  var unselectedCard: ThemeColor
  var sectionCardFill: ThemeColor
  var controlBackground: ThemeColor
  var divider: ThemeColor
  var noteBodyBorder: ThemeColor
}

// Whether a theme targets dark or light appearance.
enum ThemeMode: String, Codable, Equatable, Sendable {
  case dark
  case light
}


// A named theme with a mode and a full color set.
struct ScealTheme: Identifiable, Codable, Equatable, Sendable {
  let id: String
  let displayName: String
  let mode: ThemeMode
  let colors: ThemeColorSet
  let suggestedAccent: String

  // MARK: - Built-in themes

  static let allBuiltIn: [ScealTheme] = [
    defaultDark, midnight, charcoal, slate, ember,
    defaultLight, paper, ivory, cloud, sand,
  ]

  // Looks up a built-in theme by its string identifier.
  static func builtIn(id: String) -> ScealTheme? {
    allBuiltIn.first(where: { $0.id == id })
  }

  // Returns the default theme for the given light/dark mode.
  static func defaultTheme(for mode: ThemeMode) -> ScealTheme {
    mode == .dark ? defaultDark : defaultLight
  }

  // Returns all built-in dark themes.
  static func darkThemes() -> [ScealTheme] {
    allBuiltIn.filter { $0.mode == .dark }
  }

  // Returns all built-in light themes.
  static func lightThemes() -> [ScealTheme] {
    allBuiltIn.filter { $0.mode == .light }
  }

  // MARK: - Dark themes

  // Current app colors — exact RGB values preserved as the default.
  static let defaultDark = ScealTheme(
    id: "default-dark",
    displayName: "Default",
    mode: .dark,
    colors: ThemeColorSet(
      sidebarBackground: ThemeColor(red: 0.105, green: 0.105, blue: 0.12),
      editorBackground: ThemeColor(red: 0.09, green: 0.09, blue: 0.105),
      selectedCard: ThemeColor(red: 0.175, green: 0.175, blue: 0.2),
      unselectedCard: ThemeColor(red: 0.13, green: 0.13, blue: 0.15),
      sectionCardFill: ThemeColor(red: 0.13, green: 0.13, blue: 0.15),
      controlBackground: ThemeColor(red: 1, green: 1, blue: 1, alpha: 0.08),
      divider: ThemeColor(red: 1, green: 1, blue: 1, alpha: 0.16),
      noteBodyBorder: ThemeColor(red: 0, green: 0, blue: 0, alpha: 0)
    ),
    suggestedAccent: "pink"
  )

  // Deep blue-black inspired by iA Writer dark mode.
  static let midnight = ScealTheme(
    id: "midnight",
    displayName: "Midnight",
    mode: .dark,
    colors: ThemeColorSet(
      sidebarBackground: ThemeColor(red: 0.07, green: 0.07, blue: 0.10),
      editorBackground: ThemeColor(red: 0.05, green: 0.05, blue: 0.08),
      selectedCard: ThemeColor(red: 0.12, green: 0.12, blue: 0.17),
      unselectedCard: ThemeColor(red: 0.09, green: 0.09, blue: 0.13),
      sectionCardFill: ThemeColor(red: 0.09, green: 0.09, blue: 0.13),
      controlBackground: ThemeColor(red: 1, green: 1, blue: 1, alpha: 0.07),
      divider: ThemeColor(red: 1, green: 1, blue: 1, alpha: 0.12),
      noteBodyBorder: ThemeColor(red: 0, green: 0, blue: 0, alpha: 0)
    ),
    suggestedAccent: "blue"
  )

  // Warm neutral dark inspired by Bear.
  static let charcoal = ScealTheme(
    id: "charcoal",
    displayName: "Charcoal",
    mode: .dark,
    colors: ThemeColorSet(
      sidebarBackground: ThemeColor(red: 0.13, green: 0.12, blue: 0.12),
      editorBackground: ThemeColor(red: 0.11, green: 0.10, blue: 0.10),
      selectedCard: ThemeColor(red: 0.20, green: 0.18, blue: 0.17),
      unselectedCard: ThemeColor(red: 0.16, green: 0.14, blue: 0.14),
      sectionCardFill: ThemeColor(red: 0.16, green: 0.14, blue: 0.14),
      controlBackground: ThemeColor(red: 1, green: 1, blue: 1, alpha: 0.08),
      divider: ThemeColor(red: 1, green: 1, blue: 1, alpha: 0.14),
      noteBodyBorder: ThemeColor(red: 0, green: 0, blue: 0, alpha: 0)
    ),
    suggestedAccent: "orange"
  )

  // Slightly lifted grey-blue inspired by Obsidian.
  static let slate = ScealTheme(
    id: "slate",
    displayName: "Slate",
    mode: .dark,
    colors: ThemeColorSet(
      sidebarBackground: ThemeColor(red: 0.14, green: 0.14, blue: 0.17),
      editorBackground: ThemeColor(red: 0.11, green: 0.11, blue: 0.14),
      selectedCard: ThemeColor(red: 0.20, green: 0.20, blue: 0.24),
      unselectedCard: ThemeColor(red: 0.17, green: 0.17, blue: 0.20),
      sectionCardFill: ThemeColor(red: 0.17, green: 0.17, blue: 0.20),
      controlBackground: ThemeColor(red: 1, green: 1, blue: 1, alpha: 0.08),
      divider: ThemeColor(red: 1, green: 1, blue: 1, alpha: 0.14),
      noteBodyBorder: ThemeColor(red: 0, green: 0, blue: 0, alpha: 0)
    ),
    suggestedAccent: "purple"
  )

  // Warm reddish dark tones.
  static let ember = ScealTheme(
    id: "ember",
    displayName: "Ember",
    mode: .dark,
    colors: ThemeColorSet(
      sidebarBackground: ThemeColor(red: 0.13, green: 0.09, blue: 0.09),
      editorBackground: ThemeColor(red: 0.10, green: 0.07, blue: 0.07),
      selectedCard: ThemeColor(red: 0.20, green: 0.14, blue: 0.14),
      unselectedCard: ThemeColor(red: 0.16, green: 0.11, blue: 0.11),
      sectionCardFill: ThemeColor(red: 0.16, green: 0.11, blue: 0.11),
      controlBackground: ThemeColor(red: 1, green: 1, blue: 1, alpha: 0.08),
      divider: ThemeColor(red: 1, green: 1, blue: 1, alpha: 0.14),
      noteBodyBorder: ThemeColor(red: 0, green: 0, blue: 0, alpha: 0)
    ),
    suggestedAccent: "red"
  )

  // MARK: - Light themes

  // Current app colors — exact RGB values preserved as the default.
  static let defaultLight = ScealTheme(
    id: "default-light",
    displayName: "Default",
    mode: .light,
    colors: ThemeColorSet(
      sidebarBackground: ThemeColor(red: 0.94, green: 0.94, blue: 0.955),
      editorBackground: ThemeColor(red: 0.955, green: 0.955, blue: 0.97),
      selectedCard: ThemeColor(red: 0, green: 0, blue: 0, alpha: 0.08),
      unselectedCard: ThemeColor(red: 0, green: 0, blue: 0, alpha: 0.04),
      sectionCardFill: ThemeColor(red: 0.985, green: 0.985, blue: 0.992),
      controlBackground: ThemeColor(red: 0, green: 0, blue: 0, alpha: 0.05),
      divider: ThemeColor(red: 0, green: 0, blue: 0, alpha: 0.12),
      noteBodyBorder: ThemeColor(red: 0, green: 0, blue: 0, alpha: 0.08)
    ),
    suggestedAccent: "pink"
  )

  // Warm off-white inspired by iA Writer.
  static let paper = ScealTheme(
    id: "paper",
    displayName: "Paper",
    mode: .light,
    colors: ThemeColorSet(
      sidebarBackground: ThemeColor(red: 0.95, green: 0.94, blue: 0.92),
      editorBackground: ThemeColor(red: 0.97, green: 0.96, blue: 0.94),
      selectedCard: ThemeColor(red: 0.42, green: 0.38, blue: 0.34, alpha: 0.12),
      unselectedCard: ThemeColor(red: 0.42, green: 0.38, blue: 0.34, alpha: 0.05),
      sectionCardFill: ThemeColor(red: 0.98, green: 0.97, blue: 0.96),
      controlBackground: ThemeColor(red: 0.42, green: 0.38, blue: 0.34, alpha: 0.07),
      divider: ThemeColor(red: 0.42, green: 0.38, blue: 0.34, alpha: 0.14),
      noteBodyBorder: ThemeColor(red: 0.42, green: 0.38, blue: 0.34, alpha: 0.10)
    ),
    suggestedAccent: "blue"
  )

  // Clean warm white inspired by Bear.
  static let ivory = ScealTheme(
    id: "ivory",
    displayName: "Ivory",
    mode: .light,
    colors: ThemeColorSet(
      sidebarBackground: ThemeColor(red: 0.96, green: 0.96, blue: 0.95),
      editorBackground: ThemeColor(red: 0.98, green: 0.98, blue: 0.97),
      selectedCard: ThemeColor(red: 0, green: 0, blue: 0, alpha: 0.07),
      unselectedCard: ThemeColor(red: 0, green: 0, blue: 0, alpha: 0.03),
      sectionCardFill: ThemeColor(red: 0.99, green: 0.99, blue: 0.985),
      controlBackground: ThemeColor(red: 0, green: 0, blue: 0, alpha: 0.05),
      divider: ThemeColor(red: 0, green: 0, blue: 0, alpha: 0.10),
      noteBodyBorder: ThemeColor(red: 0, green: 0, blue: 0, alpha: 0.07)
    ),
    suggestedAccent: "turquoise"
  )

  // Cool blue-grey tint.
  static let cloud = ScealTheme(
    id: "cloud",
    displayName: "Cloud",
    mode: .light,
    colors: ThemeColorSet(
      sidebarBackground: ThemeColor(red: 0.92, green: 0.93, blue: 0.96),
      editorBackground: ThemeColor(red: 0.95, green: 0.96, blue: 0.98),
      selectedCard: ThemeColor(red: 0.22, green: 0.28, blue: 0.42, alpha: 0.12),
      unselectedCard: ThemeColor(red: 0.22, green: 0.28, blue: 0.42, alpha: 0.05),
      sectionCardFill: ThemeColor(red: 0.97, green: 0.975, blue: 0.99),
      controlBackground: ThemeColor(red: 0.22, green: 0.28, blue: 0.42, alpha: 0.07),
      divider: ThemeColor(red: 0.22, green: 0.28, blue: 0.42, alpha: 0.14),
      noteBodyBorder: ThemeColor(red: 0.22, green: 0.28, blue: 0.42, alpha: 0.10)
    ),
    suggestedAccent: "blue"
  )

  // Warm beige tones.
  static let sand = ScealTheme(
    id: "sand",
    displayName: "Sand",
    mode: .light,
    colors: ThemeColorSet(
      sidebarBackground: ThemeColor(red: 0.95, green: 0.93, blue: 0.90),
      editorBackground: ThemeColor(red: 0.97, green: 0.96, blue: 0.93),
      selectedCard: ThemeColor(red: 0.44, green: 0.36, blue: 0.26, alpha: 0.12),
      unselectedCard: ThemeColor(red: 0.44, green: 0.36, blue: 0.26, alpha: 0.05),
      sectionCardFill: ThemeColor(red: 0.98, green: 0.975, blue: 0.955),
      controlBackground: ThemeColor(red: 0.44, green: 0.36, blue: 0.26, alpha: 0.07),
      divider: ThemeColor(red: 0.44, green: 0.36, blue: 0.26, alpha: 0.14),
      noteBodyBorder: ThemeColor(red: 0.44, green: 0.36, blue: 0.26, alpha: 0.10)
    ),
    suggestedAccent: "orange"
  )
}
