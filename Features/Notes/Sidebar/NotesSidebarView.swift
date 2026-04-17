//
//  NotesSidebarView.swift
//
//

// Monthly-grouped note list with keyboard navigation and empty state.

import SwiftUI

struct NotesSidebarView: View {
  @ObservedObject var store: NotesStore
  let requestDelete: (DayNote.ID) -> Void
  let requestChangeDate: (DayNote.ID) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Group {
        switch store.sidebarMode {
        case .calendar:
          DailyCalendarSidebarContent(
            store: store,
            requestDelete: requestDelete,
            requestChangeDate: requestChangeDate
          )
        case .daily:
          dailySidebarContent
        case .list:
          ListNotesSidebarContent(
            store: store,
            requestDelete: requestDelete
          )
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
    .safeAreaInset(edge: .bottom, spacing: 0) {
      SidebarModeToggle(
        mode: $store.sidebarMode,
        accentColor: sidebarAccentColor
      )
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .frame(maxWidth: .infinity)
      .background(sidebarBackgroundColor)
    }
    .background(sidebarBackgroundColor)
    .background {
      SidebarKeyboardHelper(
        onUpArrow: {
          switch store.sidebarMode {
          case .calendar, .daily: store.selectNextNote()
          case .list: store.selectNextListNote()
          }
        },
        onDownArrow: {
          switch store.sidebarMode {
          case .calendar, .daily: store.selectPreviousNote()
          case .list: store.selectPreviousListNote()
          }
        }
      )
    }
  }

  // Daily mode sidebar content — the original monthly-grouped note list.
  @ViewBuilder
  private var dailySidebarContent: some View {
    let monthSections = store.monthSections

    if monthSections.isEmpty, store.isSearchActive {
      VStack {
        Spacer()
        Text("No matching notes")
          .font(.subheadline.weight(.medium))
          .foregroundStyle(.secondary)
        Spacer()
      }
      .frame(maxWidth: .infinity)
    } else if monthSections.isEmpty {
      SidebarEmptyStateView {
        store.selectToday()
      }
    } else {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 10) {
          if !store.hasTodayNote, !store.isSearchActive {
            AddTodayButton(accentColor: sidebarAccentColor) {
              store.selectToday()
            }
          }

          ForEach(monthSections) { section in
            MonthDividerView(
              title: section.title,
              accentColor: sidebarAccentColor,
              dividerColor: themeColors.divider.color
            )

            ForEach(section.notes) { note in
              Button {
                store.select(noteID: note.id)
              } label: {
                DayNoteCardView(
                  note: note,
                  appearanceSettings: store.appearanceSettings,
                  isSelected: store.selectedNoteID == note.id,
                  accentColor: sidebarAccentColor,
                  selectedCardColor: themeColors.selectedCard.color,
                  unselectedCardColor: themeColors.unselectedCard.color,
                  searchText: store.searchText
                )
              }
              .buttonStyle(.plain)
              .contextMenu {
                Button {
                  requestChangeDate(note.id)
                } label: {
                  Label("Change date…", systemImage: "calendar")
                }

                Button(role: .destructive) {
                  requestDelete(note.id)
                } label: {
                  Label("Delete note…", systemImage: "trash")
                }
              }
            }
          }
        }
        .padding(.bottom, 20)
      }
      .scrollIndicators(
        store.appearanceSettings.showEditorScrollbar ? .visible : .hidden
      )
    }
  }

  // Resolved color set from the active theme.
  private var themeColors: ThemeColorSet {
    store.appearanceSettings.resolvedColors
  }

  // Background color from the active theme.
  private var sidebarBackgroundColor: Color {
    themeColors.sidebarBackground.color
  }

  // Uses the saved appearance accent instead of the app-level default tint.
  private var sidebarAccentColor: Color {
    Color(nsColor: store.appearanceSettings.accentColor)
  }
}

