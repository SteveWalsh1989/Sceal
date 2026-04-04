//
//  SettingsAppearanceView.swift
//

// Settings panel for font, layout, spacing, and sidebar preferences.

import AppKit
import SwiftUI

struct SettingsAppearanceView: View {
  @ObservedObject var store: NotesStore
  @State private var fontPanelController = FontPanelController()

  var body: some View {
    Form {
      Section("Font") {
        HStack {
          Text(store.appearanceSettings.bodyFontDisplayName)
          Spacer()
          Button("Choose Font\u{2026}") {
            fontPanelController.present(
              using: store.appearanceSettings,
              onChange: store.updateBodyFontName
            )
          }
        }

        AppearanceSliderRow(
          style: .settings,
          title: "Body size",
          valueLabel: "\(Int(store.appearanceSettings.bodyFontSize))",
          value: Binding(
            get: { Double(store.appearanceSettings.bodyFontSize) },
            set: { store.updateBodyFontSize(CGFloat($0)) }
          ),
          range: Double(
            NoteAppearanceSettings.minimumBodyFontSize)...Double(
              NoteAppearanceSettings.maximumBodyFontSize),
          step: 1
        )

        AppearanceSliderRow(
          style: .settings,
          title: "Sidebar size",
          valueLabel: "\(Int(store.appearanceSettings.sidebarFontSize))",
          value: Binding(
            get: { Double(store.appearanceSettings.sidebarFontSize) },
            set: { store.updateSidebarFontSize(CGFloat($0)) }
          ),
          range: Double(
            NoteAppearanceSettings.minimumSidebarFontSize)...Double(
              NoteAppearanceSettings.maximumSidebarFontSize),
          step: 1
        )
      }

      Section("Layout") {
        AppearanceSliderRow(
          style: .settings,
          title: "Line height",
          valueLabel: String(format: "%.2fx", store.appearanceSettings.lineHeight),
          value: Binding(
            get: { Double(store.appearanceSettings.lineHeight) },
            set: { store.updateLineHeight(CGFloat($0)) }
          ),
          range: Double(
            NoteAppearanceSettings.minimumLineHeight)...Double(
              NoteAppearanceSettings.maximumLineHeight),
          step: 0.05
        )

        AppearanceSliderRow(
          style: .settings,
          title: "List spacing",
          valueLabel: String(format: "%.1f", store.appearanceSettings.listItemSpacing),
          value: Binding(
            get: { Double(store.appearanceSettings.listItemSpacing) },
            set: { store.updateListItemSpacing(CGFloat($0)) }
          ),
          range: Double(
            NoteAppearanceSettings.minimumListItemSpacing)...Double(
              NoteAppearanceSettings.maximumListItemSpacing),
          step: 0.25
        )

        AppearanceSliderRow(
          style: .settings,
          title: "Section gap",
          valueLabel: String(format: "%.2fx", store.appearanceSettings.sectionDividerGapScale),
          value: Binding(
            get: { Double(store.appearanceSettings.sectionDividerGapScale) },
            set: { store.updateSectionDividerGapScale(CGFloat($0)) }
          ),
          range: Double(
            NoteAppearanceSettings.minimumSectionDividerGapScale)...Double(
              NoteAppearanceSettings.maximumSectionDividerGapScale),
          step: 0.25
        )

        AppearanceSliderRow(
          style: .settings,
          title: "Bullet size",
          valueLabel: "\(Int(store.appearanceSettings.bulletSize))",
          value: Binding(
            get: { Double(store.appearanceSettings.bulletSize) },
            set: { store.updateBulletSize(CGFloat($0)) }
          ),
          range: Double(
            NoteAppearanceSettings.minimumBulletSize)...Double(
              NoteAppearanceSettings.maximumBulletSize),
          step: 1
        )
      }

      Section("Accent color") {
        AppearanceAccentColorRow(
          style: .settings,
          selectedColorName: store.appearanceSettings.accentColorName,
          onSelect: store.updateAccentColorName
        )
      }

      Section("Sidebar") {
        Toggle(
          "Show tags on sidebar cards",
          isOn: Binding(
            get: { store.appearanceSettings.sidebarShowsTags },
            set: { store.updateSidebarShowsTags($0) }
          )
        )

        Picker(
          "Sidebar date format",
          selection: Binding(
            get: { store.appearanceSettings.sidebarDateFormat },
            set: { store.updateSidebarDateFormat($0) }
          )
        ) {
          ForEach(SidebarDateFormat.allCases, id: \.self) { option in
            Text(option.displayName).tag(option)
          }
        }
        .pickerStyle(.menu)
      }

      Section("Behavior") {
        Picker(
          "New note default",
          selection: Binding(
            get: { store.newNoteDefault },
            set: { store.updateNewNoteDefault($0) }
          )
        ) {
          ForEach(NewNoteDefault.allCases, id: \.self) { option in
            Text(option.displayName).tag(option)
          }
        }
        .pickerStyle(.menu)
      }
    }
    .formStyle(.grouped)
    .onDisappear {
      fontPanelController.detachIfNeeded()
    }
  }
}

// Shared styling variants for appearance controls used in both settings and quick popovers.
enum AppearanceControlRowStyle {
  case settings
  case compact
}

struct AppearanceSliderRow: View {
  let style: AppearanceControlRowStyle
  let title: String
  let valueLabel: String
  @Binding var value: Double
  let range: ClosedRange<Double>
  let step: Double

  var body: some View {
    switch style {
    case .settings:
      LabeledContent(title) {
        HStack(spacing: 4) {
          Text(valueLabel)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .frame(width: 42, alignment: .trailing)
          Slider(value: $value, in: range, step: step)
        }
      }
    case .compact:
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .firstTextBaseline) {
          Text(title)
            .font(.system(size: 12, weight: .medium))

          Spacer()

          Text(valueLabel)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }

        Slider(value: $value, in: range, step: step)
          .controlSize(.small)
          .tint(.accentColor)
      }
    }
  }
}

struct AppearanceAccentColorRow: View {
  let style: AppearanceControlRowStyle
  let selectedColorName: String
  let onSelect: (String) -> Void

  var body: some View {
    switch style {
    case .settings:
      HStack(spacing: 8) {
        colorSwatches(circleSize: 20)
      }
    case .compact:
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .firstTextBaseline) {
          Text("Default color")
            .font(.system(size: 12, weight: .medium))

          Spacer()

          Text(selectedColorName.capitalized)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }

        HStack(spacing: 10) {
          colorSwatches(circleSize: 18)
        }
      }
    }
  }

  @ViewBuilder
  private func colorSwatches(circleSize: CGFloat) -> some View {
    ForEach(ThemePalette.colors, id: \.name) { entry in
      Button {
        onSelect(entry.name)
      } label: {
        Circle()
          .fill(Color(nsColor: entry.color))
          .frame(width: circleSize, height: circleSize)
          .overlay {
            Circle()
              .strokeBorder(
                borderColor(for: entry.name),
                lineWidth: entry.name == selectedColorName ? 2 : 1
              )
          }
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Use \(entry.name) accent color")
    }
  }

  private func borderColor(for colorName: String) -> Color {
    if colorName == selectedColorName {
      return Color.primary
    }
    if colorName == "white" {
      return Color.primary.opacity(0.2)
    }
    return Color.clear
  }
}
