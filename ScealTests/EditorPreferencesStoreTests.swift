import Foundation
import XCTest

@testable import Sceal

@MainActor
final class EditorPreferencesStoreTests: NotesStoreTestCase {
  // Keeps new installs on the existing defaults while moving preferences out of NotesStore.
  func testLoadsDefaultEditorPreferences() {
    let store = EditorPreferencesStore(
      settingsRepository: SettingsRepository(userDefaults: makeUserDefaults())
    )

    XCTAssertTrue(store.continuousSpellCheckingEnabled)
    XCTAssertEqual(store.newNoteDefault, .blank)
  }

  // Preserves the existing UserDefaults keys for editor behavior preferences.
  func testUpdatesPersistToExistingDefaultsKeys() {
    let userDefaults = makeUserDefaults()
    let store = EditorPreferencesStore(
      settingsRepository: SettingsRepository(userDefaults: userDefaults)
    )

    store.updateContinuousSpellCheckingEnabled(false)
    store.updateNewNoteDefault(.copyPrevious)

    XCTAssertFalse(store.continuousSpellCheckingEnabled)
    XCTAssertEqual(store.newNoteDefault, .copyPrevious)
    XCTAssertEqual(
      userDefaults.object(forKey: "sceal.continuousSpellCheckingEnabled") as? Bool,
      false
    )
    XCTAssertEqual(userDefaults.string(forKey: "sceal.newNoteDefault"), "copyPrevious")
  }

  // Preserves template-backed daily note defaults after store extraction.
  func testLoadsTemplateBackedNewNoteDefault() {
    let userDefaults = makeUserDefaults()
    userDefaults.set(false, forKey: "sceal.continuousSpellCheckingEnabled")
    userDefaults.set("template:starter-meeting", forKey: "sceal.newNoteDefault")

    let store = EditorPreferencesStore(
      settingsRepository: SettingsRepository(userDefaults: userDefaults)
    )

    XCTAssertFalse(store.continuousSpellCheckingEnabled)
    XCTAssertEqual(store.newNoteDefault, .template("starter-meeting"))
  }
}
