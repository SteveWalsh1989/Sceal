import SwiftUI

struct GitHubPRSectionView: View {
  @Environment(\.openSettings) private var openSettings
  @ObservedObject var store: NotesStore
  let documentID: String
  let section: StructuredNoteSection

  private var date: Date { store.selectedStructuredNote?.date ?? .distantPast }
  private var isToday: Bool { Calendar.current.isDateInToday(date) && store.sidebarMode != .list }
  private var snapshot: GitHubPRSnapshot { section.githubSnapshot ?? GitHubPRSnapshot() }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        Text("PRs").font(.title3.bold()).foregroundStyle(.pink)
        Spacer()
        if isToday {
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
      if !isToday {
        Label(
          "Saved snapshot for \(date.formatted(date: .abbreviated, time: .omitted))",
          systemImage: "lock"
        )
        .font(.caption).foregroundStyle(.secondary)
      } else if let refreshedAt = snapshot.refreshedAt {
        Text("Updated \(refreshedAt.formatted(date: .omitted, time: .shortened))")
          .font(.caption).foregroundStyle(.secondary)
      } else {
        Text("Not yet synced for this day").font(.caption).foregroundStyle(.secondary)
      }
      if snapshot.entries.isEmpty {
        Text(
          snapshot.refreshedAt == nil
            ? "Connect GitHub in Settings, then refresh to load your PRs." : "No PRs for this day."
        )
        .foregroundStyle(.secondary)
      } else {
        entryGroup(
          "Opened today",
          entries: snapshot.entries.filter {
            Calendar.current.isDate($0.createdAt, inSameDayAs: date)
          })
        entryGroup(
          "Carried forward",
          entries: snapshot.entries.filter {
            !Calendar.current.isDate($0.createdAt, inSameDayAs: date)
          })
      }
      if isToday {
        if let error = store.githubError {
          Text(error).font(.caption).foregroundStyle(.red)
        }
        HStack {
          Text("Saved locally · Refreshes every 5 minutes while active")
            .font(.caption).foregroundStyle(.secondary)
          Spacer()
          Button("Settings") { openSettings() }.buttonStyle(.link)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .task(id: section.id) { await store.refreshGitHub(documentID: documentID) }
  }

  // The title is the link target; status is separate so completed work stays readable.
  private func entryGroup(_ title: String, entries: [GitHubPREntry]) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("\(title)  \(entries.count)").font(.subheadline.weight(.semibold))
      ForEach(entries) { entry in
        HStack(alignment: .top, spacing: 12) {
          Image(systemName: entry.mergedAt == nil ? "arrow.triangle.pull" : "arrow.triangle.merge")
            .foregroundStyle(.secondary)
          VStack(alignment: .leading, spacing: 4) {
            Link(entry.title, destination: entry.url).foregroundStyle(.primary)
            Text("\(entry.repository) · #\(entry.number)")
              .font(.caption).foregroundStyle(.secondary)
          }
          Spacer(minLength: 8)
          Text(entry.status)
            .font(.caption.weight(.medium))
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
