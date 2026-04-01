//
//  SidebarView.swift
//  dayra
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
          LazyVStack(alignment: .leading, spacing: 12) {
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
        .onKeyPress(.upArrow) {
          store.selectNextNote()
          return .handled
        }
        .onKeyPress(.downArrow) {
          store.selectPreviousNote()
          return .handled
        }
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
    .background(Color.primary.opacity(0.03))
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
        .foregroundStyle(.secondary)
        .fixedSize()

      Rectangle()
        .fill(Color.primary.opacity(0.12))
        .frame(height: 1)
    }
    .padding(.top, 6)
  }
}

private struct DayNoteCardView: View {
  let note: DayNote
  let isSelected: Bool

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 6) {
        Text(note.displayTitle)
          .font(.system(size: 16, weight: .semibold))
          .multilineTextAlignment(.leading)
          .lineLimit(2)
          .foregroundStyle(.primary)

        HStack(spacing: 6) {
          Text(note.id)
            .font(.caption)
            .foregroundStyle(.secondary)

          if !note.tags.isEmpty {
            Text(note.tags.joined(separator: ", "))
              .font(.caption)
              .foregroundStyle(.tertiary)
              .lineLimit(1)
          }
        }
      }
      .layoutPriority(1)

      Spacer(minLength: 8)

      VStack(alignment: .trailing, spacing: 4) {
        Text(note.dayNumberText)
          .font(.system(size: 22, weight: .bold, design: .rounded))
          .monospacedDigit()
          .foregroundStyle(.primary)

        Text(note.weekdayText)
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.secondary)
      }
      .frame(minWidth: 34, alignment: .trailing)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .background(cardBackground)
    .overlay(
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .strokeBorder(isSelected ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
    )
    .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
  }

  private var cardBackground: some ShapeStyle {
    isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04)
  }
}
