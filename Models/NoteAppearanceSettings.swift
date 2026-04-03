//
//  NoteAppearanceSettings.swift
//

// Shared editor and sidebar appearance settings with theme resolution and persistence.

import AppKit
import SwiftUI

struct NoteAppearanceSettings: Codable, Equatable, Sendable {
  static let systemFontToken = "__system__"
  static let minimumBodyFontSize: CGFloat = 11
  static let maximumBodyFontSize: CGFloat = 24
  static let defaultBodyFontSize: CGFloat = 15
  static let minimumLineHeight: CGFloat = 0.8
  static let maximumLineHeight: CGFloat = 1.8
  static let defaultLineHeight: CGFloat = 1.0
  static let minimumListItemSpacing: CGFloat = 0
  static let maximumListItemSpacing: CGFloat = 6
  static let defaultListItemSpacing: CGFloat = 1
  static let minimumBulletSize: CGFloat = 12
  static let maximumBulletSize: CGFloat = 30
  static let defaultBulletSize: CGFloat = 16
  static let minimumSectionDividerGapScale: CGFloat = 1
  static let maximumSectionDividerGapScale: CGFloat = 3
  static let defaultSectionDividerGapScale: CGFloat = 1
  static let minimumSidebarFontSize: CGFloat = 12
  static let maximumSidebarFontSize: CGFloat = 18
  static let defaultSidebarFontSize: CGFloat = 14
  static let defaultAccentColorName = "pink"
  static let defaultThemeID = "default-dark"
  static let `default` = NoteAppearanceSettings()

  var bodyFontName: String
  var bodyFontSize: CGFloat
  var lineHeight: CGFloat
  var listItemSpacing: CGFloat
  var bulletSize: CGFloat
  var sectionDividerGapScale: CGFloat
  var sidebarFontSize: CGFloat
  var accentColorName: String
  var sidebarShowsTags: Bool
  var sidebarDateFormat: SidebarDateFormat
  var themeID: String
  var colorOverrides: ThemeColorSet?

  init(
    bodyFontName: String = Self.systemFontToken,
    bodyFontSize: CGFloat = Self.defaultBodyFontSize,
    lineHeight: CGFloat = Self.defaultLineHeight,
    listItemSpacing: CGFloat = Self.defaultListItemSpacing,
    bulletSize: CGFloat = Self.defaultBulletSize,
    sectionDividerGapScale: CGFloat = Self.defaultSectionDividerGapScale,
    sidebarFontSize: CGFloat = Self.defaultSidebarFontSize,
    accentColorName: String = Self.defaultAccentColorName,
    sidebarShowsTags: Bool = false,
    sidebarDateFormat: SidebarDateFormat = .yearMonthDay,
    themeID: String = Self.defaultThemeID,
    colorOverrides: ThemeColorSet? = nil
  ) {
    self.bodyFontName = bodyFontName
    self.bodyFontSize = bodyFontSize
    self.lineHeight = lineHeight
    self.listItemSpacing = listItemSpacing
    self.bulletSize = bulletSize
    self.sectionDividerGapScale = sectionDividerGapScale
    self.sidebarFontSize = sidebarFontSize
    self.accentColorName = accentColorName
    self.sidebarShowsTags = sidebarShowsTags
    self.sidebarDateFormat = sidebarDateFormat
    self.themeID = themeID
    self.colorOverrides = colorOverrides
  }

  // Returns a copy with all numeric values clamped to their valid ranges.
  var clamped: NoteAppearanceSettings {
    NoteAppearanceSettings(
      bodyFontName: normalizedBodyFontName,
      bodyFontSize: bodyFontSize.clamped(
        to: Self.minimumBodyFontSize...Self.maximumBodyFontSize),
      lineHeight: lineHeight.clamped(to: Self.minimumLineHeight...Self.maximumLineHeight),
      listItemSpacing: listItemSpacing.clamped(
        to: Self.minimumListItemSpacing...Self.maximumListItemSpacing),
      bulletSize: bulletSize.clamped(to: Self.minimumBulletSize...Self.maximumBulletSize),
      sectionDividerGapScale: sectionDividerGapScale.clamped(
        to: Self.minimumSectionDividerGapScale...Self.maximumSectionDividerGapScale),
      sidebarFontSize: sidebarFontSize.clamped(
        to: Self.minimumSidebarFontSize...Self.maximumSidebarFontSize),
      accentColorName: normalizedAccentColorName,
      sidebarShowsTags: sidebarShowsTags,
      sidebarDateFormat: sidebarDateFormat,
      themeID: themeID,
      colorOverrides: colorOverrides
    )
  }

  // Resolved NSFont for the editor body text.
  var bodyFont: NSFont {
    resolvedFont(ofSize: bodyFontSize)
  }

  // Human-readable font name for the settings UI.
  var bodyFontDisplayName: String {
    if normalizedBodyFontName == Self.systemFontToken {
      return "System"
    }

    return resolvedFont(ofSize: bodyFontSize).displayName ?? normalizedBodyFontName
  }

  // Resolved accent NSColor from the palette.
  var accentColor: NSColor {
    ScealPalette.color(named: normalizedAccentColorName)
      ?? ScealPalette.color(named: Self.defaultAccentColorName)
      ?? .systemPink
  }

