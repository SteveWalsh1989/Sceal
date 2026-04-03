//
//  ThemesSettingsView.swift
//

import SwiftUI

// Settings panel for choosing built-in themes and customizing individual color tokens.
struct ThemesSettingsView: View {
  @ObservedObject var store: NoteStore

  private var hasOverrides: Bool {
    store.appearanceSettings.colorOverrides != nil
  }

  private var resolvedColors: ThemeColorSet {
    store.appearanceSettings.resolvedColors
  }

  var body: some View {
    Form {
      Section("Dark Themes") {
        ThemeGrid(
          themes: ScealTheme.darkThemes(),
          selectedID: store.appearanceSettings.themeID
        ) { theme in
          store.updateThemeID(theme.id)
        }
      }

      Section("Light Themes") {
        ThemeGrid(
          themes: ScealTheme.lightThemes(),
          selectedID: store.appearanceSettings.themeID
        ) { theme in
          store.updateThemeID(theme.id)
        }
      }

      Section {
        VStack(alignment: .leading, spacing: 14) {
          HStack {
            let activeTheme = ScealTheme.builtIn(id: store.appearanceSettings.themeID)
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

          ColorTokenRow(label: "Sidebar background", color: resolvedColors.sidebarBackground) {
            color in
            store.updateColorOverride { $0.sidebarBackground = color }
          }

          ColorTokenRow(label: "Editor background", color: resolvedColors.editorBackground) {
            color in
            store.updateColorOverride { $0.editorBackground = color }
          }

          ColorTokenRow(label: "Selected card", color: resolvedColors.selectedCard) { color in
            store.updateColorOverride { $0.selectedCard = color }
          }

          ColorTokenRow(label: "Unselected card", color: resolvedColors.unselectedCard) { color in
            store.updateColorOverride { $0.unselectedCard = color }
          }

          ColorTokenRow(label: "Section card fill", color: resolvedColors.sectionCardFill) {
            color in
            store.updateColorOverride { $0.sectionCardFill = color }
          }

          ColorTokenRow(label: "Control background", color: resolvedColors.controlBackground) {
            color in
            store.updateColorOverride { $0.controlBackground = color }
          }

          ColorTokenRow(label: "Divider", color: resolvedColors.divider) { color in
            store.updateColorOverride { $0.divider = color }
          }

          ColorTokenRow(label: "Note body border", color: resolvedColors.noteBodyBorder) { color in
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
  let themes: [ScealTheme]
  let selectedID: String
  let onSelect: (ScealTheme) -> Void

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
  let theme: ScealTheme
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
  let onChange: (ThemeColor) -> Void

  @State private var pickerColor: Color

  init(label: String, color: ThemeColor, onChange: @escaping (ThemeColor) -> Void) {
    self.label = label
    self.color = color
    self.onChange = onChange
    self._pickerColor = State(initialValue: color.color)
  }

  var body: some View {
    HStack {
      Text(label)
        .font(.system(size: 12, weight: .medium))

      Spacer()

      ColorPicker("", selection: $pickerColor, supportsOpacity: true)
        .labelsHidden()
        .frame(width: 44)
    }
    .onChange(of: pickerColor) { _, newColor in
      let resolved = NSColor(newColor).usingColorSpace(.sRGB)
        ?? NSColor(newColor)
      onChange(ThemeColor(nsColor: resolved))
    }
    .onChange(of: color) { _, newThemeColor in
      pickerColor = newThemeColor.color
    }
  }
}
