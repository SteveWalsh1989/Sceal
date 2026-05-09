//
//  NotesEditorView.swift
//

// SwiftUI editor container with header controls, title field, and markdown body.

import AppKit
import SwiftUI

struct NotesEditorView: View {
  @Environment(\.openWindow) private var openWindow
  @ObservedObject var store: NotesStore
  let noteID: DayNote.ID
  var sidebarCollapsed: Bool
  let requestDelete: (DayNote.ID) -> Void

  @State private var isShowingAppearancePopover = false
  @State private var fontPanelController = FontPanelController()

  // Previous/next note IDs for the header navigation arrows.
  private var adjacentNoteIDs: (previous: DayNote.ID?, next: DayNote.ID?) {
    store.adjacentNoteIDs(for: noteID)
  }

  private var isListMode: Bool {
    store.isListModeAvailable && !store.sidebarMode.usesDailyNotes
  }

  // Resolves the current note from either daily or list notes.
  private var currentNote: DayNote? {
    isListMode ? store.listNote(withID: noteID) : store.note(withID: noteID)
  }

  var body: some View {
    if let note = currentNote {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .center, spacing: 12) {
          HStack(spacing: 8) {
            Text(note.editorDateText)
              .font(.callout)
              .foregroundStyle(.secondary)

            if !isListMode {
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
          }

          Spacer()

          TextField("Tags", text: store.activeTagsBinding(for: noteID))
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)

          EditorSearchBar(
            searchText: store.activeSearchTextBinding,
            isExpanded: store.activeSearchBarExpandedBinding,
            controlColor: themeColors.controlBackground.color
          )

          if !isListMode {
            Button {
              store.selectToday()
            } label: {
              Label("Today", systemImage: "calendar")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
          }

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
                openWindow(id: "settings")
              },
              openFontPanel: openFontPanel,
              confirmDelete: {
                isShowingAppearancePopover = false
                requestDelete(noteID)
              },
              allowsDelete: !store.isDemoModeEnabled
            )
          }
        }
        .padding(.leading, sidebarCollapsed ? 130 : 0)

        TextField("Title", text: store.activeTitleBinding(for: noteID), axis: .vertical)
          .textFieldStyle(.plain)
          .font(.system(size: 30, weight: .bold))
          .lineLimit(1...3)

        ZStack(alignment: .topLeading) {
          if note.body.isEmpty {
            Text(isListMode ? "Start writing…" : "Start writing today's note here.")
              .foregroundStyle(.secondary)
              .padding(.horizontal, 34)
              .padding(.vertical, 30)
              .allowsHitTesting(false)
          }

          MarkdownEditorView(
            noteID: noteID,
            text: store.activeBodyBinding(for: noteID),
            appearanceSettings: store.appearanceSettings,
            continuousSpellCheckingEnabled: store.continuousSpellCheckingEnabled,
            searchText: isListMode ? store.listSearchText : store.searchText,
            customSlashTemplates: store.enabledSlashCommandTemplates()
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

  // Opens the system font picker to change the editor body font.
  private func openFontPanel() {
    fontPanelController.present(using: store.appearanceSettings) { selectedFontName in
      store.updateBodyFontName(selectedFontName)
    }
  }

  // Resolved color set from the active theme.
  private var themeColors: ThemeColorSet {
    store.appearanceSettings.resolvedColors
  }

  // Background color for the note body container.
  private var noteBodyShellColor: Color {
    themeColors.editorBackground.color
  }

  // Border color for the note body container.
  private var noteBodyBorderColor: Color {
    themeColors.noteBodyBorder.color
  }
}

// Expandable search bar — shows as a magnifying glass icon, expands into a native NSSearchField on tap.
// The icon always occupies its natural 28pt in the HStack so nothing around it ever shifts.
// When expanded, the native search field appears as a trailing-aligned overlay growing leftward.
private struct EditorSearchBar: View {
  @Binding var searchText: String
  @Binding var isExpanded: Bool
  let controlColor: Color

  private let expandedWidth: CGFloat = 168

  var body: some View {
    // Icon button stays in the layout at 28pt at all times to prevent HStack reflow.
    Button {
      expand()
    } label: {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
        .frame(width: 28, height: 28)
        .background(controlColor, in: RoundedRectangle(cornerRadius: 8))
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Search notes")
    .opacity(isExpanded ? 0 : 1)
    .allowsHitTesting(!isExpanded)
    .overlay(alignment: .trailing) {
      if isExpanded {
        NativeSearchField(text: $searchText, onCollapse: collapse)
          .frame(width: expandedWidth)
          .transition(.opacity)
      }
    }
  }

  private func expand() {
    withAnimation(.easeInOut(duration: 0.2)) {
      isExpanded = true
    }
  }

  private func collapse() {
    withAnimation(.easeInOut(duration: 0.2)) {
      searchText = ""
      isExpanded = false
    }
  }
}

// NSSearchField wrapper — provides the native macOS search field with its built-in
// magnifying glass icon, × clear button, and Escape key handling.
private struct NativeSearchField: NSViewRepresentable {
  @Binding var text: String
  let onCollapse: () -> Void

  func makeNSView(context: Context) -> NSSearchField {
    let field = NSSearchField()
    field.placeholderString = "Search"
    field.delegate = context.coordinator
    field.focusRingType = .none
    // Auto-focus after the view is inserted into the window.
    DispatchQueue.main.async {
      field.window?.makeFirstResponder(field)
    }
    return field
  }

  func updateNSView(_ nsView: NSSearchField, context: Context) {
    context.coordinator.onCollapse = onCollapse
    // Sync external clears (e.g. Escape from SwiftUI) back into the field.
    if nsView.stringValue != text {
      nsView.stringValue = text
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(text: $text, onCollapse: onCollapse)
  }

  @MainActor
  final class Coordinator: NSObject, NSSearchFieldDelegate {
    @Binding var text: String
    var onCollapse: () -> Void

    init(text: Binding<String>, onCollapse: @escaping () -> Void) {
      _text = text
      self.onCollapse = onCollapse
    }

    // Fires on every keystroke.
    func controlTextDidChange(_ obj: Notification) {
      guard let field = obj.object as? NSSearchField else { return }
      text = field.stringValue
    }

    // Fires when the user clicks the built-in × button or presses Escape.
    func searchFieldDidEndSearching(_ sender: NSSearchField) {
      text = ""
      onCollapse()
    }
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
  @ObservedObject var store: NotesStore
  let openSettings: () -> Void
  let openFontPanel: () -> Void
  let confirmDelete: () -> Void
  let allowsDelete: Bool

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

      Divider()

      QuickNewNoteDefaultRow(
        selection: store.newNoteDefault,
        templates: store.sortedNoteTemplates,
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