  // Resolves the effective color set for the active theme.
  var resolvedColors: ThemeColorSet {
    if let colorOverrides { return colorOverrides }
    return ScealTheme.builtIn(id: themeID)?.colors
      ?? ScealTheme.defaultDark.colors
  }

  // The color scheme the active theme requires.
  var preferredColorScheme: ColorScheme? {
    let theme = ScealTheme.builtIn(id: themeID) ?? ScealTheme.defaultDark
    return theme.mode == .dark ? .dark : .light
  }

  // Resolves the named font at the given size, falling back to system font.
  func resolvedFont(ofSize size: CGFloat) -> NSFont {
    let clampedSize = size.clamped(to: Self.minimumBodyFontSize...Self.maximumBodyFontSize)

    guard normalizedBodyFontName != Self.systemFontToken else {
      return NSFont.systemFont(ofSize: clampedSize)
    }

    return NSFont(name: normalizedBodyFontName, size: clampedSize)
      ?? NSFont.systemFont(ofSize: clampedSize)
  }

  // Bold variant of the body font at the given size.
  func boldBodyFont(ofSize size: CGFloat) -> NSFont {
    NSFontManager.shared.convert(resolvedFont(ofSize: size), toHaveTrait: .boldFontMask)
  }

  // Italic variant of the body font at the given size.
  func italicBodyFont(ofSize size: CGFloat) -> NSFont {
    NSFontManager.shared.convert(resolvedFont(ofSize: size), toHaveTrait: .italicFontMask)
  }

  // Falls back to the system font token when the name is empty.
  private var normalizedBodyFontName: String {
    bodyFontName.isEmpty ? Self.systemFontToken : bodyFontName
  }

  // Falls back to the default accent when the name isn't in the palette.
  private var normalizedAccentColorName: String {
    ScealPalette.colors.contains(where: { $0.name == accentColorName })
      ? accentColorName
      : Self.defaultAccentColorName
  }

  private enum CodingKeys: String, CodingKey {
    case bodyFontName
    case bodyFontSize
    case lineHeight
    case listItemSpacing
    case bulletSize
    case sectionDividerGapScale
    case sidebarFontSize
    case accentColorName
    case sidebarShowsTags
    case sidebarDateFormat
    case themeID
    case colorOverrides
  }

  // Decodes with defaults for any missing keys to support forward compatibility.
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      bodyFontName: try container.decodeIfPresent(String.self, forKey: .bodyFontName)
        ?? Self.systemFontToken,
      bodyFontSize: try container.decodeIfPresent(CGFloat.self, forKey: .bodyFontSize)
        ?? Self.defaultBodyFontSize,
      lineHeight: try container.decodeIfPresent(CGFloat.self, forKey: .lineHeight)
        ?? Self.defaultLineHeight,
      listItemSpacing: try container.decodeIfPresent(CGFloat.self, forKey: .listItemSpacing)
        ?? Self.defaultListItemSpacing,
      bulletSize: try container.decodeIfPresent(CGFloat.self, forKey: .bulletSize)
        ?? Self.defaultBulletSize,
      sectionDividerGapScale: try container.decodeIfPresent(
        CGFloat.self,
        forKey: .sectionDividerGapScale
      ) ?? Self.defaultSectionDividerGapScale,
      sidebarFontSize: try container.decodeIfPresent(CGFloat.self, forKey: .sidebarFontSize)
        ?? Self.defaultSidebarFontSize,
      accentColorName: try container.decodeIfPresent(String.self, forKey: .accentColorName)
        ?? Self.defaultAccentColorName,
      sidebarShowsTags: try container.decodeIfPresent(Bool.self, forKey: .sidebarShowsTags)
        ?? false,
      sidebarDateFormat: try container.decodeIfPresent(
        SidebarDateFormat.self,
        forKey: .sidebarDateFormat
      ) ?? .yearMonthDay,
      themeID: try container.decodeIfPresent(String.self, forKey: .themeID)
        ?? Self.defaultThemeID,
      colorOverrides: try container.decodeIfPresent(
        ThemeColorSet.self, forKey: .colorOverrides)
    )
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(bodyFontName, forKey: .bodyFontName)
    try container.encode(bodyFontSize, forKey: .bodyFontSize)
    try container.encode(lineHeight, forKey: .lineHeight)
    try container.encode(listItemSpacing, forKey: .listItemSpacing)
    try container.encode(bulletSize, forKey: .bulletSize)
    try container.encode(sectionDividerGapScale, forKey: .sectionDividerGapScale)
    try container.encode(sidebarFontSize, forKey: .sidebarFontSize)
    try container.encode(accentColorName, forKey: .accentColorName)
    try container.encode(sidebarShowsTags, forKey: .sidebarShowsTags)
    try container.encode(sidebarDateFormat, forKey: .sidebarDateFormat)
    try container.encode(themeID, forKey: .themeID)
    try container.encodeIfPresent(colorOverrides, forKey: .colorOverrides)
  }
}

extension CGFloat {
  // Constrains a value to the given closed range.
  fileprivate func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
    Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
  }
}
