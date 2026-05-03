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

  // Prevents new installs from silently shipping with spell checking disabled.
  func testContinuousSpellCheckingDefaultsToEnabled() {
    let userDefaults = makeUserDefaults()
    let store = makeStore(userDefaults: userDefaults)

    XCTAssertTrue(store.continuousSpellCheckingEnabled)
  }

  // Prevents the spell-check toggle from changing UI state without persisting the preference.
  func testUpdatingContinuousSpellCheckingPersistsChoice() {
    let userDefaults = makeUserDefaults()
    let store = makeStore(userDefaults: userDefaults)

    store.updateContinuousSpellCheckingEnabled(false)

    XCTAssertFalse(store.continuousSpellCheckingEnabled)
    XCTAssertEqual(
      userDefaults.object(forKey: "sceal.continuousSpellCheckingEnabled") as? Bool,
      false
    )
  }

  // Prevents the persisted spell-check preference from being ignored on relaunch.
  func testLoadingContinuousSpellCheckingFromDefaults() {
    let userDefaults = makeUserDefaults()
    userDefaults.set(false, forKey: "sceal.continuousSpellCheckingEnabled")

    let store = makeStore(userDefaults: userDefaults)

    XCTAssertFalse(store.continuousSpellCheckingEnabled)
  }

  // Prevents the new-note default from resetting to blank across launches.
  func testLoadingNewNoteDefaultFromDefaults() {
    let userDefaults = makeUserDefaults()
    userDefaults.set(NewNoteDefault.copyPrevious.rawValue, forKey: "sceal.newNoteDefault")

    let store = makeStore(userDefaults: userDefaults)

    XCTAssertEqual(store.newNoteDefault, .copyPrevious)
  }

  // Prevents the calendar weekend visibility toggle from updating UI without persisting the choice.
  func testUpdatingCalendarHidesWeekendsPersistsChoice() throws {
    let userDefaults = makeUserDefaults()
    let store = makeStore(userDefaults: userDefaults)

    store.updateCalendarHidesWeekends(true)

    let data = try XCTUnwrap(
      userDefaults.data(forKey: "sceal.noteAppearanceSettings")
    )
    let persisted = try JSONDecoder().decode(NoteAppearanceSettings.self, from: data)

    XCTAssertTrue(store.appearanceSettings.calendarHidesWeekends)
    XCTAssertTrue(persisted.calendarHidesWeekends)
  }
}
