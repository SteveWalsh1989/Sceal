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
    let items = sectionItems(in: document)

    return VStack(alignment: .leading, spacing: 12) {
      editorHeader(document)
        .padding(.leading, sidebarCollapsed ? 130 : 0)

      TextField("Title", text: store.structuredTitleBinding(for: document.id), axis: .vertical)
        .textFieldStyle(.plain)
        .font(.system(size: 30, weight: .bold))
        .lineLimit(1...3)

      ScrollViewReader { scrollProxy in
        ScrollView {
          VStack(spacing: 14) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
              StructuredSectionEditorCard(
                store: store,
                editorCoordinator: editorCoordinator,
                documentID: document.id,
                item: item,
                position: index + 1
              )
              .id(item.id)
            }
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .onChange(of: editorCoordinator.focusRequest) { _, request in
          guard let request else { return }
          withAnimation(.easeOut(duration: 0.16)) {
            scrollProxy.scrollTo(request.sectionID, anchor: .center)
          }
        }
      }
    }
    .padding(.horizontal, 24)
    .padding(.bottom, 24)
    .padding(.top, 12)
    .onAppear {
      editorCoordinator.updateSectionOrder(items.map(\.id))
    }
    .onChange(of: items.map(\.id)) { _, sectionIDs in
      editorCoordinator.updateSectionOrder(sectionIDs)
    }
    .onChange(of: document.title) { _, _ in
      editorCoordinator.invalidateStructuralUndo()
    }
    .onChange(of: document.tags) { _, _ in
      editorCoordinator.invalidateStructuralUndo()
    }
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

  // Flattens root and grouped sections while retaining their structural action context.
  private func sectionItems(in document: StructuredNoteDocument) -> [StructuredEditorSectionItem] {
    var items: [StructuredEditorSectionItem] = []
    let totalSectionCount = document.nodes.reduce(into: 0) { count, node in
      switch node {
      case .section:
        count += 1
      case .group(let group):
        count += group.sections.count
      }
    }

    for (rootNodeIndex, node) in document.nodes.enumerated() {
      switch node {
      case .section(let section):
        let previousMergeID: UUID? = {
          guard rootNodeIndex > document.nodes.startIndex,
            case .section(let previousSection) = document.nodes[rootNodeIndex - 1]
          else { return nil }
          return previousSection.id
        }()
        let nextMergeID: UUID? = {
          guard document.nodes.indices.contains(rootNodeIndex + 1),
            case .section(let nextSection) = document.nodes[rootNodeIndex + 1]
          else { return nil }
          return nextSection.id
        }()
        items.append(
          StructuredEditorSectionItem(
            section: section,
            parent: .root,
            groupTitle: nil,
            groupStyle: nil,
            indexInContainer: rootNodeIndex,
            containerCount: document.nodes.count,
            totalSectionCount: totalSectionCount,
            previousMergeSectionID: previousMergeID,
            nextMergeSectionID: nextMergeID
          )
        )

      case .group(let group):
        for (sectionIndex, section) in group.sections.enumerated() {
          items.append(
            StructuredEditorSectionItem(
              section: section,
              parent: .group(group.id),
              groupTitle: group.title,
              groupStyle: group.style,
              indexInContainer: sectionIndex,
              containerCount: group.sections.count,
              totalSectionCount: totalSectionCount,
              previousMergeSectionID:
                sectionIndex > group.sections.startIndex
                ? group.sections[sectionIndex - 1].id
                : nil,
              nextMergeSectionID:
                group.sections.indices.contains(sectionIndex + 1)
                ? group.sections[sectionIndex + 1].id
                : nil
            )
          )
        }
      }
    }

    return items.enumerated().map { index, item in
      var item = item
      item.previousVisibleSectionID = index > items.startIndex ? items[index - 1].id : nil
      item.nextVisibleSectionID = items.indices.contains(index + 1) ? items[index + 1].id : nil
      return item
    }
  }

  private func activateEditor(for document: StructuredNoteDocument) {
    let sectionIDs = sectionItems(in: document).map(\.id)
    editorCoordinator.activate(documentID: document.id, initialSectionID: sectionIDs.first)
    editorCoordinator.updateSectionOrder(sectionIDs)
  }
}

private struct StructuredEditorSectionItem: Identifiable {
  let section: StructuredNoteSection
  let parent: StructuredNoteSectionParent
  let groupTitle: String?
  let groupStyle: StructuredSectionStyle?
  let indexInContainer: Int
  let containerCount: Int
  let totalSectionCount: Int
  let previousMergeSectionID: UUID?
  let nextMergeSectionID: UUID?
  var previousVisibleSectionID: UUID?
  var nextVisibleSectionID: UUID?

