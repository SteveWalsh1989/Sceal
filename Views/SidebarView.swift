//
//  SidebarView.swift
//
//

import SwiftUI

struct SidebarView: View {
  @ObservedObject var store: NoteStore
  let requestDelete: (DayNote.ID) -> Void

  var body: some View {
    Group {
      if store.monthSections.isEmpty {
        SidebarEmptyStateView {
          store.selectToday()
        }
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 10) {
            if !store.hasTodayNote {
              AddTodayButton {
                store.selectToday()
              }
            }

            ForEach(store.monthSections) { section in
              MonthDividerView(title: section.title)

              ForEach(section.notes) { note in
                Button {
                  store.select(noteID: note.id)
                } label: {
                  DayNoteCardView(
                    note: note,
                    appearanceSettings: store.appearanceSettings,
                    isSelected: store.selectedNoteID == note.id
                  )
                }
                .buttonStyle(.plain)
                .contextMenu {
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
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
    .background(Color.primary.opacity(0.03))
    .background {
      // Captures arrow keys at the AppKit level when the editor isn't first responder.
      SidebarKeyboardHelper(
        onUpArrow: { store.selectNextNote() },
        onDownArrow: { store.selectPreviousNote() }
      )
    }
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
        Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
    .buttonStyle(.plain)
    .foregroundStyle(Color.accentColor)
  }
}

private struct MonthDividerView: View {
  let title: String

  var body: some View {
    HStack(spacing: 10) {
      Rectangle()
        .fill(Color.primary.opacity(0.12))
        .frame(height: 1)

      Text(title)
        .font(.caption.weight(.bold))
        .foregroundStyle(Color.accentColor)
        .fixedSize()

      Rectangle()
        .fill(Color.primary.opacity(0.12))
        .frame(height: 1)
    }
    .padding(.top, 4)
  }
}

private struct DayNoteCardView: View {
  let note: DayNote
  let appearanceSettings: NoteAppearanceSettings
  let isSelected: Bool

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      VStack(alignment: .leading, spacing: 4) {
        Text(note.displayTitle)
          .font(.system(size: titleFontSize, weight: .semibold))
          .multilineTextAlignment(.leading)
          .lineLimit(2)
          .foregroundStyle(.primary)

        HStack(spacing: 8) {
          Text(note.sidebarDateText(using: appearanceSettings.sidebarDateFormat))
            .lineLimit(1)

          if appearanceSettings.sidebarShowsTags, !note.sidebarTagsText.isEmpty {
            Spacer(minLength: 6)

            Text(note.sidebarTagsText)
              .lineLimit(1)
              .truncationMode(.tail)
          }
        }
        .font(.system(size: metadataFontSize, weight: .medium))
        .foregroundStyle(.secondary)
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
        .strokeBorder(isSelected ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
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
    isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04)
  }
}
