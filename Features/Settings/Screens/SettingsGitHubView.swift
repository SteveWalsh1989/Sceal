import SwiftUI

struct SettingsGitHubView: View {
  @ObservedObject var store: NotesStore
  @State private var token = ""
  @FocusState private var tokenIsFocused: Bool

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        GroupBox("GitHub") {
          VStack(alignment: .leading, spacing: 16) {
            if let account = store.githubAccount {
              Text("Connected as \(account)")
            }
            VStack(alignment: .leading, spacing: 8) {
              Text("Personal access token").font(.headline)
              // A dedicated input keeps macOS from rendering its prompt as an external form label.
              SecureField(
                "GitHub token", text: $token, prompt: Text("Paste your GitHub token here")
              )
              .labelsHidden()
              .textFieldStyle(.plain)
              .font(.system(size: 15))
              .padding(12)
              .frame(maxWidth: .infinity, minHeight: 44)
              .background(
                Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8)
              )
              .overlay {
                RoundedRectangle(cornerRadius: 8)
                  .strokeBorder(tokenIsFocused ? Color.accentColor : Color.secondary, lineWidth: 1)
              }
              .accessibilityLabel("GitHub personal access token")
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
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(12)
        }
        GitHubPRAppearanceControls(store: store)
        GroupBox("Create a token") {
          VStack(alignment: .leading, spacing: 12) {
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
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(12)
        }
        GroupBox("Daily notes") {
          Text(
            "Type /github in a daily note to insert your PR section. Copying the previous note carries unfinished PRs forward. Today's section refreshes on opening and every five minutes while the app is active. Older notes keep their saved statuses."
          )
        }
      }
      .padding(28)
    }
    .task { await store.restoreGitHubConnection() }
    .onDisappear { token = "" }
  }
}

private struct GitHubPRAppearanceControls: View {
  @ObservedObject var store: NotesStore

  var body: some View {
    GroupBox("PR section appearance") {
      VStack(alignment: .leading, spacing: 20) {
        Text("Applies to all notes. Saved PR records and historical statuses stay unchanged.")
          .foregroundStyle(.secondary)
        labeledField("Section title", text: $store.githubPRAppearance.title)
        VStack(alignment: .leading, spacing: 8) {
          Text("Title color").font(.headline)
          HStack(spacing: 12) {
            ForEach(ThemePalette.colors, id: \.name) { color in
              Button {
                store.githubPRAppearance.titleColorName = color.name
              } label: {
                Circle().fill(Color(nsColor: color.color))
                  .frame(width: 24, height: 24)
                  .overlay {
                    if store.githubPRAppearance.titleColorName == color.name {
                      Circle().strokeBorder(Color.primary, lineWidth: 2)
                    }
                  }
              }
              .buttonStyle(.plain)
              .accessibilityLabel("Use \(color.name) for the PR title")
              .accessibilityAddTraits(
                store.githubPRAppearance.titleColorName == color.name ? .isSelected : []
              )
              .help(color.name.capitalized)
            }
          }
        }
        VStack(alignment: .leading, spacing: 8) {
          Text("First group").font(.headline)
          Picker("First group", selection: $store.githubPRAppearance.firstGroup) {
            ForEach(GitHubPRGroup.allCases) { group in
              Text(store.githubPRAppearance.label(for: group)).tag(group)
            }
          }
          .labelsHidden()
          .pickerStyle(.segmented)
        }
        labeledField("Today's group label", text: $store.githubPRAppearance.todayLabel)
        labeledField("Earlier PRs group label", text: $store.githubPRAppearance.carriedForwardLabel)
        Toggle("Hide empty groups", isOn: $store.githubPRAppearance.hidesEmptyGroups)
        Divider()
        HStack {
          Text("Live preview · Example PRs").font(.headline)
          Spacer()
          Button("Reset appearance") { store.githubPRAppearance = GitHubPRAppearance() }
        }
        GitHubPRSectionView(
          store: store, documentID: "preview", section: previewSection, previewDate: previewDate
        )
        .padding(20)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(12)
    }
  }

  // Explicit labels and full-width inputs avoid the automatic macOS Form field layout.
  private func labeledField(_ title: String, text: Binding<String>) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title).font(.headline)
      TextField("", text: text)
        .textFieldStyle(.roundedBorder)
        .accessibilityLabel(title)
    }
  }

  private var previewDate: Date { Calendar.current.startOfDay(for: .now) }
  private var previewSection: StructuredNoteSection {
    let today = GitHubPREntry(
      id: 1, number: 24514, title: "Utilization report > remove unused cell",
      repository: "Teamwork/teamwork-lightspeed",
      url: URL(string: "https://github.com/Teamwork/teamwork-lightspeed/pull/24514")!,
      createdAt: previewDate, isDraft: false)
    var earlier = today
    earlier.id = 2
    earlier.number = 24501
    earlier.title = "Companies > edit address in the company dialog"
    earlier.url = URL(string: "https://github.com/Teamwork/teamwork-lightspeed/pull/24501")!
    earlier.createdAt = previewDate.addingTimeInterval(-86400)
    return StructuredNoteSection(githubSnapshot: GitHubPRSnapshot(entries: [today, earlier]))
  }
}
