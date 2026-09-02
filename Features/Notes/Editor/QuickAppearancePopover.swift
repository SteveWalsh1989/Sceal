//
//  QuickAppearancePopover.swift
//

// Shared compact appearance controls used by legacy and structured note headers.

import SwiftUI

struct QuickAppearancePopover: View {
  @ObservedObject var store: NotesStore
  let showsStructuredSectionControls: Bool
  let openSettings: () -> Void
  let openFontPanel: () -> Void
  let confirmDelete: () -> Void
  let allowsDelete: Bool

  private var controlBackgroundColor: Color {
    store.effectiveAppearanceSettings.resolvedColors
      .controlBackground.color
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(spacing: 12) {
        Text("Appearance")
          .font(.system(size: 14, weight: .semibold))

        Spacer()

        Button(action: openSettings) {
          Image(systemName: "gearshape")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 28, height: 28)
            .background(controlBackgroundColor, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("App settings")
        .help("App settings")
      }

      QuickAppearanceFontRow(
        fontName: store.appearanceSettings.bodyFontDisplayName,
        openFontPanel: openFontPanel
      )

      AppearanceSliderRow(
        style: .compact,
        title: "Font size",
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
        style: .compact,
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

      AppearanceSliderRow(
        style: .compact,
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

      AppearanceSliderRow(
        style: .compact,
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

      AppearanceSliderRow(
        style: .compact,
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

      AppearanceAccentColorRow(
        style: .compact,
        selectedColorName: store.appearanceSettings.accentColorName,
        onSelect: store.updateAccentColorName
      )

      if showsStructuredSectionControls {
        Toggle(
          "Highlight focused section border",
          isOn: Binding(
            get: { store.appearanceSettings.highlightsFocusedSectionBorder },
            set: { store.updateHighlightsFocusedSectionBorder($0) }
          )
        )
        .font(.system(size: 12, weight: .medium))
        .toggleStyle(.switch)
        .controlSize(.small)
      }

      Divider()

      QuickNewNoteDefaultRow(
        selection: store.effectiveNewNoteDefault,
        templates: store.accessibleNoteTemplates,
        onSelect: store.updateNewNoteDefault
      )

      if allowsDelete {
        Divider()

        Button(role: .destructive, action: confirmDelete) {
          HStack(spacing: 8) {
            Image(systemName: "trash")
            Text("Delete note…")
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.red)
        .padding(.top, 2)
      }
    }
    .padding(20)
    .frame(width: 332)
  }
}

private struct QuickAppearanceFontRow: View {
  let fontName: String
  let openFontPanel: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        Text("Font")
          .font(.system(size: 12, weight: .medium))

        Spacer()

        Text(fontName)
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
      }

      Button("Choose Font…", action: openFontPanel)
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
  }
}

private struct QuickNewNoteDefaultRow: View {
  let selection: NewNoteDefault
  let templates: [NoteTemplate]
  let onSelect: (NewNoteDefault) -> Void

  var body: some View {
    HStack {
      Text("New note default")
        .font(.system(size: 12, weight: .medium))

      Spacer()

      Picker(
        "",
        selection: Binding(
          get: { selection },
          set: { onSelect($0) }
        )
      ) {
        ForEach(NewNoteDefault.builtInCases, id: \.self) { option in
          Text(option.displayName).tag(option)
        }

        if !templates.isEmpty {
          Section("Templates") {
            ForEach(templates) { template in
              Text(templateLabel(for: template))
                .tag(NewNoteDefault.template(template.id))
            }
          }
        }
      }
      .labelsHidden()
      .pickerStyle(.menu)
      .controlSize(.small)
      .fixedSize()
    }
  }

  private func templateLabel(for template: NoteTemplate) -> String {
    let title = template.title.isEmpty ? "Untitled Template" : template.title
    return template.command.isEmpty ? title : "\(title) (\(template.slashCommand))"
  }
}
