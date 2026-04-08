//
//  ListNoteCardView.swift
//

// Sidebar card for a list note — similar to DayNoteCardView but without the day number column.

import SwiftUI

struct ListNoteCardView: View {
  let note: DayNote
  let appearanceSettings: NoteAppearanceSettings
  let isSelected: Bool
  let accentColor: Color
  let selectedCardColor: Color
  let unselectedCardColor: Color
  let searchText: String

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(highlighted(note.displayTitle))
        .font(.system(size: titleFontSize, weight: .semibold))
        .multilineTextAlignment(.leading)
        .lineLimit(2)
        .foregroundStyle(.primary)

      HStack(spacing: 8) {
        Text(note.sidebarDateText(using: appearanceSettings.sidebarDateFormat))
          .lineLimit(1)

        if appearanceSettings.sidebarShowsTags, !note.sidebarTagsText.isEmpty {
          Spacer(minLength: 6)

          Text(highlighted(note.sidebarTagsText))
            .lineLimit(1)
            .truncationMode(.tail)
        }
      }
      .font(.system(size: metadataFontSize, weight: .medium))
      .foregroundStyle(.secondary)

      if let snippet = bodySnippet {
        Text(highlighted(snippet))
          .font(.system(size: snippetFontSize, weight: .regular))
          .foregroundStyle(.tertiary)
          .lineLimit(2)
          .truncationMode(.middle)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
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

  private var snippetFontSize: CGFloat {
    max(appearanceSettings.sidebarFontSize - 4, 9)
  }

  private var cardBackground: Color {
    isSelected ? selectedCardColor : unselectedCardColor
  }

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
      body.index(matchRange.upperBound, offsetBy: window, limitedBy: body.endIndex)
      ?? body.endIndex

    var snippet =
      String(body[snippetStart..<snippetEnd])
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
