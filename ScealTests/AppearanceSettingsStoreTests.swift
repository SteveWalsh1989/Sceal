import Foundation
import XCTest

@testable import Sceal

@MainActor
final class AppearanceSettingsStoreTests: NotesStoreTestCase {
  // Keeps the extracted appearance store compatible with the existing defaults payload.
  func testLoadsAppearanceSettingsFromRepository() throws {
    let userDefaults = makeUserDefaults()
    let expectedSettings = NoteAppearanceSettings(
      bodyFontSize: 19,
      lineHeight: 1.4,
      accentColorName: "blue"
    )
    userDefaults.set(
      try JSONEncoder().encode(expectedSettings),
      forKey: "sceal.noteAppearanceSettings"
    )

    let store = AppearanceSettingsStore(
      settingsRepository: SettingsRepository(userDefaults: userDefaults)
    )

    XCTAssertEqual(store.settings.bodyFontSize, 19)
    XCTAssertEqual(store.settings.lineHeight, 1.4)
    XCTAssertEqual(store.settings.accentColorName, "blue")
  }

  // Prevents extracted appearance mutations from bypassing clamp and persistence behavior.
  func testUpdatingAppearanceSettingsClampsAndPersists() throws {
    let userDefaults = makeUserDefaults()
    let store = AppearanceSettingsStore(
      settingsRepository: SettingsRepository(userDefaults: userDefaults)
    )

    try store.updateSettings { settings in
      settings.bodyFontSize = 999
      settings.lineHeight = 999
      settings.accentColorName = "not-a-real-color"
    }

    let data = try XCTUnwrap(
      userDefaults.data(forKey: "sceal.noteAppearanceSettings")
    )
    let persisted = try JSONDecoder().decode(NoteAppearanceSettings.self, from: data)

    XCTAssertEqual(store.settings.bodyFontSize, NoteAppearanceSettings.maximumBodyFontSize)
    XCTAssertEqual(store.settings.lineHeight, NoteAppearanceSettings.maximumLineHeight)
    XCTAssertEqual(store.settings.accentColorName, NoteAppearanceSettings.defaultAccentColorName)
    XCTAssertEqual(persisted.bodyFontSize, NoteAppearanceSettings.maximumBodyFontSize)
    XCTAssertEqual(persisted.accentColorName, NoteAppearanceSettings.defaultAccentColorName)
  }
}
