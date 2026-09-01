//
//  StructuredNoteEditorView.swift
//

// Multi-section daily-note editor backed directly by StructuredNoteDocument values.

import SwiftUI

struct StructuredNoteEditorView: View {
  @Environment(\.openWindow) private var openWindow
  @ObservedObject var store: NotesStore
  var sidebarCollapsed: Bool
  @StateObject private var editorCoordinator = StructuredNoteEditorCoordinator()

  var body: some View {
    if let document = store.selectedStructuredNote {
      editor(document)
        .onAppear {
          activateEditor(for: document)
        }
        .onChange(of: store.selectedStructuredNoteID) { _, _ in
          guard let selectedDocument = store.selectedStructuredNote else { return }
          activateEditor(for: selectedDocument)
        }
        .onDisappear {
          store.flushPendingStructuredNoteSave(for: document.id)
        }
    } else {
      StructuredNotePlaceholderView(store: store)
    }
  }

  private func editor(_ document: StructuredNoteDocument) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      editorHeader(document)
        .padding(.leading, sidebarCollapsed ? 130 : 0)

      TextField("Title", text: store.structuredTitleBinding(for: document.id), axis: .vertical)
        .textFieldStyle(.plain)
        .font(.system(size: 30, weight: .bold))
        .lineLimit(1...3)

      ScrollView {
        VStack(spacing: 14) {
          ForEach(Array(sectionItems(in: document).enumerated()), id: \.element.id) {
            index, item in
            StructuredSectionEditorCard(
              store: store,
              editorCoordinator: editorCoordinator,
              documentID: document.id,
              item: item,
              position: index + 1
            )
          }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
      }
      .scrollIndicators(.hidden)
    }
    .padding(.horizontal, 24)
    .padding(.bottom, 24)
    .padding(.top, 12)
  }

  private func editorHeader(_ document: StructuredNoteDocument) -> some View {
    let adjacentNoteIDs = store.adjacentStructuredNoteIDs(for: document.id)
    let controlColor = themeColors.controlBackground.color

    return HStack(alignment: .center, spacing: 12) {
      HStack(spacing: 8) {
        Text(NoteDateFormatters.editorDate.string(from: document.date))
          .font(.callout)
          .foregroundStyle(.secondary)

        if let previousID = adjacentNoteIDs.previous {
          HeaderNavigationButton(
            systemImage: "chevron.left",
            accessibilityLabel: "Open older note",
            controlColor: controlColor
          ) {
            store.selectStructuredNote(previousID)
          }
        }

        if let nextID = adjacentNoteIDs.next {
          HeaderNavigationButton(
            systemImage: "chevron.right",
            accessibilityLabel: "Open newer note",
            controlColor: controlColor
          ) {
            store.selectStructuredNote(nextID)
          }
        }
      }

      Spacer()

      TextField("Tags", text: store.structuredTagsBinding(for: document.id))
        .textFieldStyle(.plain)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)

      EditorSearchBar(
        searchText: store.activeSearchTextBinding,
        isExpanded: store.activeSearchBarExpandedBinding,
        controlColor: controlColor
      )

      Button {
        store.selectToday()
      } label: {
        Label("Today", systemImage: "calendar")
      }
      .buttonStyle(.bordered)
      .controlSize(.small)

      Button {
        openWindow(id: "settings")
      } label: {
        Image(systemName: "slider.vertical.3")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(.secondary)
          .frame(width: 28, height: 28)
          .background(controlColor, in: RoundedRectangle(cornerRadius: 8))
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Open appearance settings")
    }
  }

  private var themeColors: ThemeColorSet {
    store.effectiveAppearanceSettings.resolvedColors
  }

  // Flattens root and grouped sections for the Stage 4 editor without losing stable identity.
  private func sectionItems(in document: StructuredNoteDocument) -> [StructuredEditorSectionItem] {
    document.nodes.flatMap { node -> [StructuredEditorSectionItem] in
      switch node {
      case .section(let section):
        return [StructuredEditorSectionItem(section: section, groupTitle: nil)]
      case .group(let group):
        return group.sections.map {
          StructuredEditorSectionItem(section: $0, groupTitle: group.title)
        }
      }
    }
  }

  private func activateEditor(for document: StructuredNoteDocument) {
    editorCoordinator.activate(
      documentID: document.id,
      initialSectionID: sectionItems(in: document).first?.id
    )
  }
}

private struct StructuredEditorSectionItem: Identifiable {
  let section: StructuredNoteSection
  let groupTitle: String?

  var id: UUID { section.id }
}

private struct StructuredSectionEditorCard: View {
  @ObservedObject var store: NotesStore
  @ObservedObject var editorCoordinator: StructuredNoteEditorCoordinator
  let documentID: String
  let item: StructuredEditorSectionItem
  let position: Int
  @State private var editorHeight: CGFloat = 132

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      sectionHeader

      ZStack(alignment: .topLeading) {
        if item.section.markdown.isEmpty {
          Text("Start writing in this section.")
            .foregroundStyle(.secondary)
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .allowsHitTesting(false)
        }

        MarkdownEditorView(
          noteID: "\(documentID)#\(item.id.uuidString)",
          text: store.structuredSectionMarkdownBinding(
            documentID: documentID,
            sectionID: item.id
          ),
          appearanceSettings: store.effectiveAppearanceSettings,
          continuousSpellCheckingEnabled: store.continuousSpellCheckingEnabled,
          searchText: store.structuredSearchText,
          libraryRootURL: store.libraryLocation.rootURL,
          imageAttachmentRootURL: store.libraryRepository.attachmentsRootURL,
          allowsImageAttachments: false,
          allowsSectionColorEditing: false,
          allowsSlashCommands: false,
          interpretsSectionDirectives: false,
          viewportMode: .contentSized(minimumHeight: 132),
          focusRequestID: focusRequestID,
          onFocus: {
            editorCoordinator.didFocus(sectionID: item.id)
          },
          onContentHeightChange: { contentHeight in
            guard abs(editorHeight - contentHeight) > 0.5 else { return }
            editorHeight = contentHeight
          }
        )
        .frame(height: editorHeight)
      }
    }
    .background(
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .fill(themeColors.sectionCardFill.color)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .strokeBorder(sectionBorderColor, lineWidth: isFocused ? 1.5 : 1)
    )
  }

  private var sectionHeader: some View {
    HStack(spacing: 8) {
      Button {
        editorCoordinator.requestFocus(sectionID: item.id)
      } label: {
        Text("Section \(position)")
          .font(.caption.weight(.semibold))
          .foregroundStyle(isFocused ? accentColor : Color(nsColor: .secondaryLabelColor))
      }
      .buttonStyle(.plain)

      if let groupTitle = item.groupTitle {
        Text("Group: \(groupTitle)")
          .font(.caption)
          .foregroundStyle(.tertiary)
      }

      Spacer()
    }
    .padding(.horizontal, 18)
    .padding(.top, 13)
  }

  private var focusRequestID: UUID? {
    guard editorCoordinator.focusRequest?.sectionID == item.id else { return nil }
    return editorCoordinator.focusRequest?.id
  }

  private var isFocused: Bool {
    editorCoordinator.focusedSectionID == item.id
  }

  private var themeColors: ThemeColorSet {
    store.effectiveAppearanceSettings.resolvedColors
  }

  private var sectionBorderColor: Color {
    isFocused ? accentColor.opacity(0.65) : themeColors.divider.color
  }

  private var accentColor: Color {
    Color(nsColor: store.effectiveAppearanceSettings.accentColor)
  }
}
