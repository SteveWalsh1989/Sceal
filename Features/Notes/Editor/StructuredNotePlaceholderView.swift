//
//  StructuredNotePlaceholderView.swift
//

// Read-only Stage 3 surface proving isolated structured loading and selection before editing.

import SwiftUI

struct StructuredNotePlaceholderView: View {
  @ObservedObject var store: NotesStore

  var body: some View {
    VStack(spacing: 0) {
      modeHeader

      Divider()

      if let document = store.selectedStructuredNote {
        selectedDocumentContent(document)
      } else {
        emptyContent
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var modeHeader: some View {
    HStack(spacing: 10) {
      Label("Structured Notes V2", systemImage: "square.stack.3d.up")
        .font(.headline)

      Text("EXPERIMENTAL")
        .font(.caption2.weight(.bold))
        .tracking(0.7)
        .foregroundStyle(.orange)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(.orange.opacity(0.12), in: Capsule())

      Spacer()

      Text("\(store.structuredNotes.count) notes")
        .font(.callout)
        .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 24)
    .padding(.vertical, 16)
  }

  private func selectedDocumentContent(_ document: StructuredNoteDocument) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text(document.date.formatted(date: .complete, time: .omitted))
          .font(.callout.weight(.medium))
          .foregroundStyle(.secondary)

        Text(
          document.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Untitled note"
            : document.title
        )
        .font(.largeTitle.weight(.bold))

        if !document.tags.isEmpty {
          Text(document.tags.joined(separator: ", "))
            .font(.callout)
            .foregroundStyle(.secondary)
        }

        Label(
          "Loaded \(sectionCount(in: document)) structured sections from the isolated library.",
          systemImage: "checkmark.circle.fill"
        )
        .foregroundStyle(.green)

        Text(
          "This checkpoint is read-only. The separate section editor, typing, and autosave arrive in Stage 4. Your legacy Markdown note remains available when you switch back to Legacy Markdown mode."
        )
        .font(.body)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

        storagePath
      }
      .frame(maxWidth: 720, alignment: .leading)
      .padding(40)
      .frame(maxWidth: .infinity, alignment: .top)
    }
  }

  private var emptyContent: some View {
    ContentUnavailableView {
      Label("No structured notes yet", systemImage: "square.stack.3d.up.slash")
    } description: {
      Text(
        "Use the explicit copy action in Experimental Settings to create structured copies of your legacy daily notes."
      )
    } actions: {
      Button("Copy legacy daily notes") {
        store.copyLegacyDailyNotesToStructuredLibrary()
      }
      .buttonStyle(.borderedProminent)
    }
  }

  private var storagePath: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Active storage")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      Text(store.activeDailyNotesStorageURL.path)
        .font(.caption.monospaced())
        .foregroundStyle(.tertiary)
        .textSelection(.enabled)
    }
  }

  private func sectionCount(in document: StructuredNoteDocument) -> Int {
    document.nodes.reduce(into: 0) { count, node in
      switch node {
      case .section:
        count += 1
      case .group(let group):
        count += group.sections.count
      }
    }
  }
}
