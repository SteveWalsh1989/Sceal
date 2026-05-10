//
//  SettingsThemesView.swift
//

// Settings panel for choosing themes and customizing color tokens.

import SwiftUI

// Settings panel for choosing built-in themes and customizing individual color tokens.
struct SettingsThemesView: View {
  @ObservedObject var store: NotesStore

  // Whether the user has customized colors beyond the base theme.
  private var hasOverrides: Bool {
    store.appearanceSettings.colorOverrides != nil
  }

  // The color set currently applied after plan gates.
  private var resolvedColors: ThemeColorSet {
    store.effectiveAppearanceSettings.resolvedColors
  }

  private var canCustomizeColors: Bool {
    store.hasAccess(to: .customThemeColors)
  }

  private var hasLockedCustomColors: Bool {
    hasOverrides && !canCustomizeColors
  }

  private var customThemeLockTitle: String {
    "Custom colors require Paid"
  }

  private var customThemeLockMessage: String {
    "Free uses built-in themes. Paid unlocks fully custom theme colors, additional templates, and automatic backup schedules."
  }

  var body: some View {
    Form {
      Section("Dark Themes") {
        ThemeGrid(
          themes: AppTheme.darkThemes(),
          selectedID: store.appearanceSettings.themeID
        ) { theme in
          store.updateThemeID(theme.id)
        }
      }

      Section("Light Themes") {
        ThemeGrid(
          themes: AppTheme.lightThemes(),
          selectedID: store.appearanceSettings.themeID
        ) { theme in
          store.updateThemeID(theme.id)
        }
      }

      Section {
        VStack(alignment: .leading, spacing: 14) {
          HStack {
            let activeTheme = AppTheme.builtIn(id: store.appearanceSettings.themeID)
            Label(
              "Theme: \(activeTheme?.displayName ?? "Custom")",
              systemImage: activeTheme?.mode == .light ? "sun.max.fill" : "moon.fill"
            )
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)

            Spacer()

            if hasOverrides {
              Button("Reset to Theme Defaults") {
                store.resetColorOverrides()
              }
              .controlSize(.small)
            }
          }

          if hasLockedCustomColors {
            UpgradeLockedStatus(
              text: "Custom colors are saved but inactive in Free.",
              capability: .customThemeColors,
              title: customThemeLockTitle,
              message: customThemeLockMessage
            )
          } else if !canCustomizeColors {
            UpgradeLockedBanner(
              capability: .customThemeColors,
              title: customThemeLockTitle,
              message: customThemeLockMessage
            )
          }

          ColorTokenRow(
            label: "Sidebar background",
            color: resolvedColors.sidebarBackground,
            isLocked: !canCustomizeColors,
            lockTitle: customThemeLockTitle,
            lockMessage: customThemeLockMessage
          ) {
            color in
            store.updateColorOverride { $0.sidebarBackground = color }
          }

          ColorTokenRow(
            label: "Editor background",
            color: resolvedColors.editorBackground,
            isLocked: !canCustomizeColors,
            lockTitle: customThemeLockTitle,
            lockMessage: customThemeLockMessage
          ) {
            color in
            store.updateColorOverride { $0.editorBackground = color }
          }

          ColorTokenRow(
            label: "Selected card",
            color: resolvedColors.selectedCard,
            isLocked: !canCustomizeColors,
            lockTitle: customThemeLockTitle,
            lockMessage: customThemeLockMessage
          ) { color in
            store.updateColorOverride { $0.selectedCard = color }
          }

          ColorTokenRow(
            label: "Unselected card",
            color: resolvedColors.unselectedCard,
            isLocked: !canCustomizeColors,
            lockTitle: customThemeLockTitle,
            lockMessage: customThemeLockMessage
          ) { color in
            store.updateColorOverride { $0.unselectedCard = color }
          }

          ColorTokenRow(
            label: "Section card fill",
            color: resolvedColors.sectionCardFill,
            isLocked: !canCustomizeColors,
            lockTitle: customThemeLockTitle,
            lockMessage: customThemeLockMessage
          ) {
            color in
            store.updateColorOverride { $0.sectionCardFill = color }
          }

          ColorTokenRow(
            label: "Control background",
            color: resolvedColors.controlBackground,
            isLocked: !canCustomizeColors,
            lockTitle: customThemeLockTitle,
            lockMessage: customThemeLockMessage
          ) {
            color in
            store.updateColorOverride { $0.controlBackground = color }
          }

          ColorTokenRow(
            label: "Divider",
            color: resolvedColors.divider,
            isLocked: !canCustomizeColors,
            lockTitle: customThemeLockTitle,
            lockMessage: customThemeLockMessage
          ) { color in
            store.updateColorOverride { $0.divider = color }
          }

          ColorTokenRow(
            label: "Note body border",
            color: resolvedColors.noteBodyBorder,
            isLocked: !canCustomizeColors,
            lockTitle: customThemeLockTitle,
            lockMessage: customThemeLockMessage
          ) { color in
            store.updateColorOverride { $0.noteBodyBorder = color }
          }
        }
      } header: {
        Text("Customize Colors")
      }
    }
    .formStyle(.grouped)
    .scrollContentBackground(.hidden)
  }
}

