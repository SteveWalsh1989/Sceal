import Foundation

// A value owned by one daily note, never a reference to mutable GitHub state.
nonisolated struct GitHubPRSnapshot: Codable, Equatable, Sendable {
  var entries: [GitHubPREntry] = []
  var refreshedAt: Date?
  var account: String?

  // Retains completed work on its completion day and drops it from subsequent days.
  func refreshed(
    with incoming: [GitHubPREntry], on date: Date, at now: Date,
    account: String, calendar: Calendar = .current
  ) -> Self {
    let start = calendar.startOfDay(for: date)
    let end = calendar.date(byAdding: .day, value: 1, to: start)!
    var byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
    for entry in incoming { byID[entry.id] = entry }
    let relevant = byID.values.filter {
      $0.createdAt < end && ($0.closedAt == nil || $0.closedAt! >= start)
    }.sorted { $0.createdAt > $1.createdAt }
    return Self(entries: relevant, refreshedAt: now, account: account)
  }

  // A new note carries only unfinished entries; the source snapshot stays untouched.
  func carriedForward() -> Self {
    Self(entries: entries.filter { $0.closedAt == nil }, account: account)
  }

  var markdown: String {
    "## PRs\n\n"
      + entries.map {
        "- [\($0.title.replacingOccurrences(of: "]", with: "\\]"))](\($0.url.absoluteString)) - \($0.status)"
      }.joined(separator: "\n")
  }
}

nonisolated struct GitHubPREntry: Codable, Equatable, Identifiable, Sendable {
  var id: Int
  var number: Int
  var title: String
  var repository: String
  var url: URL
  var createdAt: Date
  var closedAt: Date?
  var mergedAt: Date?
  var isDraft: Bool

  var status: String {
    if mergedAt != nil { return "Merged" }
    if closedAt != nil { return "Closed" }
    return isDraft ? "Draft" : "Open"
  }
}

extension StructuredNoteSection {
  static let githubMarker = "<!-- sceal:github-prs -->"
  var isGitHubSection: Bool {
    githubSnapshot != nil
      || markdown.trimmingCharacters(in: .whitespacesAndNewlines) == Self.githubMarker
  }
}

extension GitHubPRSectionLayout {
  // Unranked PRs appear first after a refresh; saved ranks remain stable for existing work.
  func orderedEntries(_ entries: [GitHubPREntry]) -> [GitHubPREntry] {
    let ranks = Dictionary(
      (manualOrder ?? []).enumerated().map { ($0.element, $0.offset) },
      uniquingKeysWith: { first, _ in first })
    return entries.sorted { left, right in
      switch sortOrder ?? .newest {
      case .newest: break
      case .alphabetical:
        let comparison = left.title.localizedStandardCompare(right.title)
        if comparison != .orderedSame { return comparison == .orderedAscending }
      case .manual:
        let leftRank = ranks[left.id] ?? -1
        let rightRank = ranks[right.id] ?? -1
        if leftRank != rightRank { return leftRank < rightRank }
      }
      return left.createdAt == right.createdAt
        ? left.id > right.id : left.createdAt > right.createdAt
    }
  }

  // A drop changes order within its date group without moving PRs between historical categories.
  mutating func moveEntry(
    _ entryID: Int, to targetID: Int, entries: [GitHubPREntry], date: Date,
    calendar: Calendar = .current
  ) -> Bool {
    guard sortOrder == .manual, entryID != targetID,
      let source = entries.first(where: { $0.id == entryID }),
      let target = entries.first(where: { $0.id == targetID }),
      calendar.isDate(source.createdAt, inSameDayAs: date)
        == calendar.isDate(target.createdAt, inSameDayAs: date)
    else { return false }
    var ordered = orderedEntries(entries).map(\.id)
    guard let targetIndex = ordered.firstIndex(of: targetID) else { return false }
    ordered.removeAll { $0 == entryID }
    ordered.insert(entryID, at: min(targetIndex, ordered.count))
    manualOrder = ordered
    return true
  }
}
