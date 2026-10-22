import Foundation

extension NotesStore {
  // Restores connection feedback without placing the saved token in a view's state.
  func restoreGitHubConnection() async {
    guard githubAccount == nil, !isRefreshingGitHub else { return }
    do {
      guard let token = try GitHubCredentialStore.token() else { return }
      let generation = githubConnectionGeneration
      let user = try await GitHubClient(token: token).user()
      if generation == githubConnectionGeneration { githubAccount = user.login }
    } catch { githubError = error.localizedDescription }
  }

  // Validates before replacing a previously working credential.
  func connectGitHub(token: String) async {
    guard !isRefreshingGitHub else { return }
    isRefreshingGitHub = true
    defer { isRefreshingGitHub = false }
    do {
      let cleanedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !cleanedToken.isEmpty else {
        throw GitHubClientError.message("Enter a GitHub personal access token.")
      }
      let user = try await GitHubClient(token: cleanedToken).user()
      try GitHubCredentialStore.save(cleanedToken)
      githubConnectionGeneration = UUID()
      githubAccount = user.login
      githubError = nil
    } catch { githubError = error.localizedDescription }
  }

  // Keeps historical records when a user disconnects the account.
  func disconnectGitHub() {
    do {
      try GitHubCredentialStore.remove()
      githubConnectionGeneration = UUID()
      githubAccount = nil
      githubError = nil
    } catch { githubError = error.localizedDescription }
  }

  // Applies a complete response to the latest document value, preserving edits made during fetching.
  func refreshGitHub(documentID: String) async {
    guard !isRefreshingGitHub, !isDemoModeEnabled, sidebarMode != .list,
      let original = selectedStructuredNote, original.id == documentID,
      Calendar.current.isDateInToday(original.date), !original.githubSections.isEmpty
    else { return }
    isRefreshingGitHub = true
    defer { isRefreshingGitHub = false }
    let generation = githubConnectionGeneration
    do {
      guard let token = try GitHubCredentialStore.token() else {
        throw GitHubClientError.message("Connect GitHub in Settings to load your PRs.")
      }
      let client = GitHubClient(token: token)
      let user = try await client.user()
      let accounts = original.githubSections.compactMap { $0.githubSnapshot?.account }
      guard accounts.allSatisfy({ $0 == user.login }) else {
        throw GitHubClientError.message(
          "This note belongs to another GitHub account. Connect the original account to refresh it."
        )
      }
      let entries = try await client.entries(
        author: user.login, date: original.date,
        existing: original.githubSections.flatMap { $0.githubSnapshot?.entries ?? [] })
      try Task.checkCancellation()
      guard generation == githubConnectionGeneration, sidebarMode != .list,
        var latest = selectedStructuredNote, latest.id == documentID,
        Calendar.current.isDateInToday(latest.date)
      else { return }
      latest.refreshGitHubSections(entries: entries, account: user.login, now: .now)
      replaceStructuredDocument(latest)
      flushPendingStructuredNoteSave(for: documentID)
      githubAccount = user.login
      githubError = nil
    } catch is CancellationError {
      return
    } catch {
      if generation == githubConnectionGeneration { githubError = error.localizedDescription }
    }
  }
}

extension StructuredNoteDocument {
  var githubSections: [StructuredNoteSection] {
    nodes.flatMap { node -> [StructuredNoteSection] in
      switch node {
      case .section(let section): return [section]
      case .group(let group): return group.sections
      }
    }.filter(\.isGitHubSection)
  }

  // Mutates only integration sections so ordinary note text is never replaced by a network result.
  mutating func refreshGitHubSections(entries: [GitHubPREntry], account: String, now: Date) {
    func refresh(_ section: StructuredNoteSection) -> StructuredNoteSection {
      guard section.isGitHubSection else { return section }
      var updated = section
      updated.githubSnapshot = (section.githubSnapshot ?? GitHubPRSnapshot()).refreshed(
        with: entries, on: date, at: now, account: account)
      return updated
    }
    nodes = nodes.map { node in
      switch node {
      case .section(let section): return .section(refresh(section))
      case .group(var group):
        group.sections = group.sections.map(refresh)
        return .group(group)
      }
    }
  }
}
