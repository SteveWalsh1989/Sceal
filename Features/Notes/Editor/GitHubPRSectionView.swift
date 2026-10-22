import SwiftUI

struct GitHubPRSectionView: View {
  @Environment(\.openWindow) private var openWindow
  @ObservedObject var store: NotesStore
  let documentID: String
  let section: StructuredNoteSection
  var previewDate: Date? = nil

  private var appearance: GitHubPRAppearance { store.githubPRAppearance }

  private var bodySize: CGFloat { store.effectiveAppearanceSettings.bodyFontSize }
  private var detailSize: CGFloat { max(13, bodySize - 2) }

  private var date: Date { previewDate ?? store.selectedStructuredNote?.date ?? .distantPast }
  private var isToday: Bool {
    previewDate == nil && Calendar.current.isDateInToday(date) && store.sidebarMode != .list
  }
  private var snapshot: GitHubPRSnapshot { section.githubSnapshot ?? GitHubPRSnapshot() }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        Text(appearance.displayedTitle)
          .font(.system(size: bodySize + 5, weight: .bold))
          .foregroundStyle(
            Color(nsColor: ThemePalette.color(named: appearance.titleColorName) ?? .systemPink))
        Spacer()
        if isToday {
          if let refreshedAt = snapshot.refreshedAt {
            Text("Updated \(refreshedAt.formatted(date: .omitted, time: .shortened))")
              .font(.system(size: detailSize)).foregroundStyle(.secondary)
          }
          if store.isRefreshingGitHub {
            ProgressView().controlSize(.small).accessibilityLabel("Refreshing GitHub PRs")
          } else {
            Button {
              Task { await store.refreshGitHub(documentID: documentID) }
            } label: {
              Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh GitHub PRs")
            .accessibilityLabel("Refresh GitHub PRs")
          }
        }
      }
      if !isToday && previewDate == nil {
        Label(
          "Saved snapshot for \(date.formatted(date: .abbreviated, time: .omitted))",
          systemImage: "lock"
        )
        .font(.system(size: detailSize)).foregroundStyle(.secondary)
      } else if snapshot.refreshedAt == nil && previewDate == nil {
        Text("Not yet synced for this day").font(.system(size: detailSize)).foregroundStyle(
          .secondary)
      }
      if snapshot.entries.isEmpty {
        Text(
          snapshot.refreshedAt == nil
            ? "Connect GitHub in Settings, then refresh to load your PRs." : "No PRs for this day."
        )
        .foregroundStyle(.secondary)
      }
      ForEach(appearance.orderedGroups) { group in
        let entries = snapshot.entries.filter {
          Calendar.current.isDate($0.createdAt, inSameDayAs: date) == (group == .today)
        }
        if !entries.isEmpty || !appearance.hidesEmptyGroups {
          entryGroup(appearance.label(for: group), entries: entries)
        }
      }
      if isToday {
        if store.githubAccount == nil {
          Button("Connect GitHub", action: showGitHubSettings)
            .buttonStyle(.bordered)
        }
        if let error = store.githubError {
          Text(error).font(.system(size: detailSize)).foregroundStyle(.red)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .font(.system(size: bodySize))
    .task(id: section.id) {
      if previewDate == nil { await store.refreshGitHub(documentID: documentID) }
    }
  }

  // The app uses a named window rather than SwiftUI's built-in Settings scene.
  private func showGitHubSettings() {
    store.selectedSettingsSection = .github
    openWindow(id: "settings")
  }

  // The title is the link target; status is separate so completed work stays readable.
  private func entryGroup(_ title: String, entries: [GitHubPREntry]) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("\(title)  \(entries.count)").font(.system(size: bodySize, weight: .semibold))
      ForEach(entries) { entry in
        HStack(alignment: .top, spacing: 12) {
          Image(systemName: entry.mergedAt == nil ? "arrow.triangle.pull" : "arrow.triangle.merge")
            .foregroundStyle(.secondary)
          VStack(alignment: .leading, spacing: 4) {
            Link(entry.title, destination: entry.url).foregroundStyle(.primary)
            Text("\(entry.repository) · #\(entry.number)")
              .font(.system(size: detailSize)).foregroundStyle(.secondary)
          }
          Spacer(minLength: 8)
          Text(entry.status)
            .font(.system(size: detailSize, weight: .medium))
            .foregroundStyle(statusColor(entry))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(statusColor(entry).opacity(0.14), in: Capsule())
        }
        Divider()
      }
    }
  }

  // Text accompanies color so status never depends on color perception alone.
  private func statusColor(_ entry: GitHubPREntry) -> Color {
    if entry.mergedAt != nil { return .purple }
    if entry.closedAt != nil { return .red }
    return entry.isDraft ? .secondary : .green
  }
}
