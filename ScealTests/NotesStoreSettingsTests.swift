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

  // Prevents the starter template from reappearing after the user deletes it.
  func testStarterTemplateSeedsOnlyOnce() throws {
    let userDefaults = makeUserDefaults()
    let store = makeStore(userDefaults: userDefaults)
    let starterID = try XCTUnwrap(store.noteTemplates.first { $0.command == "meeting" }?.id)

    store.deleteNoteTemplate(id: starterID)

    let relaunchedStore = makeStore(userDefaults: userDefaults)

    XCTAssertFalse(relaunchedStore.noteTemplates.contains { $0.command == "meeting" })
  }

  // Prevents generated commands from continuing to follow the title after manual command edits.
  func testTemplateTitleGeneratesCommandUntilManualOverride() {
    let userDefaults = makeUserDefaults()
    let store = makeStore(userDefaults: userDefaults)
    let templateID = store.createNoteTemplate()

    store.templateTitleBinding(for: templateID).wrappedValue = "Meeting Notes"

    XCTAssertEqual(store.noteTemplate(withID: templateID)?.command, "meeting-notes")

    store.templateCommandBinding(for: templateID).wrappedValue = "sync"
    store.templateTitleBinding(for: templateID).wrappedValue = "Weekly Sync"

    XCTAssertEqual(store.noteTemplate(withID: templateID)?.command, "sync")
  }

  // Prevents an empty command edit from snapping back to the generated placeholder value.
  func testTemplateCommandCanBeClearedForValidation() {
    let userDefaults = makeUserDefaults()
    let store = makeStore(userDefaults: userDefaults)
    let templateID = store.createNoteTemplate()

    store.templateCommandBinding(for: templateID).wrappedValue = ""

    XCTAssertEqual(store.noteTemplate(withID: templateID)?.command, "")
    XCTAssertEqual(store.templateCommandValidationMessage(for: templateID), "Enter a command.")
  }

  // Prevents the starter template from storing its final divider inside the compact editor body.
  func testStarterTemplateEndsWithDividerOption() throws {
    let userDefaults = makeUserDefaults()
    let store = makeStore(userDefaults: userDefaults)
    let template = try XCTUnwrap(store.noteTemplates.first { $0.command == "meeting" })

    XCTAssertTrue(template.endsWithDivider)
    XCTAssertFalse(NoteTemplateMarkdown.hasTrailingSectionDivider(in: template.body))
    XCTAssertTrue(
      NoteTemplateMarkdown.hasTrailingSectionDivider(in: template.resolvedBodyForInsertion))
  }

  // Prevents enabling the final-divider option from leaving a duplicate manual divider in the body.
  func testEndingTemplateWithDividerRemovesTrailingBodyDivider() throws {
    let userDefaults = makeUserDefaults()
    let store = makeStore(userDefaults: userDefaults)
    let templateID = store.createNoteTemplate()

    store.templateBodyBinding(for: templateID).wrappedValue = "Body\n\n<!-- section -->"
    store.templateEndsWithDividerBinding(for: templateID).wrappedValue = true

    let template = try XCTUnwrap(store.noteTemplate(withID: templateID))
    XCTAssertEqual(template.body, "Body")
    XCTAssertEqual(template.resolvedBodyForInsertion, "Body\n<!-- section -->")
  }

  // Prevents the single template color from becoming separate per-section color state again.
  func testTemplateSectionColorAppliesToAllDividersOnInsertion() {
    let template = NoteTemplate(
      title: "Meeting",
      command: "meeting",
      body: "<!-- section -->\nBody",
      sectionColorName: "blue",
      endsWithDivider: true
    )

    XCTAssertEqual(
      template.resolvedBodyForInsertion,
      [
        "<!-- section heading:blue bullet:blue usesectioncolor:true -->",
        "Body",
        "<!-- section heading:blue bullet:blue usesectioncolor:true -->",
      ].joined(separator: "\n")
    )
  }

  // Prevents user templates from taking over built-in slash commands.
  func testReservedTemplateCommandShowsValidationMessage() {
    let userDefaults = makeUserDefaults()
    let store = makeStore(userDefaults: userDefaults)
    let templateID = store.createNoteTemplate()

    store.templateCommandBinding(for: templateID).wrappedValue = "div"

    XCTAssertEqual(
      store.templateCommandValidationMessage(for: templateID),
      "This command is reserved by Scéal."
    )
  }

  // Prevents imported templates from duplicating local commands instead of replacing them.
  func testImportedTemplatesOverrideExistingCommands() {
    let userDefaults = makeUserDefaults()
    let store = makeStore(userDefaults: userDefaults)
    let imported = NoteTemplate(
      id: "imported-meeting",
      title: "Imported Meeting",
      command: "meeting",
      body: "# Imported"
    )

    store.mergeImportedNoteTemplates([imported])

    let matchingTemplates = store.noteTemplates.filter { $0.command == "meeting" }
    XCTAssertEqual(matchingTemplates, [imported])
  }

  // Prevents the new-note default picker from updating UI without persisting the choice.
  func testUpdatingNewNoteDefaultPersistsChoice() {
    let userDefaults = makeUserDefaults()
    let store = makeStore(userDefaults: userDefaults)

    store.updateNewNoteDefault(.copyPrevious)

    XCTAssertEqual(store.newNoteDefault, .copyPrevious)
    XCTAssertEqual(userDefaults.string(forKey: "sceal.newNoteDefault"), "copyPrevious")
  }

  // Prevents template-backed note defaults from losing their selected template across launches.
  func testUpdatingNewNoteDefaultPersistsTemplateChoice() {
    let userDefaults = makeUserDefaults()
    let store = makeStore(userDefaults: userDefaults)
    let templateID = store.createNoteTemplate()

    store.updateNewNoteDefault(.template(templateID))

    XCTAssertEqual(store.newNoteDefault, .template(templateID))
    XCTAssertEqual(userDefaults.string(forKey: "sceal.newNoteDefault"), "template:\(templateID)")
  }

  // Prevents deleted templates from leaving the new-note default pointed at a missing template.
  func testDeletingSelectedDefaultTemplateResetsNewNoteDefault() {
    let userDefaults = makeUserDefaults()
    let store = makeStore(userDefaults: userDefaults)
    let templateID = store.createNoteTemplate()

    store.updateNewNoteDefault(.template(templateID))
    store.deleteNoteTemplate(id: templateID)

    XCTAssertEqual(store.newNoteDefault, .blank)
    XCTAssertEqual(userDefaults.string(forKey: "sceal.newNoteDefault"), "blank")
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

  // Prevents the template default storage value from loading as blank on relaunch.
  func testLoadingTemplateNewNoteDefaultFromDefaults() {
    let userDefaults = makeUserDefaults()
    userDefaults.set("template:starter-meeting", forKey: "sceal.newNoteDefault")

    let store = makeStore(userDefaults: userDefaults)

    XCTAssertEqual(store.newNoteDefault, .template("starter-meeting"))
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
