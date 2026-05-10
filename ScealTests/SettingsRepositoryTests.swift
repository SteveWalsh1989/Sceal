import Foundation
import XCTest

@testable import Sceal

@MainActor
final class SettingsRepositoryTests: NotesStoreTestCase {
  // SettingsRepository keeps the current UserDefaults keys and encoded payload shapes.
  func testSavesSettingsToExistingDefaultsKeys() throws {
    let userDefaults = makeUserDefaults()
    let repository = SettingsRepository(userDefaults: userDefaults)
    let appearance = NoteAppearanceSettings(bodyFontSize: 19, lineHeight: 1.4)
    let backupSettings = BackupSettings(
      folderBookmarkData: Data("bookmark".utf8),
      folderDisplayPath: "/tmp/backups",
      schedule: .weekly,
      backupOnInactive: false,
      lastSuccessfulBackupAt: makeDate(year: 2026, month: 5, day: 1),
      lastAttemptedBackupAt: nil,
      lastBackupErrorDescription: nil,
      lastBackupArchiveName: "sceal-backup-auto-2026-05-01-12-00-00.zip",
      lastBackupBytes: 4096
    )
    let template = NoteTemplate(title: "Planning", command: "planning", body: "# Plan")

    try repository.saveAppearanceSettings(appearance)
    repository.saveContinuousSpellCheckingEnabled(false)
    repository.saveNewNoteDefault(.template(template.id))
    repository.saveDeveloperPlan(.free)
    try repository.saveBackupSettings(backupSettings)
    try repository.saveNoteTemplates([template])

    let savedAppearanceData = try XCTUnwrap(
      userDefaults.data(forKey: "sceal.noteAppearanceSettings")
    )
    let savedBackupData = try XCTUnwrap(userDefaults.data(forKey: "sceal.backupSettings"))
    let savedTemplateData = try XCTUnwrap(userDefaults.data(forKey: "sceal.noteTemplates"))
    XCTAssertEqual(
      try JSONDecoder().decode(NoteAppearanceSettings.self, from: savedAppearanceData),
      appearance
    )
    XCTAssertFalse(userDefaults.bool(forKey: "sceal.continuousSpellCheckingEnabled"))
    XCTAssertEqual(userDefaults.string(forKey: "sceal.newNoteDefault"), "template:\(template.id)")
    XCTAssertEqual(userDefaults.string(forKey: "sceal.developer.plan"), "free")
    XCTAssertEqual(
      try JSONDecoder().decode(BackupSettings.self, from: savedBackupData), backupSettings)
    XCTAssertEqual(
      try JSONDecoder().decode([NoteTemplate].self, from: savedTemplateData), [template])
    XCTAssertTrue(userDefaults.bool(forKey: "sceal.noteTemplatesSeeded"))
  }

  // Starter templates seed once, then respect the existing seeded marker.
  func testStarterTemplateSeedsOnlyOnceWithExistingKeys() {
    let userDefaults = makeUserDefaults()
    let repository = SettingsRepository(userDefaults: userDefaults)

    let firstLoad = repository.loadNoteTemplates()
    userDefaults.removeObject(forKey: "sceal.noteTemplates")
    let secondLoad = repository.loadNoteTemplates()

    XCTAssertEqual(firstLoad.map(\.command), ["meeting"])
    XCTAssertTrue(userDefaults.bool(forKey: "sceal.noteTemplatesSeeded"))
    XCTAssertEqual(secondLoad, [])
  }

  // Loading templates preserves the current normalization behavior for legacy payloads.
  func testLoadingTemplatesNormalizesExistingPayload() throws {
    let userDefaults = makeUserDefaults()
    let repository = SettingsRepository(userDefaults: userDefaults)
    let savedTemplate = NoteTemplate(
      title: "Legacy Meeting",
      command: "legacy-meeting",
      body: "<!-- section -->\nBody"
    )
    userDefaults.set(try JSONEncoder().encode([savedTemplate]), forKey: "sceal.noteTemplates")

    let templates = repository.loadNoteTemplates()
    let loadedTemplate = try XCTUnwrap(templates.first)

    XCTAssertTrue(loadedTemplate.startsWithDivider)
    XCTAssertEqual(loadedTemplate.body, "Body")
  }
}
