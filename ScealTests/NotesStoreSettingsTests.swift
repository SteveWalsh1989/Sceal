import Foundation
import XCTest

@testable import Sceal

@MainActor
final class NotesStoreSettingsTests: NotesStoreTestCase {
  // Prevents appearance setting updates from saving out-of-range values to defaults.
  func testUpdatingAppearanceSettingsClampsAndPersists() throws {
    let userDefaults = makeUserDefaults()
    let store = makeStore(userDefaults: userDefaults)

    store.updateAppearanceSettings { settings in
      settings.bodyFontSize = 999
      settings.lineHeight = 999
      settings.accentColorName = "not-a-real-color"
    }

    let data = try XCTUnwrap(
      userDefaults.data(forKey: "sceal.noteAppearanceSettings")
    )
    let persisted = try JSONDecoder().decode(NoteAppearanceSettings.self, from: data)

    XCTAssertEqual(
      store.appearanceSettings.bodyFontSize, NoteAppearanceSettings.maximumBodyFontSize)
    XCTAssertEqual(store.appearanceSettings.lineHeight, NoteAppearanceSettings.maximumLineHeight)
    XCTAssertEqual(
      store.appearanceSettings.accentColorName, NoteAppearanceSettings.defaultAccentColorName)
    XCTAssertEqual(persisted.bodyFontSize, NoteAppearanceSettings.maximumBodyFontSize)
    XCTAssertEqual(persisted.accentColorName, NoteAppearanceSettings.defaultAccentColorName)
  }

  // Prevents a saved appearance payload from being ignored on the next launch.
  func testLoadingAppearanceSettingsFromDefaults() throws {
    let userDefaults = makeUserDefaults()
    let encoded = try JSONEncoder().encode(
      NoteAppearanceSettings(bodyFontSize: 19, lineHeight: 1.4, accentColorName: "blue")
    )
    userDefaults.set(encoded, forKey: "sceal.noteAppearanceSettings")

    let store = makeStore(userDefaults: userDefaults)

    XCTAssertEqual(store.appearanceSettings.bodyFontSize, 19)
    XCTAssertEqual(store.appearanceSettings.lineHeight, 1.4)
    XCTAssertEqual(store.appearanceSettings.accentColorName, "blue")
  }

  // Prevents the new-note default picker from updating UI without persisting the choice.
  func testUpdatingNewNoteDefaultPersistsChoice() {
    let userDefaults = makeUserDefaults()
    let store = makeStore(userDefaults: userDefaults)

    store.updateNewNoteDefault(.copyPrevious)

    XCTAssertEqual(store.newNoteDefault, .copyPrevious)
    XCTAssertEqual(userDefaults.string(forKey: "sceal.newNoteDefault"), "copyPrevious")
  }

  // Prevents the new-note default from resetting to blank across launches.
  func testLoadingNewNoteDefaultFromDefaults() {
    let userDefaults = makeUserDefaults()
    userDefaults.set(NewNoteDefault.copyPrevious.rawValue, forKey: "sceal.newNoteDefault")

    let store = makeStore(userDefaults: userDefaults)

    XCTAssertEqual(store.newNoteDefault, .copyPrevious)
  }
}
