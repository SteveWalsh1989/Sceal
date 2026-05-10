import Foundation
import XCTest

@testable import Sceal

@MainActor
final class NoteTemplatesStoreTests: NotesStoreTestCase {
  // Keeps generated template commands unique after moving template state out of NotesStore.
  func testCreateTemplateGeneratesUniqueCommandsAndPersistsExistingPayload() throws {
    let userDefaults = makeUserDefaults()
    let store = NoteTemplatesStore(
      settingsRepository: SettingsRepository(userDefaults: userDefaults)
    )

    let firstTemplateID = store.createTemplate()
    let secondTemplateID = store.createTemplate()
    try store.persistTemplates()

    XCTAssertEqual(store.template(withID: firstTemplateID)?.command, "new-template")
    XCTAssertEqual(store.template(withID: secondTemplateID)?.command, "new-template-2")

    let data = try XCTUnwrap(userDefaults.data(forKey: "sceal.noteTemplates"))
    let persistedTemplates = try JSONDecoder().decode([NoteTemplate].self, from: data)
    XCTAssertTrue(persistedTemplates.contains { $0.id == firstTemplateID })
    XCTAssertTrue(persistedTemplates.contains { $0.id == secondTemplateID })
  }

  // Prevents imported templates from duplicating local commands after store extraction.
  func testMergeImportedTemplatesNormalizesAndReplacesByCommand() throws {
    let userDefaults = makeUserDefaults()
    let store = NoteTemplatesStore(
      settingsRepository: SettingsRepository(userDefaults: userDefaults)
    )
    let imported = NoteTemplate(
      id: "imported-meeting",
      title: "Imported Meeting",
      command: "/Meeting",
      body: "# Imported"
    )

    store.mergeImportedTemplates([imported])
    try store.persistTemplates()

    let meetingTemplates = store.templates.filter { $0.command == "meeting" }
    XCTAssertEqual(meetingTemplates.map(\.id), ["imported-meeting"])
    XCTAssertEqual(meetingTemplates.first?.body, "# Imported")
  }

  // Keeps command validation owned by the template store while matching existing messages.
  func testCommandValidationRejectsReservedAndDuplicateCommands() {
    let userDefaults = makeUserDefaults()
    let store = NoteTemplatesStore(
      settingsRepository: SettingsRepository(userDefaults: userDefaults)
    )
    let firstTemplateID = store.createTemplate()
    let secondTemplateID = store.createTemplate()

    store.mutateTemplate(id: firstTemplateID) { $0.command = "div" }
    XCTAssertEqual(
      store.commandValidationMessage(for: firstTemplateID),
      "This command is reserved by Scéal."
    )

    store.mutateTemplate(id: firstTemplateID) { $0.command = "shared" }
    store.mutateTemplate(id: secondTemplateID) { $0.command = "shared" }
    XCTAssertEqual(
      store.commandValidationMessage(for: firstTemplateID),
      "This command is already used by another template."
    )
  }
}
