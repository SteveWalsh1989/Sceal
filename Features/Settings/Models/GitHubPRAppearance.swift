import Foundation

nonisolated enum GitHubPRGroup: String, Codable, Identifiable, CaseIterable {
  case today
  case carriedForward

  var id: String { rawValue }
  var defaultTitle: String { self == .today ? "Opened today" : "Carried forward" }
}

// Display preferences are independent of the historical records owned by notes.
nonisolated struct GitHubPRAppearance: Codable, Equatable {
  var title = "PRs"
  var titleColorName = "pink"
  var firstGroup: GitHubPRGroup = .today
  var todayLabel = "Opened today"
  var carriedForwardLabel = "Carried forward"
  var hidesEmptyGroups = true

  var displayedTitle: String {
    title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "PRs" : title
  }
  var orderedGroups: [GitHubPRGroup] {
    firstGroup == .today ? [.today, .carriedForward] : [.carriedForward, .today]
  }

  // Empty labels fall back while editing so headings never disappear accidentally.
  func label(for group: GitHubPRGroup) -> String {
    let label = group == .today ? todayLabel : carriedForwardLabel
    return label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? group.defaultTitle : label
  }
}
