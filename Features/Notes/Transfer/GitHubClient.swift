import Foundation
import Security

// Credentials stay outside the note library, backups, and preferences.
enum GitHubCredentialStore {
  private static var query: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "Sceal.GitHub", kSecAttrAccount as String: "personal-access-token",
    ]
  }

  // Reads the token only when a connection or refresh needs it.
  static func token() throws -> String? {
    var request = query
    request[kSecReturnData as String] = true
    var result: CFTypeRef?
    let status = SecItemCopyMatching(request as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = result as? Data,
      let token = String(data: data, encoding: .utf8)
    else { throw GitHubClientError.message("Could not read the GitHub token from Keychain.") }
    return token
  }

  // Updates an existing item without deleting a working credential first.
  static func save(_ token: String) throws {
    let data = Data(token.utf8)
    let status = SecItemUpdate(
      query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    if status == errSecItemNotFound {
      var request = query
      request[kSecValueData as String] = data
      request[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
      guard SecItemAdd(request as CFDictionary, nil) == errSecSuccess else {
        throw GitHubClientError.message("Could not save the GitHub token in Keychain.")
      }
    } else if status != errSecSuccess {
      throw GitHubClientError.message("Could not update the GitHub token in Keychain.")
    }
  }

  // Disconnecting removes credentials while retaining all daily snapshots.
  static func remove() throws {
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw GitHubClientError.message("Could not remove the GitHub token from Keychain.")
    }
  }
}

nonisolated enum GitHubClientError: LocalizedError {
  case message(String)
  var errorDescription: String? {
    switch self {
    case .message(let text): return text
    }
  }
}

nonisolated struct GitHubClient: Sendable {
  let token: String

  struct User: Decodable { let login: String }
  private struct SearchResult: Decodable {
    let totalCount: Int
    let incompleteResults: Bool
    let items: [Issue]
  }
  private struct Issue: Decodable {
    let number: Int
    let repositoryUrl: URL
  }
  private struct Pull: Decodable {
    let id: Int
    let number: Int
    let title: String
    let htmlUrl: URL
    let createdAt: Date
    let closedAt: Date?
    let mergedAt: Date?
    let draft: Bool
    let base: Base
    struct Base: Decodable { let repo: Repository }
    struct Repository: Decodable { let fullName: String }

    var entry: GitHubPREntry {
      GitHubPREntry(
        id: id, number: number, title: title, repository: base.repo.fullName,
        url: htmlUrl, createdAt: createdAt, closedAt: closedAt, mergedAt: mergedAt,
        isDraft: draft)
    }
  }

  // Validates a token and resolves the authenticated author instead of accepting a typed username.
  func user() async throws -> User {
    try await get(URL(string: "https://api.github.com/user")!)
  }

  // Searches all accessible repositories and refuses truncated results rather than saving a partial list.
  func entries(author: String, date: Date, existing: [GitHubPREntry]) async throws
    -> [GitHubPREntry]
  {
    let start = Calendar.current.startOfDay(for: date)
    let formatter = ISO8601DateFormatter()
    let timestamp = formatter.string(from: start)
    var issues: [String: Issue] = [:]
    for entry in existing {
      let repositoryURL = URL(string: "https://api.github.com/repos")!.appendingPathComponent(
        entry.repository)
      issues["\(repositoryURL)/\(entry.number)"] = Issue(
        number: entry.number, repositoryUrl: repositoryURL)
    }
    for filter in ["is:open", "updated:>=\(timestamp)"] {
      var page = 1
      while true {
        var url = URLComponents(string: "https://api.github.com/search/issues")!
        url.queryItems = [
          URLQueryItem(name: "q", value: "is:pr author:\(author) \(filter)"),
          URLQueryItem(name: "per_page", value: "100"),
          URLQueryItem(name: "page", value: String(page)),
        ]
        let result: SearchResult = try await get(url.url!)
        guard !result.incompleteResults, result.totalCount <= 1000 else {
          throw GitHubClientError.message(
            "GitHub returned incomplete PR results. Your saved snapshot has been kept.")
        }
        for issue in result.items { issues["\(issue.repositoryUrl)/\(issue.number)"] = issue }
        if page * 100 >= result.totalCount { break }
        page += 1
      }
    }
    var entries: [GitHubPREntry] = []
    for issue in issues.values {
      try Task.checkCancellation()
      let url = issue.repositoryUrl.appendingPathComponent("pulls").appendingPathComponent(
        String(issue.number))
      let pull: Pull = try await get(url)
      entries.append(pull.entry)
    }
    return entries
  }

  // Only sends credentials to GitHub's API; errors never include response bodies or credentials.
  private func get<Value: Decodable>(_ url: URL) async throws -> Value {
    guard url.scheme == "https", url.host == "api.github.com" else {
      throw GitHubClientError.message("Invalid GitHub API address.")
    }
    var request = URLRequest(url: url)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("Sceal", forHTTPHeaderField: "User-Agent")
    request.cachePolicy = .reloadIgnoringLocalCacheData
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
      let code = (response as? HTTPURLResponse)?.statusCode ?? 0
      throw GitHubClientError.message(
        "GitHub request failed (\(code)). Check your token, repository access, or rate limit.")
    }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(Value.self, from: data)
  }
}