// Installs a local event monitor for arrow keys that only fires when
// no NSTextView is the first responder, bridging the gap between SwiftUI
// focus and AppKit's responder chain.
private struct SidebarKeyboardHelper: NSViewRepresentable {
  let onUpArrow: () -> Void
  let onDownArrow: () -> Void

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    context.coordinator.install(onUpArrow: onUpArrow, onDownArrow: onDownArrow)
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    context.coordinator.onUpArrow = onUpArrow
    context.coordinator.onDownArrow = onDownArrow
  }

  func makeCoordinator() -> Coordinator { Coordinator() }

  static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
    coordinator.uninstall()
  }

  class Coordinator {
    var onUpArrow: (() -> Void)?
    var onDownArrow: (() -> Void)?
    private var monitor: Any?

    func install(onUpArrow: @escaping () -> Void, onDownArrow: @escaping () -> Void) {
      self.onUpArrow = onUpArrow
      self.onDownArrow = onDownArrow
      monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        guard let self else { return event }
        // Only handle arrows when the sidebar is the relevant context.
        let responder = event.window?.firstResponder
        if responder is NSTextView || responder is NSTableView { return event }
        switch event.keyCode {
        case 126:  // up arrow
          self.onUpArrow?()
          return nil
        case 125:  // down arrow
          self.onDownArrow?()
          return nil
        default:
          return event
        }
      }
    }

    func uninstall() {
      if let monitor { NSEvent.removeMonitor(monitor) }
      monitor = nil
    }
  }
}

// Shown when no notes exist yet — keeps the sidebar from feeling broken on first launch.
private struct SidebarEmptyStateView: View {
  let addToday: () -> Void

  var body: some View {
    VStack(spacing: 10) {
      Image(systemName: "note.text")
        .font(.system(size: 32, weight: .light))
        .foregroundStyle(.tertiary)

      Text("No notes yet")
        .font(.headline)
        .foregroundStyle(.secondary)

      Button(action: addToday) {
        Label("Add today", systemImage: "plus")
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

// Appears at the top of the sidebar when today has no note, so the user can manually create one.
private struct AddTodayButton: View {
  let accentColor: Color
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Image(systemName: "plus")
          .font(.system(size: 12, weight: .semibold))

        Text("Add today")
          .font(.system(size: 13, weight: .medium))
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 8)
      .background(
        accentColor.opacity(0.1),
        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
      )
    }
    .buttonStyle(.plain)
    .foregroundStyle(accentColor)
  }
}

private struct MonthDividerView: View {
  let title: String
  let accentColor: Color
  let dividerColor: Color

