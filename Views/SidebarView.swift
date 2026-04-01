//
//  SidebarView.swift
//  dayra
//
//

import SwiftUI

struct SidebarView: View {
  @ObservedObject var store: NoteStore

  var body: some View {
    Group {
      if store.monthSections.isEmpty {
        SidebarEmptyStateView()
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 12) {
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
  }
}

// Shown when no notes exist yet — keeps the sidebar from feeling broken on first launch.
private struct SidebarEmptyStateView: View {
  var body: some View {
    VStack(spacing: 10) {
      Image(systemName: "note.text")
        .font(.system(size: 32, weight: .light))
        .foregroundStyle(.tertiary)

      Text("No notes yet")
        .font(.headline)
        .foregroundStyle(.secondary)

      Text("Press Today to start writing")
        .font(.subheadline)
        .foregroundStyle(.tertiary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
