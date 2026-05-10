#if DEBUG
  import XCTest

  @testable import Sceal

  @MainActor
  final class NotesStorePlanAccessTests: NotesStoreTestCase {
    // Store defaults to paid so existing debug and release behavior stays feature-complete.
    func testStoreDefaultsToPaidPlan() {
      let store = makeStore(userDefaults: makeUserDefaults())

      XCTAssertEqual(store.activePlan, .paid)
      XCTAssertTrue(store.hasAccess(to: .additionalTemplates))
      XCTAssertTrue(store.hasAccess(to: .customThemeColors))
      XCTAssertTrue(store.hasAccess(to: .automaticBackupSchedules))
    }

    // Developer overrides persist locally so repeated test launches keep the selected plan.
    func testDeveloperPlanOverridePersistsInDebugDefaults() {
      let userDefaults = makeUserDefaults()
      let store = makeStore(userDefaults: userDefaults)

      store.updateDeveloperPlan(.free)
      let reloadedStore = makeStore(userDefaults: userDefaults)

      XCTAssertEqual(reloadedStore.activePlan, .free)
    }

    // Free blocks new templates after the included template without deleting stored templates.
    func testFreePlanBlocksAdditionalTemplateCreationWithoutDeletingTemplates() {
      let store = makeStore(userDefaults: makeUserDefaults())
      let existingTemplateCount = store.noteTemplates.count

      store.updateDeveloperPlan(.free)
      let createdTemplateID = store.createNoteTemplateIfAllowed()

      XCTAssertNil(createdTemplateID)
      XCTAssertEqual(store.noteTemplates.count, existingTemplateCount)
      XCTAssertNotNil(store.userMessage)
    }

    // Free keeps only the included template available to slash commands.
    func testFreePlanFiltersSlashCommandTemplates() {
      let store = makeStore(userDefaults: makeUserDefaults())
      let paidTemplateID = store.createNoteTemplate()

      store.updateDeveloperPlan(.free)

      XCTAssertEqual(store.accessibleNoteTemplates.map(\.id), ["starter-meeting"])
      XCTAssertEqual(store.enabledSlashCommandTemplates().map(\.id), ["starter-meeting"])
      XCTAssertTrue(store.isNoteTemplateLockedByPlan(paidTemplateID))
    }

    // Free ignores saved custom theme colors at runtime without deleting them.
    func testFreePlanPreservesButDoesNotApplyCustomThemeColors() {
      let store = makeStore(userDefaults: makeUserDefaults())
      let customEditorBackground = ThemeColor(red: 0.10, green: 0.20, blue: 0.30)
      let attemptedFreeEditorBackground = ThemeColor(red: 0.60, green: 0.20, blue: 0.10)

      store.updateColorOverride { colors in
        colors.editorBackground = customEditorBackground
      }
      store.updateDeveloperPlan(.free)
      store.updateColorOverride { colors in
        colors.editorBackground = attemptedFreeEditorBackground
      }

      XCTAssertEqual(
        store.appearanceSettings.colorOverrides?.editorBackground,
        customEditorBackground
      )
      XCTAssertNil(store.effectiveAppearanceSettings.colorOverrides)
      XCTAssertEqual(
        store.effectiveAppearanceSettings.resolvedColors.editorBackground,
        AppTheme.defaultDark.colors.editorBackground
      )
      XCTAssertNotNil(store.userMessage)

      store.updateDeveloperPlan(.paid)

      XCTAssertEqual(
        store.effectiveAppearanceSettings.resolvedColors.editorBackground,
        customEditorBackground
      )
    }

    // Free can use two themes per mode and preserves paid theme choices for later.
    func testFreePlanPreservesButDoesNotApplyPremiumThemeSelection() {
      let store = makeStore(userDefaults: makeUserDefaults())

      store.updateThemeID(AppTheme.charcoal.id)
      store.updateDeveloperPlan(.free)

      XCTAssertEqual(store.appearanceSettings.themeID, AppTheme.charcoal.id)
      XCTAssertEqual(store.effectiveAppearanceSettings.themeID, AppTheme.defaultDark.id)
      XCTAssertTrue(store.isThemeLockedByPlan(AppTheme.charcoal.id))
      XCTAssertFalse(store.isThemeLockedByPlan(AppTheme.midnight.id))

      store.updateThemeID(AppTheme.slate.id)

      XCTAssertEqual(store.appearanceSettings.themeID, AppTheme.charcoal.id)
      XCTAssertNotNil(store.userMessage)

      store.updateDeveloperPlan(.paid)

      XCTAssertEqual(store.effectiveAppearanceSettings.themeID, AppTheme.charcoal.id)
    }

    // Free preserves stored backup settings but treats paid schedules as manual at runtime.
    func testFreePlanUsesManualBackupScheduleWithoutMutatingStoredSchedule() {
      let store = makeStore(userDefaults: makeUserDefaults())
      store.updateBackupSchedule(.daily)

      store.updateDeveloperPlan(.free)
      store.updateBackupSchedule(.weekly)

      XCTAssertEqual(store.backupSettings.schedule, .daily)
      XCTAssertEqual(store.effectiveBackupSchedule, .manualOnly)
      XCTAssertEqual(store.availableBackupSchedules, [.manualOnly])
      XCTAssertNotNil(store.userMessage)
    }

    // Free cannot enable inactive-window backups, but it does not clear the stored preference.
    func testFreePlanBlocksInactiveBackupEnableWithoutDeletingStoredPreference() {
      let store = makeStore(userDefaults: makeUserDefaults())
      store.updateBackupOnInactive(false)

      store.updateDeveloperPlan(.free)
      store.updateBackupOnInactive(true)

      XCTAssertFalse(store.backupSettings.backupOnInactive)
      XCTAssertFalse(store.isBackupOnInactiveAvailable)
      XCTAssertNotNil(store.userMessage)
    }

    // Free can use the included template as a default but not templates beyond the limit.
    func testFreePlanBlocksLockedTemplateAsNewNoteDefaultWithoutDeletingStoredChoice() {
      let userDefaults = makeUserDefaults()
      let store = makeStore(userDefaults: userDefaults)
      let paidTemplateID = store.createNoteTemplate()

      store.updateDeveloperPlan(.free)
      store.updateNewNoteDefault(.template("starter-meeting"))

      XCTAssertEqual(store.newNoteDefault, .template("starter-meeting"))
      XCTAssertEqual(store.effectiveNewNoteDefault, .template("starter-meeting"))

      store.updateNewNoteDefault(.template(paidTemplateID))

      XCTAssertEqual(store.newNoteDefault, .template("starter-meeting"))
      XCTAssertNotNil(store.userMessage)

      store.updateDeveloperPlan(.paid)
      store.updateNewNoteDefault(.template(paidTemplateID))
      store.updateDeveloperPlan(.free)

      XCTAssertEqual(store.newNoteDefault, .template(paidTemplateID))
      XCTAssertEqual(store.effectiveNewNoteDefault, .blank)
    }
  }
#endif