  init(
    section: StructuredNoteSection,
    parent: StructuredNoteSectionParent,
    groupTitle: String?,
    groupStyle: StructuredSectionStyle?,
    indexInContainer: Int,
    containerCount: Int,
    totalSectionCount: Int,
    previousMergeSectionID: UUID?,
    nextMergeSectionID: UUID?,
    previousVisibleSectionID: UUID? = nil,
    nextVisibleSectionID: UUID? = nil
  ) {
    self.section = section
    self.parent = parent
    self.groupTitle = groupTitle
    self.groupStyle = groupStyle
    self.indexInContainer = indexInContainer
    self.containerCount = containerCount
    self.totalSectionCount = totalSectionCount
    self.previousMergeSectionID = previousMergeSectionID
    self.nextMergeSectionID = nextMergeSectionID
    self.previousVisibleSectionID = previousVisibleSectionID
    self.nextVisibleSectionID = nextVisibleSectionID
  }

  var id: UUID { section.id }
  var canMoveUp: Bool { indexInContainer > 0 }
  var canMoveDown: Bool { indexInContainer + 1 < containerCount }
  var canDelete: Bool { totalSectionCount > 1 }
}

private struct StructuredSectionEditorCard: View {
  @ObservedObject var store: NotesStore
  @ObservedObject var editorCoordinator: StructuredNoteEditorCoordinator
  let documentID: String
  let item: StructuredEditorSectionItem
  let position: Int
  @State private var editorHeight: CGFloat = 132
  @State private var isHovering = false
  @State private var isConfirmingDeletion = false

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
          debouncesMarkdownUpdates: false,
          viewportMode: .contentSized(minimumHeight: 132),
          focusRequestID: focusRequest?.id,
          focusCaretPlacement: focusRequest?.caretPlacement ?? .preserve,
          initialSectionHeadingColorName: resolvedStyle.headingColorName,
          initialSectionBulletColorName: resolvedStyle.bulletColorName,
          onFocus: {
            editorCoordinator.didFocus(sectionID: item.id)
          },
          onTextChange: {
            editorCoordinator.didEditText()
          },
          onStructuredSectionSplit: { markdown, splitOffset in
            splitSection(markdown: markdown, atUTF16Offset: splitOffset)
          },
          onBoundaryNavigation: { direction in
            editorCoordinator.navigate(from: item.id, direction: direction)
          },
          onStructuredUndo: {
            editorCoordinator.undoStructuralChangeIfPreferred()
          },
          onStructuredRedo: {
            editorCoordinator.redoStructuralChangeIfPreferred()
          },
          onContentHeightChange: { contentHeight in
            guard abs(editorHeight - contentHeight) > 0.5 else { return }
            editorHeight = contentHeight
          }
        )
        .frame(height: editorHeight)
      }
    }
    .background(sectionBackground)
    .overlay(
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .strokeBorder(sectionBorderColor, lineWidth: isFocused ? 1.5 : 1)
    )
    .onHover { isHovering = $0 }
    .alert("Delete this section?", isPresented: $isConfirmingDeletion) {
      Button("Delete", role: .destructive) {
        deleteSection()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "This section contains content. You can undo the deletion from another section's options menu."
      )
    }
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

      sectionOptionsMenu
        .opacity(isHovering || isFocused ? 1 : 0)
        .allowsHitTesting(isHovering || isFocused)
    }
    .padding(.horizontal, 18)
    .padding(.top, 11)
  }

  private var sectionOptionsMenu: some View {
    Menu {
      Button("Add Section Below", systemImage: "plus") {
        splitSection(
          markdown: item.section.markdown,
          atUTF16Offset: item.section.markdown.utf16.count
        )
      }

      Divider()

      Button("Move Up", systemImage: "arrow.up") {
        moveSection(to: item.indexInContainer - 1)
      }
      .disabled(!item.canMoveUp)

      Button("Move Down", systemImage: "arrow.down") {
        moveSection(to: item.indexInContainer + 1)
      }
      .disabled(!item.canMoveDown)

      Divider()

      Button("Merge With Previous", systemImage: "arrow.up.to.line") {
        mergeSection(direction: .previous)
      }
      .disabled(item.previousMergeSectionID == nil)

      Button("Merge With Next", systemImage: "arrow.down.to.line") {
        mergeSection(direction: .next)
      }
      .disabled(item.nextMergeSectionID == nil)

      StructuredSectionAppearanceMenu(
        styleOverrides: item.section.styleOverrides,
        onChange: updateStyleOverrides
      )

      Divider()

      Button("Undo Structural Change", systemImage: "arrow.uturn.backward") {
        editorCoordinator.undoStructuralChange()
      }
      .disabled(!editorCoordinator.structuralUndoManager.canUndo)

      Button("Redo Structural Change", systemImage: "arrow.uturn.forward") {
        editorCoordinator.redoStructuralChange()
      }
      .disabled(!editorCoordinator.structuralUndoManager.canRedo)

      Divider()

      Button("Delete Section", systemImage: "trash", role: .destructive) {
        requestSectionDeletion()
      }
      .disabled(!item.canDelete)
    } label: {
      Image(systemName: "ellipsis")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.secondary)
        .frame(width: 28, height: 24)
        .contentShape(Rectangle())
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
    .accessibilityLabel("Section \(position) options")
  }

  private var focusRequest: StructuredNoteEditorCoordinator.FocusRequest? {
    guard editorCoordinator.focusRequest?.sectionID == item.id else { return nil }
    return editorCoordinator.focusRequest
  }

  private var isFocused: Bool {
    editorCoordinator.focusedSectionID == item.id
  }

  private var themeColors: ThemeColorSet {
    store.effectiveAppearanceSettings.resolvedColors
  }

  private var resolvedStyle: StructuredSectionStyle {
    item.section.resolvedStyle(groupStyle: item.groupStyle, themeStyle: .themeDefault)
  }

  private var sectionBackground: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .fill(themeColors.sectionCardFill.color)
      if let colorName = resolvedStyle.backgroundColorName,
        let color = ThemePalette.color(named: colorName)
      {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
          .fill(Color(nsColor: color).opacity(0.2))
      }
    }
  }

  private var sectionBorderColor: Color {
    if isFocused {
      return accentColor.opacity(0.65)
    }
    if let colorName = resolvedStyle.borderColorName,
      let color = ThemePalette.color(named: colorName)
    {
      return Color(nsColor: color).opacity(0.8)
    }
    return themeColors.divider.color
  }

  private var accentColor: Color {
    Color(nsColor: store.effectiveAppearanceSettings.accentColor)
  }

  // Splits current Markdown and focuses the newly inserted section at its beginning.
  private func splitSection(markdown: String, atUTF16Offset splitOffset: Int) {
    guard var previousDocument = currentDocument else { return }
    do {
      try previousDocument.setSectionMarkdown(markdown, sectionID: item.id)
      var updatedDocument = previousDocument
      let newSectionID = try updatedDocument.splitSection(
        id: item.id,
        atUTF16Offset: splitOffset
      )
      commitStructuralChange(
        from: previousDocument,
        to: updatedDocument,
        actionName: "Split Section",
        undoFocusSectionID: item.id,
        focusSectionID: newSectionID,
        caretPlacement: .start
      )
    } catch {
      reportStructuralError(error)
    }
  }

  // Reorders a root node or a section inside its existing group.
  private func moveSection(to destinationIndex: Int) {
    performStructuralChange(actionName: "Move Section", focusSectionID: item.id) { document in
      switch item.parent {
      case .root:
        try document.moveRootNode(id: item.id, to: destinationIndex)
      case .group(let groupID):
        try document.moveSection(
          id: item.id,
          to: StructuredNoteSectionDestination(parent: .group(groupID), index: destinationIndex)
        )
      }
    }
  }

  // Merges only with a same-container neighbor and focuses the retained section.
  private func mergeSection(direction: StructuredNoteMergeDirection) {
    guard
      let retainedSectionID =
        direction == .previous ? item.previousMergeSectionID : Optional(item.id)
    else { return }

    performStructuralChange(
      actionName: "Merge Sections",
      focusSectionID: retainedSectionID,
      caretPlacement: .end
    ) { document in
      _ = try document.mergeSection(id: item.id, direction: direction)
    }
  }

  // Deletes empty sections directly and requires confirmation for content-bearing sections.
  private func requestSectionDeletion() {
    guard item.canDelete else { return }
    if item.section.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      deleteSection()
    } else {
      isConfirmingDeletion = true
    }
  }

  private func deleteSection() {
    let nextFocusID = item.nextVisibleSectionID ?? item.previousVisibleSectionID
    let caretPlacement: StructuredEditorCaretPlacement =
      item.nextVisibleSectionID != nil ? .start : .end
    performStructuralChange(
      actionName: "Delete Section",
      focusSectionID: nextFocusID,
      caretPlacement: caretPlacement
    ) { document in
      try document.deleteSection(id: item.id)
    }
  }

  // Persists all four appearance properties as one undoable section mutation.
  private func updateStyleOverrides(_ styleOverrides: StructuredSectionStyleOverrides) {
    performStructuralChange(
      actionName: "Change Section Appearance",
      focusSectionID: item.id
    ) { document in
      try document.setStyleOverrides(styleOverrides, sectionID: item.id)
    }
  }

  // Applies one validated structural mutation through the shared snapshot undo stack.
  private func performStructuralChange(
    actionName: String,
    focusSectionID: UUID?,
    caretPlacement: StructuredEditorCaretPlacement = .preserve,
    mutate: (inout StructuredNoteDocument) throws -> Void
  ) {
    guard let previousDocument = currentDocument else { return }
    var updatedDocument = previousDocument
    do {
      try mutate(&updatedDocument)
      commitStructuralChange(
        from: previousDocument,
        to: updatedDocument,
        actionName: actionName,
        undoFocusSectionID: item.id,
        focusSectionID: focusSectionID,
        caretPlacement: caretPlacement
      )
    } catch {
      reportStructuralError(error)
    }
  }

  private func commitStructuralChange(
    from previousDocument: StructuredNoteDocument,
    to updatedDocument: StructuredNoteDocument,
    actionName: String,
    undoFocusSectionID: UUID?,
    focusSectionID: UUID?,
    caretPlacement: StructuredEditorCaretPlacement
  ) {
    editorCoordinator.commitStructuralChange(
      from: previousDocument,
      to: updatedDocument,
      actionName: actionName,
      undoFocusTarget: undoFocusSectionID.map {
        StructuredNoteEditorCoordinator.FocusTarget(sectionID: $0)
      },
      redoFocusTarget: focusSectionID.map {
        StructuredNoteEditorCoordinator.FocusTarget(
          sectionID: $0,
          caretPlacement: caretPlacement
        )
      }
    ) { [weak store] document in
      store?.replaceStructuredDocument(document)
    }
    if let focusSectionID {
      editorCoordinator.requestFocus(
        sectionID: focusSectionID,
        caretPlacement: caretPlacement
      )
    }
  }

  private var currentDocument: StructuredNoteDocument? {
    guard store.selectedStructuredNote?.id == documentID else { return nil }
    return store.selectedStructuredNote
  }

  private func reportStructuralError(_ error: Error) {
    store.showTransientMessage(error.localizedDescription, kind: .error)
  }
}

