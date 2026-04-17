//
//  DailyCalendarSidebarContent.swift
//
//

// Calendar-grid alternative for browsing daily notes across older years.

import SwiftUI

struct DailyCalendarSidebarContent: View {
  @ObservedObject var store: NotesStore
  let requestDelete: (DayNote.ID) -> Void
  let requestChangeDate: (DayNote.ID) -> Void

  private let calendarColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)

  var body: some View {
    let filteredNoteIDs = store.filteredDailyNoteIDs

    if store.isSearchActive, filteredNoteIDs.isEmpty {
      VStack {
        Spacer()
        Text("No matching notes")
          .font(.subheadline.weight(.medium))
          .foregroundStyle(.secondary)
        Spacer()
      }
      .frame(maxWidth: .infinity)
    } else {
      VStack(alignment: .leading, spacing: 14) {
        CalendarYearHeader(
          year: store.calendarBrowseYear,
          canBrowseBackward: store.canBrowseCalendarYear(by: -1),
          canBrowseForward: store.canBrowseCalendarYear(by: 1),
          controlColor: themeColors.controlBackground.color,
          accentColor: sidebarAccentColor,
          browseBackward: { store.browseCalendarYear(by: -1) },
          browseForward: { store.browseCalendarYear(by: 1) },
          openToday: { store.selectToday() }
        )

        CalendarWeekdayHeader(
          weekdaySymbols: orderedWeekdaySymbols(),
          dividerColor: themeColors.divider.color
        )

        ScrollView {
          LazyVStack(alignment: .leading, spacing: 24) {
            ForEach(monthStartDates, id: \.self) { monthStart in
              VStack(alignment: .leading, spacing: 12) {
                Text(monthTitle(for: monthStart))
                  .font(.headline.weight(.semibold))
                  .foregroundStyle(.secondary)

                LazyVGrid(columns: calendarColumns, spacing: 12) {
                  ForEach(gridCells(for: monthStart)) { cell in
                    if let date = cell.date {
                      let note = store.dailyNote(on: date)

                      CalendarDayButton(
                        date: date,
                        note: note,
                        isSelected: note?.id == store.selectedNoteID,
                        isToday: store.calendar.isDateInToday(date),
                        isSearchActive: store.isSearchActive,
                        isSearchMatch: note.map { filteredNoteIDs.contains($0.id) } ?? false,
                        accentColor: sidebarAccentColor,
                        controlColor: themeColors.controlBackground.color,
                        selectedCardColor: themeColors.selectedCard.color,
                        openDate: {
                          store.openDailyDate(date)
                        }
                      )
                      .contextMenu {
                        if let note {
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
                    } else {
                      Color.clear
                        .frame(height: 58)
                    }
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
  }

  private var monthStartDates: [Date] {
    (1...12).compactMap { month in
      var components = DateComponents()
      components.calendar = store.calendar
      components.year = store.calendarBrowseYear
      components.month = month
      components.day = 1
      return store.calendar.date(from: components)
    }
  }

  private func gridCells(for monthStart: Date) -> [CalendarGridCell] {
    guard let dayRange = store.calendar.range(of: .day, in: .month, for: monthStart) else {
      return []
    }

    let monthID = NoteDateFormatters.storageDate.string(from: monthStart)
    let firstWeekday = store.calendar.component(.weekday, from: monthStart)
    let leadingBlankCount = (firstWeekday - store.calendar.firstWeekday + 7) % 7
    var cells = (0..<leadingBlankCount).map { offset in
      CalendarGridCell(id: "\(monthID)-leading-\(offset)", date: nil)
    }

    for day in dayRange {
      var components = store.calendar.dateComponents([.year, .month], from: monthStart)
      components.day = day
      if let date = store.calendar.date(from: components) {
        cells.append(
          CalendarGridCell(
            id: NoteDateFormatters.storageDate.string(from: date),
            date: date
          )
        )
      }
    }

    let trailingBlankCount = (7 - (cells.count % 7)) % 7
    cells.append(
      contentsOf: (0..<trailingBlankCount).map { offset in
        CalendarGridCell(id: "\(monthID)-trailing-\(offset)", date: nil)
      }
    )

    return cells
  }

  private func orderedWeekdaySymbols() -> [String] {
    let weekdaySymbols = store.calendar.shortWeekdaySymbols
    let startIndex = max(store.calendar.firstWeekday - 1, 0)
    return Array(weekdaySymbols[startIndex...] + weekdaySymbols[..<startIndex])
  }

  private func monthTitle(for date: Date) -> String {
    date.formatted(.dateTime.month(.wide).year())
  }

  private var themeColors: ThemeColorSet {
    store.appearanceSettings.resolvedColors
  }

  private var sidebarAccentColor: Color {
    Color(nsColor: store.appearanceSettings.accentColor)
  }
}

private struct CalendarGridCell: Identifiable {
  let id: String
  let date: Date?
}

private struct CalendarYearHeader: View {
  let year: Int
  let canBrowseBackward: Bool
  let canBrowseForward: Bool
  let controlColor: Color
  let accentColor: Color
  let browseBackward: () -> Void
  let browseForward: () -> Void
  let openToday: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      HStack(spacing: 10) {
        CalendarHeaderButton(
          systemImage: "chevron.left",
          isEnabled: canBrowseBackward,
          controlColor: controlColor,
          action: browseBackward
        )

        Text(String(year))
          .font(.headline.weight(.semibold))
          .frame(minWidth: 56)

        CalendarHeaderButton(
          systemImage: "chevron.right",
          isEnabled: canBrowseForward,
          controlColor: controlColor,
          action: browseForward
        )
      }

      Spacer()

      Button(action: openToday) {
        Text("Today")
          .font(.system(size: 13, weight: .semibold))
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .background(controlColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
      .buttonStyle(.plain)
      .foregroundStyle(accentColor)
    }
  }
}

private struct CalendarHeaderButton: View {
  let systemImage: String
  let isEnabled: Bool
  let controlColor: Color
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.system(size: 11, weight: .semibold))
        .frame(width: 24, height: 24)
        .background(controlColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain)
    .foregroundStyle(.secondary)
    .disabled(!isEnabled)
    .opacity(isEnabled ? 1 : 0.35)
  }
}

private struct CalendarWeekdayHeader: View {
  let weekdaySymbols: [String]
  let dividerColor: Color

  var body: some View {
    VStack(spacing: 8) {
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 0)
      {
        ForEach(weekdaySymbols, id: \.self) { weekday in
          Text(weekday)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
        }
      }

      Rectangle()
        .fill(dividerColor.opacity(0.6))
        .frame(height: 1)
    }
  }
}

private struct CalendarDayButton: View {
  let date: Date
  let note: DayNote?
  let isSelected: Bool
  let isToday: Bool
  let isSearchActive: Bool
  let isSearchMatch: Bool
  let accentColor: Color
  let controlColor: Color
  let selectedCardColor: Color
  let openDate: () -> Void

  private var hasNote: Bool {
    note != nil
  }

  var body: some View {
    Button(action: openDate) {
      VStack(spacing: 5) {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(statusBackgroundColor)
          .overlay {
            Image(systemName: hasNote ? "checkmark" : "plus")
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(statusForegroundColor)
          }
          .frame(height: 26)

        Text(dayNumber)
          .font(.system(size: 13, weight: dayFontWeight))
          .foregroundStyle(dayForegroundColor)

        Circle()
          .fill(dotColor)
          .frame(width: 4, height: 4)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 6)
      .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(isSelected ? selectedCardColor : Color.clear)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .strokeBorder(accentColor.opacity(isToday ? 0.55 : 0), lineWidth: 1)
      )
      .opacity(contentOpacity)
      .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(accessibilityLabel)
  }

  private var dayNumber: String {
    String(Calendar.current.component(.day, from: date))
  }

  private var statusBackgroundColor: Color {
    if isSelected {
      return accentColor.opacity(0.28)
    }

    return hasNote ? controlColor.opacity(0.95) : controlColor.opacity(0.5)
  }

  private var statusForegroundColor: Color {
    if isSelected || isToday {
      return accentColor
    }

    return hasNote ? .primary : .secondary
  }

  private var dayForegroundColor: Color {
    if isSelected || isToday {
      return accentColor
    }

    return hasNote ? .primary : .secondary
  }

  private var dotColor: Color {
    if isSelected || isToday {
      return accentColor
    }

    return hasNote ? Color.secondary.opacity(0.75) : Color.secondary.opacity(0.3)
  }

  private var dayFontWeight: Font.Weight {
    hasNote || isToday ? .semibold : .medium
  }

  private var contentOpacity: Double {
    guard isSearchActive else { return 1 }
    if isSelected || isSearchMatch { return 1 }
    return hasNote ? 0.32 : 0.16
  }

  private var accessibilityLabel: String {
    let dateLabel = date.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
    if hasNote {
      return "Open note for \(dateLabel)"
    }

    return "Create note for \(dateLabel)"
  }
}
