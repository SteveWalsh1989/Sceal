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

  @State private var displayMode: CalendarDisplayMode = .allTime
  @State private var pendingScrollTargetID: String?

  private var calendarColumns: [GridItem] {
    Array(repeating: GridItem(.flexible(), spacing: 8), count: visibleWeekdays.count)
  }

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
        CalendarHeader(
          displayMode: $displayMode,
          year: store.activeDailyCalendarBrowseYear,
          canBrowseBackward: store.canBrowseCalendarYear(by: -1),
          canBrowseForward: store.canBrowseCalendarYear(by: 1),
          controlColor: themeColors.controlBackground.color,
          accentColor: sidebarAccentColor,
          browseBackward: { store.browseCalendarYear(by: -1) },
          browseForward: { store.browseCalendarYear(by: 1) },
          openToday: openToday
        )

        CalendarWeekdayHeader(
          weekdaySymbols: orderedWeekdaySymbols(),
          columnCount: visibleWeekdays.count,
          dividerColor: themeColors.divider.color
        )

        ScrollViewReader { scrollProxy in
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
              ForEach(displayedMonthSections) { section in
                VStack(alignment: .leading, spacing: 12) {
                  if section.showsYearDivider {
                    CalendarYearDividerView(
                      year: yearText(for: section.monthStartDate),
                      accentColor: sidebarAccentColor,
                      dividerColor: themeColors.divider.color
                    )
                  }

                  let monthStart = section.monthStartDate

                  Text(monthTitle(for: monthStart))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(sidebarAccentColor)

                  LazyVGrid(columns: calendarColumns, spacing: 12) {
                    ForEach(gridCells(for: monthStart)) { cell in
                      if let date = cell.date {
                        let note = store.dailyNote(on: date)

                        CalendarDayButton(
                          date: date,
                          note: note,
                          isSelected: note?.id == store.activeDailySelectedNoteID,
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
                          if let note,
                            !store.isDemoModeEnabled,
                            !store.isStructuredDailyNoteMode
                          {
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
                          .frame(height: CalendarDayLayout.cellHeight)
                      }
                    }
                  }
                }
                .id(monthScrollID(for: section.monthStartDate))
              }
            }
            .padding(.bottom, 20)
          }
          .onChange(of: pendingScrollTargetID) { _, targetID in
            guard let targetID else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
              scrollProxy.scrollTo(targetID, anchor: .top)
            }
            pendingScrollTargetID = nil
          }
        }
        .scrollIndicators(
          store.appearanceSettings.showEditorScrollbar ? .visible : .hidden
        )
      }
    }
  }

  private var displayedMonthSections: [CalendarMonthSection] {
    let monthStartDates = displayedMonthStartDates

    return monthStartDates.enumerated().map { index, monthStart in
      CalendarMonthSection(
        monthStartDate: monthStart,
        showsYearDivider: shouldShowYearDivider(at: index, in: monthStartDates)
      )
    }
  }

  private var displayedMonthStartDates: [Date] {
    switch displayMode {
    case .allTime:
      return allTimeMonthStartDates
    case .year:
      return yearMonthStartDates
    }
  }

  private var allTimeMonthStartDates: [Date] {
    guard let currentMonthStart = monthStart(for: .now) else {
      return []
    }

    let noteMonthStarts = store.dailyNotesForDisplay.compactMap { monthStart(for: $0.date) }
    let firstMonthStart = min(noteMonthStarts.min() ?? currentMonthStart, currentMonthStart)
    let lastMonthStart = max(noteMonthStarts.max() ?? currentMonthStart, currentMonthStart)

    return descendingMonthStartDates(from: lastMonthStart, through: firstMonthStart)
  }

  private var yearMonthStartDates: [Date] {
    (1...12).compactMap { month in
      var components = DateComponents()
      components.calendar = store.calendar
      components.year = store.activeDailyCalendarBrowseYear
      components.month = month
      components.day = 1
      return store.calendar.date(from: components)
    }
  }

  private func monthStart(for date: Date) -> Date? {
    var components = store.calendar.dateComponents([.year, .month], from: date)
    components.calendar = store.calendar
    components.day = 1
    return store.calendar.date(from: components).map { store.calendar.startOfDay(for: $0) }
  }

  private func descendingMonthStartDates(
    from latestMonthStart: Date, through earliestMonthStart: Date
  )
    -> [Date]
  {
    var monthStartDates: [Date] = []
    var currentMonthStart = latestMonthStart

    while currentMonthStart >= earliestMonthStart {
      monthStartDates.append(currentMonthStart)

      guard
        let previousMonthStart = store.calendar.date(
          byAdding: .month,
          value: -1,
          to: currentMonthStart
        ),
        previousMonthStart < currentMonthStart
      else { break }

      currentMonthStart = previousMonthStart
    }

    return monthStartDates
  }

  private func gridCells(for monthStart: Date) -> [CalendarGridCell] {
    guard let dayRange = store.calendar.range(of: .day, in: .month, for: monthStart) else {
      return []
    }

    let monthID = NoteDateFormatters.storageDate.string(from: monthStart)
    let weekdayNumbers = visibleWeekdays.map(\.number)
    let dates = visibleDates(in: dayRange, for: monthStart)
    guard let firstDate = dates.first else { return [] }

    let firstWeekday = store.calendar.component(.weekday, from: firstDate)
    let leadingBlankCount = weekdayNumbers.firstIndex(of: firstWeekday) ?? 0
    var cells = (0..<leadingBlankCount).map { offset in
      CalendarGridCell(id: "\(monthID)-leading-\(offset)", date: nil)
    }

    cells.append(
      contentsOf: dates.map { date in
        CalendarGridCell(
          id: NoteDateFormatters.storageDate.string(from: date),
          date: date
        )
      }
    )

    let cellRemainder = cells.count % weekdayNumbers.count
    let trailingBlankCount = (weekdayNumbers.count - cellRemainder) % weekdayNumbers.count
    cells.append(
      contentsOf: (0..<trailingBlankCount).map { offset in
        CalendarGridCell(id: "\(monthID)-trailing-\(offset)", date: nil)
      }
    )

    return cells
  }

  private func visibleDates(in dayRange: Range<Int>, for monthStart: Date) -> [Date] {
    dayRange.compactMap { day in
      var components = store.calendar.dateComponents([.year, .month], from: monthStart)
      components.day = day
      guard let date = store.calendar.date(from: components),
        shouldShowDate(date, in: monthStart),
        !calendarHidesWeekends || !store.calendar.isDateInWeekend(date)
      else { return nil }

      return date
    }
  }

  private func shouldShowDate(_ date: Date, in monthStart: Date) -> Bool {
    guard displayMode == .allTime,
      let currentMonthStart = self.monthStart(for: .now),
      store.calendar.isDate(monthStart, inSameDayAs: currentMonthStart)
    else { return true }

    return store.calendar.startOfDay(for: date) <= store.calendar.startOfDay(for: .now)
  }

  private func orderedWeekdaySymbols() -> [String] {
    visibleWeekdays.map(\.symbol)
  }

  private var visibleWeekdays: [CalendarWeekday] {
    let weekdays = orderedWeekdays()
    guard calendarHidesWeekends else { return weekdays }
    return weekdays.filter { !$0.isWeekend }
  }

  private func orderedWeekdays() -> [CalendarWeekday] {
    let symbols = store.calendar.shortWeekdaySymbols
    let startIndex = max(store.calendar.firstWeekday - 1, 0)
    let weekdays = symbols.enumerated().map { index, symbol in
      CalendarWeekday(number: index + 1, symbol: symbol)
    }
    return Array(weekdays[startIndex...] + weekdays[..<startIndex])
  }

  private func monthTitle(for date: Date) -> String {
    date.formatted(.dateTime.month(.wide).year())
  }

  private func openToday() {
    store.selectToday()
    if let todayMonthStart = monthStart(for: .now) {
      pendingScrollTargetID = monthScrollID(for: todayMonthStart)
    }
  }

  private func monthScrollID(for monthStart: Date) -> String {
    "calendar-month-\(NoteDateFormatters.storageDate.string(from: monthStart))"
  }

  private func yearText(for date: Date) -> String {
    String(store.calendar.component(.year, from: date))
  }

  private func shouldShowYearDivider(at index: Int, in dates: [Date]) -> Bool {
    guard displayMode == .allTime else { return false }
    guard index > dates.startIndex else { return true }

    let monthStart = dates[index]
    let currentYear = store.calendar.component(.year, from: monthStart)
    let previousYear = store.calendar.component(.year, from: dates[index - 1])
    return currentYear != previousYear
  }

  private var themeColors: ThemeColorSet {
    store.effectiveAppearanceSettings.resolvedColors
  }

  private var sidebarAccentColor: Color {
    Color(nsColor: store.appearanceSettings.accentColor)
  }

  private var calendarHidesWeekends: Bool {
    store.appearanceSettings.calendarHidesWeekends
  }
}

