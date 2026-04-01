//
//  NoteAppearanceSettings.swift
//  dayra
//

import AppKit

struct NoteAppearanceSettings: Codable, Equatable {
  static let systemFontToken = "__system__"
  static let minimumBodyFontSize: CGFloat = 11
  static let maximumBodyFontSize: CGFloat = 24
  static let defaultBodyFontSize: CGFloat = 15
  static let minimumLineHeight: CGFloat = 1.0
  static let maximumLineHeight: CGFloat = 1.8
  static let defaultLineHeight: CGFloat = 1.0
  static let minimumBulletSize: CGFloat = 12
  static let maximumBulletSize: CGFloat = 30
  static let defaultBulletSize: CGFloat = 16
  static let defaultAccentColorName = "pink"
  static let `default` = NoteAppearanceSettings()

  var bodyFontName: String
  var bodyFontSize: CGFloat
  var lineHeight: CGFloat
  var bulletSize: CGFloat
  var accentColorName: String

  init(
    bodyFontName: String = Self.systemFontToken,
    bodyFontSize: CGFloat = Self.defaultBodyFontSize,
    lineHeight: CGFloat = Self.defaultLineHeight,
    bulletSize: CGFloat = Self.defaultBulletSize,
    accentColorName: String = Self.defaultAccentColorName
  ) {
    self.bodyFontName = bodyFontName
    self.bodyFontSize = bodyFontSize
    self.lineHeight = lineHeight
    self.bulletSize = bulletSize
    self.accentColorName = accentColorName
  }

  var clamped: NoteAppearanceSettings {
    NoteAppearanceSettings(
      bodyFontName: normalizedBodyFontName,
      bodyFontSize: bodyFontSize.clamped(
        to: Self.minimumBodyFontSize...Self.maximumBodyFontSize),
      lineHeight: lineHeight.clamped(to: Self.minimumLineHeight...Self.maximumLineHeight),
      bulletSize: bulletSize.clamped(to: Self.minimumBulletSize...Self.maximumBulletSize),
      accentColorName: normalizedAccentColorName
    )
  }

  var bodyFont: NSFont {
    resolvedFont(ofSize: bodyFontSize)
  }

  var bodyFontDisplayName: String {
    if normalizedBodyFontName == Self.systemFontToken {
      return "System"
    }

    return resolvedFont(ofSize: bodyFontSize).displayName ?? normalizedBodyFontName
  }

  var accentColor: NSColor {
    DayraPalette.color(named: normalizedAccentColorName)
      ?? DayraPalette.color(named: Self.defaultAccentColorName)
      ?? .systemPink
  }

  func resolvedFont(ofSize size: CGFloat) -> NSFont {
    let clampedSize = size.clamped(to: Self.minimumBodyFontSize...Self.maximumBodyFontSize)

    guard normalizedBodyFontName != Self.systemFontToken else {
      return NSFont.systemFont(ofSize: clampedSize)
    }

    return NSFont(name: normalizedBodyFontName, size: clampedSize)
      ?? NSFont.systemFont(ofSize: clampedSize)
  }

  func boldBodyFont(ofSize size: CGFloat) -> NSFont {
    NSFontManager.shared.convert(resolvedFont(ofSize: size), toHaveTrait: .boldFontMask)
  }

  func italicBodyFont(ofSize size: CGFloat) -> NSFont {
    NSFontManager.shared.convert(resolvedFont(ofSize: size), toHaveTrait: .italicFontMask)
  }

  private var normalizedBodyFontName: String {
    bodyFontName.isEmpty ? Self.systemFontToken : bodyFontName
  }

  private var normalizedAccentColorName: String {
    DayraPalette.colors.contains(where: { $0.name == accentColorName })
      ? accentColorName
      : Self.defaultAccentColorName
  }
}

extension CGFloat {
  fileprivate func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
    Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
  }
}
