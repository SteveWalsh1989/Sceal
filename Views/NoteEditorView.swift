//
//  NoteEditorView.swift
//

import AppKit
import SwiftUI

struct NoteEditorView: View {
  @Environment(\.openSettings) private var openSettings
  @ObservedObject var store: NoteStore
  let noteID: DayNote.ID
  var sidebarCollapsed: Bool
  let requestDelete: (DayNote.ID) -> Void

  @State private var isShowingAppearancePopover = false
  private let fontPanelController = FontPanelController()

  private var adjacentNoteIDs: (previous: DayNote.ID?, next: DayNote.ID?) {
    store.adjacentNoteIDs(for: noteID)
  }

  var body: some View {
    if let note = store.note(withID: noteID) {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .center, spacing: 12) {
          HStack(spacing: 8) {
            Text(note.editorDateText)
              .font(.callout)
              .foregroundStyle(.secondary)

            if let previousNoteID = adjacentNoteIDs.previous {
              HeaderNavigationButton(
                systemImage: "chevron.left",
                accessibilityLabel: "Open older note",
                controlColor: themeColors.controlBackground.color
              ) {
                store.select(noteID: previousNoteID)
              }
            }

            if let nextNoteID = adjacentNoteIDs.next {
              HeaderNavigationButton(
                systemImage: "chevron.right",
                accessibilityLabel: "Open newer note",
                controlColor: themeColors.controlBackground.color
              ) {
                store.select(noteID: nextNoteID)
              }
            }
          }

          Spacer()

          TextField("Tags", text: store.tagsBinding(for: noteID))
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)

          Button {
            store.selectToday()
          } label: {
            Label("Today", systemImage: "calendar")
          }
          .buttonStyle(.bordered)
          .controlSize(.small)

          HeaderIconButton(
            systemImage: "slider.vertical.3",
            accessibilityLabel: "Open note appearance settings",
            controlColor: themeColors.controlBackground.color
          ) {
            isShowingAppearancePopover.toggle()
          }
          .popover(isPresented: $isShowingAppearancePopover, arrowEdge: .top) {
            QuickAppearancePopover(
              store: store,
              openSettings: {
                isShowingAppearancePopover = false
                openSettings()
              },
              openFontPanel: openFontPanel,
              confirmDelete: {
                isShowingAppearancePopover = false
                requestDelete(noteID)
              }
            )
          }
        }
        .padding(.leading, sidebarCollapsed ? 130 : 0)

        TextField("Title", text: store.titleBinding(for: noteID))
          .textFieldStyle(.plain)
          .font(.system(size: 30, weight: .bold))

        ZStack(alignment: .topLeading) {
          if note.body.isEmpty {
            Text("Start writing today's note here.")
              .foregroundStyle(.secondary)
              .padding(.horizontal, 34)
              .padding(.vertical, 30)
              .allowsHitTesting(false)
          }

          MarkdownTextView(
            noteID: noteID,
            text: store.bodyBinding(for: noteID),
            appearanceSettings: store.appearanceSettings
          )
        }
        .background(
          RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(noteBodyShellColor)
        )
        .overlay(
          RoundedRectangle(cornerRadius: 26, style: .continuous)
            .strokeBorder(noteBodyBorderColor, lineWidth: 1)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .padding(.horizontal, 24)
      .padding(.bottom, 24)
      .padding(.top, 12)
      .onDisappear {
        fontPanelController.detachIfNeeded()
      }
    } else {
      ContentUnavailableView(
        "Note unavailable",
        systemImage: "square.and.pencil",
        description: Text("Select another day from the sidebar.")
      )
    }
  }

  private func openFontPanel() {
    fontPanelController.present(using: store.appearanceSettings) { selectedFontName in
      store.updateBodyFontName(selectedFontName)
    }
  }

  private var themeColors: ThemeColorSet {
    store.appearanceSettings.resolvedColors
  }

  private var noteBodyShellColor: Color {
    themeColors.editorBackground.color
  }

  private var noteBodyBorderColor: Color {
    themeColors.noteBodyBorder.color
  }
}

// Keeps header note-jump actions compact and visually aligned with the date.
private struct HeaderNavigationButton: View {
  let systemImage: String
  let accessibilityLabel: String
  let controlColor: Color
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
        .frame(width: 24, height: 24)
        .background(controlColor, in: RoundedRectangle(cornerRadius: 8))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(accessibilityLabel)
  }
}

// Keeps header utility actions visually aligned with the navigation buttons.
private struct HeaderIconButton: View {
  let systemImage: String
  let accessibilityLabel: String
  let controlColor: Color
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.secondary)
        .frame(width: 28, height: 28)
        .background(controlColor, in: RoundedRectangle(cornerRadius: 8))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(accessibilityLabel)
  }
}

private struct QuickAppearancePopover: View {
  @ObservedObject var store: NoteStore
  let openSettings: () -> Void
  let openFontPanel: () -> Void
  let confirmDelete: () -> Void

  private var controlBackgroundColor: Color {
    store.appearanceSettings.resolvedColors
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

      QuickAppearanceSliderRow(
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

      QuickAppearanceSliderRow(
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

      QuickAppearanceSliderRow(
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

      QuickAppearanceSliderRow(
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

      QuickAppearanceSliderRow(
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

      QuickAppearanceColorRow(
        selectedColorName: store.appearanceSettings.accentColorName,
        onSelect: store.updateAccentColorName
      )

      Divider()

      QuickNewNoteDefaultRow(
        selection: store.newNoteDefault,
        onSelect: store.updateNewNoteDefault
      )

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

private struct QuickAppearanceSliderRow: View {
  let title: String
  let valueLabel: String
  @Binding var value: Double
  let range: ClosedRange<Double>
  let step: Double

  var body: some View {
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

private struct QuickAppearanceColorRow: View {
  let selectedColorName: String
  let onSelect: (String) -> Void

  var body: some View {
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
        ForEach(ScealPalette.colors, id: \.name) { entry in
          Button {
            onSelect(entry.name)
          } label: {
            Circle()
              .fill(Color(nsColor: entry.color))
              .frame(width: 18, height: 18)
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

private struct QuickNewNoteDefaultRow: View {
  let selection: NewNoteDefault
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
        ForEach(NewNoteDefault.allCases, id: \.self) { option in
          Text(option.displayName).tag(option)
        }
      }
      .labelsHidden()
      .pickerStyle(.menu)
      .controlSize(.small)
      .fixedSize()
    }
  }
}