private struct CalendarGridCell: Identifiable {
  let id: String
  let date: Date?
}

private struct CalendarMonthSection: Identifiable {
  let monthStartDate: Date
  let showsYearDivider: Bool

  var id: String {
    NoteDateFormatters.storageDate.string(from: monthStartDate)
  }
}

private struct CalendarWeekday {
  let number: Int
  let symbol: String

  var isWeekend: Bool {
    number == 1 || number == 7
  }
}

private enum CalendarDayLayout {
  static let cellHeight: CGFloat = 58
}

private enum CalendarDisplayMode: CaseIterable {
  case allTime
  case year

  var title: String {
    switch self {
    case .allTime:
      return "All time"
    case .year:
      return "Year"
    }
  }
}

private struct CalendarHeader: View {
  @Binding var displayMode: CalendarDisplayMode
  let year: Int
  let canBrowseBackward: Bool
  let canBrowseForward: Bool
  let controlColor: Color
  let accentColor: Color
  let browseBackward: () -> Void
  let browseForward: () -> Void
  let openToday: () -> Void

  var body: some View {
    VStack(spacing: 8) {
      HStack(spacing: 12) {
        CalendarDisplayModeToggle(
          displayMode: $displayMode,
          controlColor: controlColor,
          accentColor: accentColor
        )

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

      if displayMode == .year {
        HStack(spacing: 10) {
          CalendarHeaderButton(
            systemImage: "chevron.left",
            isEnabled: canBrowseBackward,
            controlColor: controlColor,
            action: browseBackward
          )

          Text(String(year))
            .font(.headline.weight(.semibold))
            .foregroundStyle(accentColor)
            .frame(minWidth: 56)

          CalendarHeaderButton(
            systemImage: "chevron.right",
            isEnabled: canBrowseForward,
            controlColor: controlColor,
            action: browseForward
          )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }
}

private struct CalendarDisplayModeToggle: View {
  @Binding var displayMode: CalendarDisplayMode
  let controlColor: Color
  let accentColor: Color

  var body: some View {
    HStack(spacing: 0) {
      ForEach(CalendarDisplayMode.allCases, id: \.self) { mode in
        Button {
          displayMode = mode
        } label: {
          Text(mode.title)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
              RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(displayMode == mode ? accentColor.opacity(0.15) : Color.clear)
            )
            .foregroundStyle(displayMode == mode ? accentColor : .secondary)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(2)
    .background(controlColor, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
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

private struct CalendarYearDividerView: View {
  let year: String
  let accentColor: Color
  let dividerColor: Color

  var body: some View {
    HStack(spacing: 10) {
      Rectangle()
        .fill(dividerColor)
        .frame(height: 1)

      Text(year)
        .font(.caption.weight(.bold))
        .foregroundStyle(accentColor)
        .fixedSize()

      Rectangle()
        .fill(dividerColor)
        .frame(height: 1)
    }
    .padding(.top, 2)
  }
}

private struct CalendarWeekdayHeader: View {
  let weekdaySymbols: [String]
  let columnCount: Int
  let dividerColor: Color

  var body: some View {
    VStack(spacing: 8) {
      LazyVGrid(
        columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columnCount),
        spacing: 0
      ) {
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
      VStack(spacing: 6) {
        statusIndicator

        Text(dayNumber)
          .font(.system(size: 13, weight: dayFontWeight))
          .foregroundStyle(dayForegroundColor)
      }
      .frame(maxWidth: .infinity)
      .frame(height: CalendarDayLayout.cellHeight)
      .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(cellBackgroundColor)
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

  @ViewBuilder
  private var statusIndicator: some View {
    if hasNote {
      Image(systemName: "checkmark")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(accentColor)
        .frame(height: 18)
    } else {
      Image(systemName: "plus")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(emptyIconColor)
        .frame(height: 18)
    }
  }

  private var dayNumber: String {
    String(Calendar.current.component(.day, from: date))
  }

  private var cellBackgroundColor: Color {
    if isSelected {
      return selectedCardColor
    }

    if isToday {
      return accentColor.opacity(0.14)
    }

    return controlColor.opacity(hasNote ? 0.32 : 0.42)
  }

  private var emptyIconColor: Color {
    isSelected || isToday ? accentColor : .secondary
  }

  private var dayForegroundColor: Color {
    if isSelected || isToday {
      return accentColor
    }

    return hasNote ? .primary : .secondary
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
