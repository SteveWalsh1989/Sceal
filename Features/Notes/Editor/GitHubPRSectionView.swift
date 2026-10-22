import SwiftUI

struct GitHubPRSectionView: View {
  @Environment(\.openWindow) private var openWindow
  @ObservedObject var store: NotesStore
  let documentID: String
  let section: StructuredNoteSection
  var previewDate: Date? = nil
  var sectionColorName: String? = nil
  var onReorder: ((Int, Int) -> Void)? = nil
  @State private var hoveredEntryID: Int?
  @State private var dropTargetEntryID: Int?
  @State private var hoveredTitleID: Int?

  private var layout: GitHubPRSectionLayout { section.githubLayout ?? GitHubPRSectionLayout() }

  private var appearance: GitHubPRAppearance {
    var appearance = store.githubPRAppearance
    if let firstGroup = section.githubLayout?.firstGroup { appearance.firstGroup = firstGroup }
    return appearance
  }
  private var isCompact: Bool { section.githubLayout?.isCompact ?? false }

  private var titleColor: Color {
    let name: String?
    switch section.githubLayout?.colorMode ?? .standard {
    case .standard: name = appearance.titleColorName
    case .section: name = sectionColorName ?? appearance.titleColorName
    case .custom: name = section.githubLayout?.customColorName ?? "pink"
    }
    return Color(nsColor: ThemePalette.color(named: name ?? "pink") ?? .systemPink)
  }

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
          .foregroundStyle(titleColor)
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
    VStack(alignment: .leading, spacing: isCompact ? 5 : 12) {
      Text("\(title)  \(entries.count)").font(.system(size: bodySize, weight: .semibold))
      ForEach(layout.orderedEntries(entries)) { entry in
        HStack(alignment: isCompact ? .center : .top, spacing: 12) {
          if section.githubLayout?.showsIcons ?? true {
            // The overlay grows the symbol without contributing to the row's measured height.
            Color.clear
              .frame(width: 22, height: bodySize)
              .overlay(alignment: .center) {
                Image(
                  systemName: entry.mergedAt == nil ? "arrow.triangle.pull" : "arrow.triangle.merge"
                )
                .font(.system(size: max(18, bodySize + 2), weight: .medium))
                .foregroundStyle(statusColor(entry))
              }
              .accessibilityHidden(true)
          }
          VStack(alignment: .leading, spacing: 4) {
            Link(entry.title, destination: entry.url)
              .foregroundStyle(Color.primary.opacity(hoveredTitleID == entry.id ? 0.75 : 1))
              .onHover { isHovering in
                if isHovering {
                  hoveredTitleID = entry.id
                } else if hoveredTitleID == entry.id {
                  hoveredTitleID = nil
                }
              }
              .lineLimit(isCompact ? 1 : nil)
              .help(entry.title)
            if !isCompact {
              Text("\(entry.repository) · #\(entry.number)")
                .font(.system(size: detailSize)).foregroundStyle(.secondary)
            }
          }
          Spacer(minLength: 8)
          if layout.sortOrder == .manual && onReorder != nil {
            Image(systemName: "line.3.horizontal")
              .font(.system(size: 13, weight: .medium))
              .foregroundStyle(.secondary)
              .frame(width: 20, height: bodySize)
              .contentShape(Rectangle())
              .opacity(hoveredEntryID == entry.id ? 1 : 0)
              .draggable("sceal-pr:\(section.id):\(entry.id)")
              .help("Drag to reorder PR")
              .accessibilityLabel("Reorder \(entry.title)")
          }
          Text(entry.status)
            .font(.system(size: detailSize, weight: .medium))
            .foregroundStyle(statusColor(entry))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(statusColor(entry).opacity(0.14), in: Capsule())
            .fixedSize(horizontal: true, vertical: false)
        }
        .contentShape(Rectangle())
        .onHover { isHovering in
          if isHovering {
            hoveredEntryID = entry.id
          } else if hoveredEntryID == entry.id {
            hoveredEntryID = nil
          }
        }
        .dropDestination(for: String.self) { items, _ in
          guard layout.sortOrder == .manual, let payload = items.first,
            payload.hasPrefix("sceal-pr:\(section.id):"),
            let sourceID = Int(payload.split(separator: ":").last ?? ""),
            let source = snapshot.entries.first(where: { $0.id == sourceID }),
            Calendar.current.isDate(source.createdAt, inSameDayAs: date)
              == Calendar.current.isDate(entry.createdAt, inSameDayAs: date),
            let onReorder, sourceID != entry.id
          else { return false }
          onReorder(sourceID, entry.id)
          return true
        } isTargeted: { isTargeted in
          if isTargeted && layout.sortOrder == .manual {
            dropTargetEntryID = entry.id
          } else if dropTargetEntryID == entry.id {
            dropTargetEntryID = nil
          }
        }
        .background {
          if dropTargetEntryID == entry.id {
            RoundedRectangle(cornerRadius: 5).fill(Color.accentColor.opacity(0.12))
          }
        }
        if section.githubLayout?.showsDividers ?? true { Divider() }
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
