//
//  AppearanceSettingsView.swift
//  dayra
//

import AppKit
import SwiftUI

struct AppearanceSettingsView: View {
  @ObservedObject var store: NoteStore
  @State private var fontPanelController = SettingsFontPanelController()

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

        SliderRow(
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

        SliderRow(
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
        SliderRow(
          title: "Line height",
          valueLabel: String(format: "%.1fx", store.appearanceSettings.lineHeight),
          value: Binding(
            get: { Double(store.appearanceSettings.lineHeight) },
            set: { store.updateLineHeight(CGFloat($0)) }
          ),
          range: Double(
            NoteAppearanceSettings.minimumLineHeight)...Double(
              NoteAppearanceSettings.maximumLineHeight),
          step: 0.1
        )

        SliderRow(
          title: "List spacing",
          valueLabel: String(format: "%.1f", store.appearanceSettings.listItemSpacing),
          value: Binding(
            get: { Double(store.appearanceSettings.listItemSpacing) },
            set: { store.updateListItemSpacing(CGFloat($0)) }
          ),
          range: Double(
            NoteAppearanceSettings.minimumListItemSpacing)...Double(
              NoteAppearanceSettings.maximumListItemSpacing),
          step: 0.5
        )

        SliderRow(
          title: "Bullet size",
          valueLabel: "\(Int(store.appearanceSettings.bulletSize))",
          value: Binding(
            get: { Double(store.appearanceSettings.bulletSize) },
            set: { store.updateBulletSize(CGFloat($0)) }
          ),
          range: Double(
            NoteAppearanceSettings.minimumBulletSize)...Double(
              NoteAppearanceSettings.maximumBulletSize),
          step: 2
        )
      }

      Section("Accent color") {
        AccentColorRow(
          selectedColorName: store.appearanceSettings.accentColorName,
          onSelect: store.updateAccentColorName
        )
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

// MARK: - Private sub-views

private struct SliderRow: View {
  let title: String
  let valueLabel: String
  @Binding var value: Double
  let range: ClosedRange<Double>
  let step: Double

  var body: some View {
    HStack {
      Text(title)
      Spacer()
      Text(valueLabel)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .frame(width: 36, alignment: .trailing)
      Slider(value: $value, in: range, step: step)
        .frame(width: 140)
    }
  }
}

private struct AccentColorRow: View {
  let selectedColorName: String
  let onSelect: (String) -> Void

  var body: some View {
    HStack(spacing: 8) {
      ForEach(DayraPalette.colors, id: \.name) { entry in
        Button {
          onSelect(entry.name)
        } label: {
          Circle()
            .fill(Color(nsColor: entry.color))
            .frame(width: 20, height: 20)
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