  var body: some View {
    HStack(spacing: 10) {
      Rectangle()
        .fill(dividerColor)
        .frame(height: 1)

      Text(title)
        .font(.caption.weight(.bold))
        .foregroundStyle(accentColor)
        .fixedSize()

      Rectangle()
        .fill(dividerColor)
        .frame(height: 1)
    }
    .padding(.top, 4)
  }
}

private struct DayNoteCardView: View {
  let note: DayNote
  let appearanceSettings: NoteAppearanceSettings
  let isSelected: Bool
  let accentColor: Color
  let selectedCardColor: Color
  let unselectedCardColor: Color
  let searchText: String

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      VStack(alignment: .leading, spacing: 4) {
        Text(highlighted(note.displayTitle))
          .font(.system(size: titleFontSize, weight: .semibold))
          .multilineTextAlignment(.leading)
          .lineLimit(2)
          .foregroundStyle(.primary)

        if appearanceSettings.sidebarShowsTags, !note.sidebarTagsText.isEmpty {
          Text(highlighted(note.sidebarTagsText))
            .font(.system(size: metadataFontSize, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
        }

        if let snippet = bodySnippet {
          Text(highlighted(snippet))
            .font(.system(size: snippetFontSize, weight: .regular))
            .foregroundStyle(.tertiary)
            .lineLimit(2)
            .truncationMode(.middle)
        }
      }
      .layoutPriority(1)

      Spacer(minLength: 6)

      VStack(alignment: .trailing, spacing: 4) {
        Text(note.dayNumberText)
          .font(.system(size: dayNumberFontSize, weight: .bold, design: .rounded))
          .monospacedDigit()
          .foregroundStyle(.primary)

        Text(note.weekdayText)
          .font(.system(size: weekdayFontSize, weight: .semibold))
          .foregroundStyle(.secondary)
      }
      .frame(minWidth: 34, alignment: .trailing)
    }
    .padding(.horizontal, 13)
    .padding(.vertical, 10)
    .background(
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .fill(cardBackground)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .strokeBorder(isSelected ? accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
    )
    .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
  }

  private var titleFontSize: CGFloat {
    appearanceSettings.sidebarFontSize
  }

  private var metadataFontSize: CGFloat {
    max(appearanceSettings.sidebarFontSize - 3, 10)
  }

  private var weekdayFontSize: CGFloat {
    max(appearanceSettings.sidebarFontSize - 4, 9)
  }

  private var dayNumberFontSize: CGFloat {
    appearanceSettings.sidebarFontSize + 6
  }

  private var cardBackground: Color {
    isSelected ? selectedCardColor : unselectedCardColor
  }

  private var snippetFontSize: CGFloat {
    max(appearanceSettings.sidebarFontSize - 4, 9)
  }

  // Trimmed search query used for matching and highlighting.
  private var query: String {
    searchText.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  // A short excerpt from the body centred around the first match, only shown during search.
  private var bodySnippet: String? {
    let body = NotesStore.searchableBody(note.body)
    guard !query.isEmpty,
      let matchRange = body.range(of: query, options: .caseInsensitive)
    else { return nil }

    let window = 60
    let snippetStart =
      body.index(matchRange.lowerBound, offsetBy: -window, limitedBy: body.startIndex)
      ?? body.startIndex
    let snippetEnd =
      body.index(matchRange.upperBound, offsetBy: window, limitedBy: body.endIndex) ?? body.endIndex

    var snippet = String(body[snippetStart..<snippetEnd])
      .components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
      .joined(separator: " ")

    if snippetStart > body.startIndex { snippet = "…" + snippet }
    if snippetEnd < body.endIndex { snippet += "…" }

    return snippet
  }

  // Returns an AttributedString with all case-insensitive occurrences of the query highlighted.
  private func highlighted(_ text: String) -> AttributedString {
    var attributed = AttributedString(text)
    guard !query.isEmpty else { return attributed }

    var searchStart = text.startIndex
    while searchStart < text.endIndex,
      let matchRange = text.range(
        of: query, options: .caseInsensitive, range: searchStart..<text.endIndex)
    {
      let startOffset = text.distance(from: text.startIndex, to: matchRange.lowerBound)
      let matchLength = text.distance(from: matchRange.lowerBound, to: matchRange.upperBound)
      let attrStart = attributed.index(attributed.startIndex, offsetByCharacters: startOffset)
      let attrEnd = attributed.index(attrStart, offsetByCharacters: matchLength)
      attributed[attrStart..<attrEnd].backgroundColor = accentColor.opacity(0.35)
      searchStart = matchRange.upperBound
    }

    return attributed
  }

}

// Full-width toggle between daily and list sidebar modes, pinned to the bottom of the sidebar.
private struct SidebarModeToggle: View {
  @Binding var mode: SidebarMode
  let accentColor: Color

  var body: some View {
    HStack(spacing: 0) {
      modeButton(.calendar, systemImage: "calendar", label: "Calendar")
      modeButton(.daily, systemImage: "clock.arrow.circlepath", label: "Daily")
      modeButton(.list, systemImage: "list.bullet", label: "Notes")
    }
    .padding(3)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(.quaternary.opacity(0.5))
    )
  }

  @ViewBuilder
  private func modeButton(_ targetMode: SidebarMode, systemImage: String, label: String)
    -> some View
  {
    let isActive = mode == targetMode

    Button {
      mode = targetMode
    } label: {
      HStack(spacing: 5) {
        Image(systemName: systemImage)
          .font(.system(size: 12, weight: .medium))
        Text(label)
          .font(.system(size: 12, weight: .medium))
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 6)
      .contentShape(Rectangle())
      .background(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(isActive ? accentColor.opacity(0.15) : Color.clear)
      )
      .foregroundStyle(isActive ? accentColor : .secondary)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(accessibilityLabel(for: targetMode))
  }

  private func accessibilityLabel(for mode: SidebarMode) -> String {
    switch mode {
    case .calendar:
      return "Calendar view"
    case .daily:
      return "Daily notes"
    case .list:
      return "List notes"
    }
  }
}
