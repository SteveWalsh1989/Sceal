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
  var showToast: (String, UserMessageKind) -> Void = { _, _ in }
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
              showsStructuredSectionControls: false,
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
            appearanceSettings: store.effectiveAppearanceSettings,
            continuousSpellCheckingEnabled: store.continuousSpellCheckingEnabled,
            searchText: isListMode ? store.listSearchText : store.searchText,
            customSlashTemplates: store.enabledSlashCommandTemplates(),
            libraryRootURL: store.libraryLocation.rootURL,
            imageAttachmentRootURL: store.libraryRepository.attachmentsRootURL,
            onPromptCopied: {
              showToast("Copied", .info)
            }
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
    store.effectiveAppearanceSettings.resolvedColors
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
struct EditorSearchBar: View {
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
struct HeaderNavigationButton: View {
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
