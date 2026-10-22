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
