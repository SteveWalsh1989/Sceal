import SwiftUI
import XCTest

@testable import Sceal

@MainActor
final class NoteAppearanceSettingsTests: XCTestCase {
  // Prevents extreme settings values from escaping the supported UI range.
  func testClampsNumericValues() {
    let settings = NoteAppearanceSettings(
      bodyFontSize: 99,
      lineHeight: 99,
      listItemSpacing: 99,
      bulletSize: 99,
      sectionDividerGapScale: 99,
      sidebarFontSize: 99
    ).clamped

    XCTAssertEqual(settings.bodyFontSize, NoteAppearanceSettings.maximumBodyFontSize)
    XCTAssertEqual(settings.lineHeight, NoteAppearanceSettings.maximumLineHeight)
    XCTAssertEqual(settings.listItemSpacing, NoteAppearanceSettings.maximumListItemSpacing)
    XCTAssertEqual(settings.bulletSize, NoteAppearanceSettings.maximumBulletSize)
    XCTAssertEqual(
      settings.sectionDividerGapScale,
      NoteAppearanceSettings.maximumSectionDividerGapScale
    )
    XCTAssertEqual(settings.sidebarFontSize, NoteAppearanceSettings.maximumSidebarFontSize)
  }

  // Prevents an empty stored font name from breaking font resolution.
  func testEmptyFontNameFallsBackToSystem() {
    let settings = NoteAppearanceSettings(bodyFontName: "").clamped

    XCTAssertEqual(settings.bodyFontDisplayName, "System")
  }

  // Prevents stale accent color values from breaking color lookup.
  func testInvalidAccentFallsBackToDefault() {
    let settings = NoteAppearanceSettings(accentColorName: "not-a-real-color").clamped

    XCTAssertEqual(settings.accentColorName, NoteAppearanceSettings.defaultAccentColorName)
  }

  // Prevents older saved settings payloads from decoding as zeroed-out values.
  func testDecodingMissingKeysUsesDefaults() throws {
    let data = try JSONEncoder().encode(["bodyFontName": NoteAppearanceSettings.systemFontToken])
    let settings = try JSONDecoder().decode(NoteAppearanceSettings.self, from: data)

    XCTAssertEqual(settings.bodyFontSize, NoteAppearanceSettings.defaultBodyFontSize)
    XCTAssertEqual(settings.lineHeight, NoteAppearanceSettings.defaultLineHeight)
    XCTAssertEqual(settings.sidebarDateFormat, .yearMonthDay)
    XCTAssertFalse(settings.calendarHidesWeekends)
    XCTAssertEqual(settings.themeID, NoteAppearanceSettings.defaultThemeID)
  }

  // Prevents invalid custom fonts from crashing or returning unusable font objects.
  func testInvalidCustomFontFallsBackToSystemFont() {
    let settings = NoteAppearanceSettings(bodyFontName: "DefinitelyNotARealFont")

    XCTAssertEqual(
      settings.resolvedFont(ofSize: 17).fontName,
      NSFont.systemFont(ofSize: 17).fontName
    )
  }

  // Prevents theme changes from reporting the wrong light or dark color scheme.
  func testPreferredColorSchemeMatchesTheme() {
    XCTAssertEqual(NoteAppearanceSettings(themeID: "default-dark").preferredColorScheme, .dark)
    XCTAssertEqual(NoteAppearanceSettings(themeID: "default-light").preferredColorScheme, .light)
  }
}
