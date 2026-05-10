import SwiftUI

struct SettingsBackupView: View {
  @ObservedObject var store: NotesStore

  var body: some View {
    Form {
      Section {
        Text(
          "Scéal keeps your notes local first and writes separate backup archives to a folder you choose, including iCloud Drive."
        )
        .foregroundStyle(.secondary)
      }

      Section("Location") {
        LabeledContent("Status") {
          BackupHealthBadge(health: store.backupHealth)
        }

        LabeledContent("Folder") {
          Text(store.backupSettings.folderDisplayPath ?? "Not configured")
            .foregroundStyle(store.backupSettings.isConfigured ? .primary : .secondary)
            .multilineTextAlignment(.trailing)
        }

        HStack {
          Button(store.backupSettings.isConfigured ? "Change Folder…" : "Choose Folder…") {
            store.chooseBackupFolder()
          }
          .disabled(store.isBackupRunning)

          Button("Reveal in Finder") {
            store.revealBackupFolderInFinder()
          }
          .disabled(!store.backupSettings.isConfigured || store.isBackupRunning)

          Spacer()

          Button("Remove Location") {
            store.removeBackupFolder()
          }
          .disabled(!store.backupSettings.isConfigured || store.isBackupRunning)
        }

        Text(
          "Backups are stored in a managed 'Sceal Backup' folder inside the location you choose."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Section("Schedule") {
        Picker(
          "Backup frequency",
          selection: Binding(
            get: { store.effectiveBackupSchedule },
            set: { store.updateBackupSchedule($0) }
          )
        ) {
          ForEach(store.availableBackupSchedules, id: \.self) { schedule in
            Text(schedule.displayName).tag(schedule)
          }
        }
        .pickerStyle(.menu)

        Toggle(
          "Back up when Scéal becomes inactive",
          isOn: Binding(
            get: { store.isBackupOnInactiveAvailable && store.backupSettings.backupOnInactive },
            set: { store.updateBackupOnInactive($0) }
          )
        )
        .disabled(!store.isBackupOnInactiveAvailable)

        Text(
          "Automatic backups run while Scéal is open and catch up next time it launches if one is overdue."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Section("Actions") {
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text("Back Up Now")
              .font(.body)
            Text("Creates a full standalone snapshot without touching your live notes.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          Spacer()

          Button("Run Backup") {
            store.runBackupNow()
          }
          .disabled(!store.backupSettings.isConfigured || store.isBackupRunning)
        }
      }

      Section("Status") {
        LabeledContent("Last successful backup") {
          Text(formattedDate(store.backupSettings.lastSuccessfulBackupAt))
            .foregroundStyle(
              store.backupSettings.lastSuccessfulBackupAt == nil ? .secondary : .primary)
        }

        LabeledContent("Next scheduled backup") {
          Text(formattedDate(store.nextBackupDueDate()))
            .foregroundStyle(store.nextBackupDueDate() == nil ? .secondary : .primary)
        }

        LabeledContent("Last backup size") {
          Text(formattedBytes(store.backupSettings.lastBackupBytes))
            .foregroundStyle(store.backupSettings.lastBackupBytes == nil ? .secondary : .primary)
        }

        LabeledContent("Automatic backups retained") {
          Text(retentionSummary)
            .foregroundStyle(.secondary)
        }

        if let lastError = store.backupSettings.lastBackupErrorDescription {
          LabeledContent("Last error") {
            Text(lastError)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.trailing)
          }
        }
      }
    }
    .formStyle(.grouped)
    .onAppear {
      store.refreshBackupHealth()
    }
  }

  private var retentionSummary: String {
    guard let count = store.effectiveBackupSchedule.retainedAutomaticBackupCount else {
      return "Manual backups are never pruned automatically."
    }

    return "Keeps the latest \(count) automatic backups."
  }

  private func formattedDate(_ date: Date?) -> String {
    guard let date else {
      return "Not yet"
    }

    return date.formatted(date: .abbreviated, time: .shortened)
  }

  private func formattedBytes(_ bytes: Int64?) -> String {
    guard let bytes else {
      return "Not yet"
    }

    return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }
}

private struct BackupHealthBadge: View {
  let health: BackupHealth

  var body: some View {
    Text(health.displayName)
      .font(.caption.weight(.semibold))
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(backgroundColor.opacity(0.14), in: Capsule())
      .foregroundStyle(backgroundColor)
  }

  private var backgroundColor: Color {
    switch health {
    case .healthy:
      return .green
    case .running:
      return .blue
    case .overdue:
      return .orange
    case .folderUnavailable, .permissionRequired, .failed:
      return .red
    case .notConfigured:
      return .secondary
    }
  }
}