private struct StructuredSectionAppearanceMenu: View {
  let styleOverrides: StructuredSectionStyleOverrides
  let onChange: (StructuredSectionStyleOverrides) -> Void

  var body: some View {
    Menu("Appearance", systemImage: "paintpalette") {
      StructuredColorOverrideMenu(
        title: "Background",
        currentValue: styleOverrides.backgroundColor
      ) { value in
        var updated = styleOverrides
        updated.backgroundColor = value
        onChange(updated)
      }

      StructuredColorOverrideMenu(
        title: "Border",
        currentValue: styleOverrides.borderColor
      ) { value in
        var updated = styleOverrides
        updated.borderColor = value
        onChange(updated)
      }

      StructuredColorOverrideMenu(
        title: "Headings",
        currentValue: styleOverrides.headingColor
      ) { value in
        var updated = styleOverrides
        updated.headingColor = value
        onChange(updated)
      }

      StructuredColorOverrideMenu(
        title: "Bullets",
        currentValue: styleOverrides.bulletColor
      ) { value in
        var updated = styleOverrides
        updated.bulletColor = value
        onChange(updated)
      }
    }
  }
}

private struct StructuredColorOverrideMenu: View {
  let title: String
  let currentValue: StructuredColorOverride
  let onSelect: (StructuredColorOverride) -> Void

  var body: some View {
    Menu(title) {
      option("Inherit", value: .inherit)
      option("Theme Default", value: .themeDefault)

      Divider()

      ForEach(ThemePalette.colors.map(\.name), id: \.self) { colorName in
        option(colorName.capitalized, value: .colorName(colorName))
      }
    }
  }

  private func option(_ title: String, value: StructuredColorOverride) -> some View {
    Button {
      onSelect(value)
    } label: {
      if currentValue == value {
        Label(title, systemImage: "checkmark")
      } else {
        Text(title)
      }
    }
  }
}
