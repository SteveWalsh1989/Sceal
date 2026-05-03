//
//  NotesStore+Appearance.swift
//

// NotesStore extension for appearance setting update methods.

import Foundation

// MARK: - Appearance Settings

extension NotesStore {

  // Each method below updates a single appearance property and persists the change.
  func updateBodyFontName(_ bodyFontName: String) {
    updateAppearanceSettings { settings in
      settings.bodyFontName = bodyFontName
    }
  }

  func updateBodyFontSize(_ bodyFontSize: CGFloat) {
    updateAppearanceSettings { settings in
      settings.bodyFontSize = bodyFontSize
    }
  }

  func updateLineHeight(_ lineHeight: CGFloat) {
    updateAppearanceSettings { settings in
      settings.lineHeight = lineHeight
    }
  }

  func updateListItemSpacing(_ listItemSpacing: CGFloat) {
    updateAppearanceSettings { settings in
      settings.listItemSpacing = listItemSpacing
    }
  }

  func updateBulletSize(_ bulletSize: CGFloat) {
    updateAppearanceSettings { settings in
      settings.bulletSize = bulletSize
    }
  }

  func updateSectionDividerGapScale(_ sectionDividerGapScale: CGFloat) {
    updateAppearanceSettings { settings in
      settings.sectionDividerGapScale = sectionDividerGapScale
    }
  }

  func updateSidebarFontSize(_ sidebarFontSize: CGFloat) {
    updateAppearanceSettings { settings in
      settings.sidebarFontSize = sidebarFontSize
    }
  }

  func updateShowEditorScrollbar(_ showEditorScrollbar: Bool) {
    updateAppearanceSettings { settings in
      settings.showEditorScrollbar = showEditorScrollbar
    }
  }

  func updateAccentColorName(_ accentColorName: String) {
    updateAppearanceSettings { settings in
      settings.accentColorName = accentColorName
    }
  }

  func updateSidebarShowsTags(_ sidebarShowsTags: Bool) {
    updateAppearanceSettings { settings in
      settings.sidebarShowsTags = sidebarShowsTags
    }
  }

  func updateSidebarDateFormat(_ sidebarDateFormat: SidebarDateFormat) {
    updateAppearanceSettings { settings in
      settings.sidebarDateFormat = sidebarDateFormat
    }
  }

  func updateCalendarHidesWeekends(_ calendarHidesWeekends: Bool) {
    updateAppearanceSettings { settings in
      settings.calendarHidesWeekends = calendarHidesWeekends
    }
  }

  // Selects a built-in theme and clears any custom overrides.
  func updateThemeID(_ id: String) {
    updateAppearanceSettings { settings in
      settings.themeID = id
      settings.colorOverrides = nil
    }
  }

  // Applies a custom color override, copying from the built-in theme on first edit.
  func updateColorOverride(mutate: (inout ThemeColorSet) -> Void) {
    updateAppearanceSettings { settings in
      var colors = settings.resolvedColors
      mutate(&colors)
      settings.colorOverrides = colors
    }
  }

  // Resets custom color overrides so the built-in theme colors apply again.
  func resetColorOverrides() {
    updateAppearanceSettings { settings in
      settings.colorOverrides = nil
    }
  }

}
