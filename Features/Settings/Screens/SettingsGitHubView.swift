import SwiftUI

struct SettingsGitHubView: View {
  @ObservedObject var store: NotesStore
  @State private var token = ""
  @FocusState private var tokenIsFocused: Bool

  var body: some View {
    Form {
      Section("GitHub") {
        if let account = store.githubAccount {
          Text("Connected as \(account)")
        }
        VStack(alignment: .leading, spacing: 8) {
          Text("Personal access token").font(.headline)
          SecureField("Paste your GitHub token", text: $token)
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()
            .focused($tokenIsFocused)
          Text("Accepts fine-grained or classic personal access tokens.")
            .foregroundStyle(.secondary)
        }
        HStack {
          Button("Connect") {
            Task {
              await store.connectGitHub(token: token)
              token = ""
              if let documentID = store.selectedStructuredNote?.id {
                await store.refreshGitHub(documentID: documentID)
              }
            }
          }
          .disabled(
            token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              || store.isConnectingGitHub)
          if store.githubAccount != nil {
            Button("Disconnect", role: .destructive) {
              store.disconnectGitHub()
              token = ""
              tokenIsFocused = true
            }
            .disabled(store.isConnectingGitHub)
          }
          if store.isConnectingGitHub { ProgressView().controlSize(.small) }
        }
        Text("Stored in macOS Keychain. Disconnecting keeps your saved daily PR history.")
          .foregroundStyle(.secondary)
        if let error = store.githubError { Text(error).foregroundStyle(.red) }
      }
      Section("Create a token") {
        Link(
          "Open GitHub token settings",
          destination: URL(string: "https://github.com/settings/personal-access-tokens/new")!)
        Text(
          "Choose Teamwork as the resource owner, select the repositories you want to track, and grant Pull requests: Read-only. GitHub also requires read-only repository metadata. Your organization may require approval."
        )
        Text(
          "Only repositories this token can access will appear. Contributions under a different repository owner require separate access."
        )
        .foregroundStyle(.secondary)
      }
      Section("Daily notes") {
        Text(
          "Type /github in a daily note to insert your PR section. Copying the previous note carries unfinished PRs forward. Today's section refreshes on opening and every five minutes while the app is active. Older notes keep their saved statuses."
        )
      }
    }
    .formStyle(.grouped)
    .task { await store.restoreGitHubConnection() }
    .onDisappear { token = "" }
  }
}