// Horizontal row of mini theme preview cards.
private struct ThemeGrid: View {
  let themes: [AppTheme]
  let selectedID: String
  let onSelect: (AppTheme) -> Void

  var body: some View {
    HStack(spacing: 12) {
      ForEach(themes) { theme in
        ThemePreviewCard(
          theme: theme,
          isSelected: theme.id == selectedID
        ) {
          onSelect(theme)
        }
      }
    }
  }
}

// Mini preview card showing sidebar/editor color split with the theme name.
private struct ThemePreviewCard: View {
  let theme: AppTheme
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 6) {
        HStack(spacing: 0) {
          Rectangle()
            .fill(theme.colors.sidebarBackground.color)
            .frame(width: 30)

          Rectangle()
            .fill(theme.colors.editorBackground.color)
        }
        .frame(width: 72, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(
              isSelected ? Color.accentColor : Color.primary.opacity(0.15),
              lineWidth: isSelected ? 2 : 1
            )
        )

        Text(theme.displayName)
          .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
          .foregroundStyle(isSelected ? .primary : .secondary)
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Use \(theme.displayName) theme")
  }
}

// Single row with a label and a ColorPicker for one theme color token.
private struct ColorTokenRow: View {
  let label: String
  let color: ThemeColor
  let isLocked: Bool
  let lockTitle: String
  let lockMessage: String
  let onChange: (ThemeColor) -> Void

  @State private var pickerColor: Color

  init(
    label: String,
    color: ThemeColor,
    isLocked: Bool,
    lockTitle: String,
    lockMessage: String,
    onChange: @escaping (ThemeColor) -> Void
  ) {
    self.label = label
    self.color = color
    self.isLocked = isLocked
    self.lockTitle = lockTitle
    self.lockMessage = lockMessage
    self.onChange = onChange
    self._pickerColor = State(initialValue: color.color)
  }

  var body: some View {
    HStack {
      Text(label)
        .font(.system(size: 12, weight: .medium))

      Spacer()

      if isLocked {
        UpgradeLockIndicator(
          capability: .customThemeColors,
          title: lockTitle,
          message: lockMessage
        )
      }

      ColorPicker("", selection: $pickerColor, supportsOpacity: true)
        .labelsHidden()
        .frame(width: 44)
        .disabled(isLocked)
        .opacity(isLocked ? 0.45 : 1)
    }
    .onChange(of: pickerColor) { _, newColor in
      guard !isLocked else {
        pickerColor = color.color
        return
      }
      let resolved =
        NSColor(newColor).usingColorSpace(.sRGB)
        ?? NSColor(newColor)
      onChange(ThemeColor(nsColor: resolved))
    }
    .onChange(of: color) { _, newThemeColor in
      pickerColor = newThemeColor.color
    }
  }
}
