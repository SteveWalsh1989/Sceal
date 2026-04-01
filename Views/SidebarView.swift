//
//  SidebarView.swift
//  dayra
//
//  Created by Steve Walsh on 01/04/2026.
//

import SwiftUI

struct SidebarView: View {
  @ObservedObject var store: NoteStore

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      header

      Divider()

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
    .padding(.vertical, 20)
    .background(Color.primary.opacity(0.03))
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text("dayra")
            .font(.title2.weight(.bold))

          Text("Daily notes")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer()

        Button {
          store.selectToday()
        } label: {
          Image(systemName: "calendar.badge.plus")
        }
        .buttonStyle(.bordered)
        .help("Open today's note")
      }

      Text("A single vertical history with clear month breaks and one note per day.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
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

        Text(note.id)
          .font(.caption)
          .foregroundStyle(.secondary)
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
    .overlay(alignment: .bottomLeading) {
      RoundedRectangle(cornerRadius: 999, style: .continuous)
        .fill(isSelected ? Color.accentColor : Color.accentColor.opacity(0.35))
        .frame(width: isSelected ? 124 : 84, height: 3)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
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
