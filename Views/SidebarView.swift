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
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 14) {
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
        .padding(.bottom, 24)
      }
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 16)
    .background(Color.primary.opacity(0.03))
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
    .padding(.top, 8)
  }
}

private struct DayNoteCardView: View {
  let note: DayNote
  let isSelected: Bool

  var body: some View {
    HStack(alignment: .top, spacing: 16) {
      VStack(alignment: .leading, spacing: 8) {
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

      Spacer(minLength: 12)

      VStack(alignment: .trailing, spacing: 4) {
        Text(note.dayNumberText)
          .font(.system(size: 24, weight: .bold, design: .rounded))
          .foregroundStyle(.primary)

        Text(note.weekdayText)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
    .background(cardBackground)
    .overlay(
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .strokeBorder(isSelected ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
    )
    .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
  }

  private var cardBackground: some ShapeStyle {
    isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04)
  }
}
