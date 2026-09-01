//
//  StructuredNoteEditorView.swift
//

// Multi-section daily-note editor backed directly by StructuredNoteDocument values.

import SwiftUI
import UniformTypeIdentifiers

struct StructuredNoteEditorView: View {
  @Environment(\.openWindow) private var openWindow
  @ObservedObject var store: NotesStore
  var sidebarCollapsed: Bool
  @StateObject private var editorCoordinator = StructuredNoteEditorCoordinator()
  @State private var activeDragPayload: StructuredNoteDragPayload?
  @State private var activeDropTarget: StructuredNoteDropTarget?

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
    let itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    let dragContext = dragContext(for: document.id)

    return VStack(alignment: .leading, spacing: 12) {
      editorHeader(document)
        .padding(.leading, sidebarCollapsed ? 130 : 0)

      TextField("Title", text: store.structuredTitleBinding(for: document.id), axis: .vertical)
        .textFieldStyle(.plain)
        .font(.system(size: 30, weight: .bold))
        .lineLimit(1...3)

      ScrollViewReader { scrollProxy in
        ScrollView {
          VStack(spacing: 0) {
            StructuredEditorDropZone(
              context: dragContext,
              target: .root(insertionIndex: 0),
              label: rootDropLabel(for: activeDragPayload, in: document),
              accentColor: accentColor
            )

            ForEach(Array(document.nodes.enumerated()), id: \.element.id) {
              rootNodeIndex,
              node in
              editorNode(
                node,
                rootNodeIndex: rootNodeIndex,
                documentID: document.id,
                itemsByID: itemsByID,
                dragContext: dragContext
              )

              StructuredEditorDropZone(
                context: dragContext,
                target: .root(insertionIndex: rootNodeIndex + 1),
                label: rootDropLabel(for: activeDragPayload, in: document),
                accentColor: accentColor
              )
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
    .onDisappear {
      activeDragPayload = nil
      activeDropTarget = nil
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

  private var accentColor: Color {
    Color(nsColor: store.effectiveAppearanceSettings.accentColor)
  }

  @ViewBuilder
  // Preserves root group boundaries while building the visible editor hierarchy.
  private func editorNode(
    _ node: StructuredNoteNode,
    rootNodeIndex: Int,
    documentID: String,
    itemsByID: [UUID: StructuredEditorSectionItem],
    dragContext: StructuredEditorDragContext
  ) -> some View {
    switch node {
    case .section(let section):
      if let item = itemsByID[section.id] {
        StructuredSectionEditorCard(
          store: store,
          editorCoordinator: editorCoordinator,
          documentID: documentID,
          item: item,
          dragContext: dragContext
        )
        .id(item.id)
      }

    case .group(let group):
      StructuredSectionGroupContainer(
        store: store,
        editorCoordinator: editorCoordinator,
        documentID: documentID,
        group: group,
        rootNodeIndex: rootNodeIndex,
        sectionItems: group.sections.compactMap { itemsByID[$0.id] },
        dragContext: dragContext,
        accentColor: accentColor
      )
      .id(group.id)
    }
  }

  // Shares one local drag session across root and nested group insertion targets.
  private func dragContext(for documentID: String) -> StructuredEditorDragContext {
    StructuredEditorDragContext(
      activePayload: $activeDragPayload,
      activeTarget: $activeDropTarget,
      beginDrag: beginDrag,
      canDrop: { payload, target in
        guard store.selectedStructuredNote?.id == documentID,
          let document = store.selectedStructuredNote
        else { return false }
        return StructuredNoteDragDrop.canApply(payload, to: target, in: document)
      },
      performDrop: { payload, target in
        performDrop(payload, to: target, documentID: documentID)
      }
    )
  }

  // Starts a local move session while still publishing a typed plain-text provider payload.
  private func beginDrag(_ payload: StructuredNoteDragPayload) -> NSItemProvider {
    activeDragPayload = payload
    activeDropTarget = nil
    let itemProvider = NSItemProvider(object: payload.encodedValue as NSString)
    itemProvider.suggestedName = payload.encodedValue
    return itemProvider
  }

  // Commits a successful resolved drop through the existing structural undo stack.
  private func performDrop(
    _ payload: StructuredNoteDragPayload,
    to target: StructuredNoteDropTarget,
    documentID: String
  ) -> Bool {
    guard store.selectedStructuredNote?.id == documentID,
      let previousDocument = store.selectedStructuredNote
    else { return false }
    var updatedDocument = previousDocument

    do {
      let result = try StructuredNoteDragDrop.apply(payload, to: target, in: &updatedDocument)
      guard result.didChange else { return false }
      let focusTarget = result.focusedSectionID.map {
        StructuredNoteEditorCoordinator.FocusTarget(sectionID: $0)
      }
      editorCoordinator.commitStructuralChange(
        from: previousDocument,
        to: updatedDocument,
        actionName: dragActionName(for: payload),
        undoFocusTarget: focusTarget,
        redoFocusTarget: focusTarget
      ) { [weak store] document in
        store?.replaceStructuredDocument(document)
      }
      if let focusedSectionID = result.focusedSectionID {
        editorCoordinator.requestFocus(sectionID: focusedSectionID)
      }
      return true
    } catch {
      store.showTransientMessage(error.localizedDescription, kind: .error)
      return false
    }
  }

  // Names section moves and top-level group reorders distinctly in the Edit menu.
  private func dragActionName(for payload: StructuredNoteDragPayload) -> String {
    switch payload {
    case .section:
      return "Move Section"
    case .group:
      return "Move Group"
    }
  }

  // Describes root targets as detach locations when the source belongs to a group.
  private func rootDropLabel(
    for payload: StructuredNoteDragPayload?,
    in document: StructuredNoteDocument
  ) -> String {
    switch payload {
    case .section(let sectionID) where isGroupedSection(sectionID, in: document):
      return "Detach section here"
    case .section:
      return "Move section here"
    case .group:
      return "Move group here"
    case nil:
      return "Move here"
    }
  }

  // Detects whether a section-to-root drop changes group membership.
  private func isGroupedSection(
    _ sectionID: UUID,
    in document: StructuredNoteDocument
  ) -> Bool {
    document.nodes.contains { node in
      guard case .group(let group) = node else { return false }
      return group.sections.contains(where: { $0.id == sectionID })
    }
  }

  // Flattens root and grouped sections while retaining their structural action context.
  private func sectionItems(in document: StructuredNoteDocument) -> [StructuredEditorSectionItem] {
    var items: [StructuredEditorSectionItem] = []
    let groupDestinations = document.nodes.compactMap { node -> StructuredEditorGroupDestination? in
      guard case .group(let group) = node else { return nil }
      return StructuredEditorGroupDestination(
        id: group.id,
        title: group.title,
        insertionIndex: group.sections.count
      )
    }
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
            groupStyle: nil,
            indexInContainer: rootNodeIndex,
            containerCount: document.nodes.count,
            totalSectionCount: totalSectionCount,
            previousMergeSectionID: previousMergeID,
            nextMergeSectionID: nextMergeID,
            availableGroups: groupDestinations
          )
        )

      case .group(let group):
        for (sectionIndex, section) in group.sections.enumerated() {
          items.append(
            StructuredEditorSectionItem(
              section: section,
              parent: .group(group.id),
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
                : nil,
              availableGroups: groupDestinations.filter { $0.id != group.id }
            )
          )
        }
      }
    }

    return items.enumerated().map { index, item in
      var item = item
      item.position = index + 1
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

private struct StructuredEditorDragContext {
  let activePayload: Binding<StructuredNoteDragPayload?>
  let activeTarget: Binding<StructuredNoteDropTarget?>
  let beginDrag: (StructuredNoteDragPayload) -> NSItemProvider
  let canDrop: (StructuredNoteDragPayload, StructuredNoteDropTarget) -> Bool
  let performDrop: (StructuredNoteDragPayload, StructuredNoteDropTarget) -> Bool
}

private struct StructuredEditorDropZone: View {
  let context: StructuredEditorDragContext
  let target: StructuredNoteDropTarget
  let label: String
  let accentColor: Color

  var body: some View {
    HStack(spacing: 8) {
      Capsule()
        .fill(isActive ? accentColor : .clear)
        .frame(height: 2)

      if isActive {
        Text(label)
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(accentColor)
          .fixedSize()
      }
    }
    .padding(.horizontal, 10)
    .frame(maxWidth: .infinity)
    .frame(height: 18)
    .contentShape(Rectangle())
    .animation(.easeOut(duration: 0.12), value: isActive)
    .onDrop(
      of: [UTType.plainText],
      delegate: StructuredEditorDropDelegate(context: context, target: target)
    )
    .accessibilityHidden(!isActive)
    .accessibilityLabel(label)
  }

  private var isActive: Bool {
    context.activeTarget.wrappedValue == target
  }
}

private struct StructuredEditorDropDelegate: DropDelegate {
  let context: StructuredEditorDragContext
  let target: StructuredNoteDropTarget

  // Accepts only the active local payload and a target that produces a real mutation.
  func validateDrop(info: DropInfo) -> Bool {
    guard let payload = localPayload(in: info) else { return false }
    return context.canDrop(payload, target)
  }

  // Activates the insertion line only for a currently valid move.
  func dropEntered(info: DropInfo) {
    guard let payload = localPayload(in: info),
      context.canDrop(payload, target)
    else { return }
    context.activeTarget.wrappedValue = target
  }

  func dropUpdated(info: DropInfo) -> DropProposal? {
    guard let payload = localPayload(in: info),
      context.canDrop(payload, target)
    else { return DropProposal(operation: .forbidden) }
    return DropProposal(operation: .move)
  }

  func dropExited(info: DropInfo) {
    guard context.activeTarget.wrappedValue == target else { return }
    context.activeTarget.wrappedValue = nil
  }

  // Clears the local session whether the resolved move succeeds or is rejected.
  func performDrop(info: DropInfo) -> Bool {
    guard let payload = localPayload(in: info),
      context.canDrop(payload, target)
    else {
      context.activeTarget.wrappedValue = nil
      context.activePayload.wrappedValue = nil
      return false
    }

    let didMove = context.performDrop(payload, target)
    context.activeTarget.wrappedValue = nil
    context.activePayload.wrappedValue = nil
    return didMove
  }

  // Matches the provider to this editor session so a cancelled drag cannot authorize a later one.
  private func localPayload(in info: DropInfo) -> StructuredNoteDragPayload? {
    guard let activePayload = context.activePayload.wrappedValue else { return nil }
    return info.itemProviders(for: [.plainText])
      .compactMap(\.suggestedName)
      .compactMap(StructuredNoteDragPayload.init(encodedValue:))
      .first(where: { $0 == activePayload })
  }
}

private struct StructuredEditorDragHandle: View {
  let accessibilityLabel: String
  let itemProvider: () -> NSItemProvider

  var body: some View {
    Image(systemName: "line.3.horizontal")
      .font(.system(size: 12, weight: .semibold))
      .foregroundStyle(.tertiary)
      .frame(width: 24, height: 24)
      .contentShape(Rectangle())
      .onDrag(itemProvider)
      .help("Drag to move")
      .accessibilityLabel(accessibilityLabel)
  }
}

private struct StructuredEditorGroupDestination: Identifiable {
  let id: UUID
  let title: String
  let insertionIndex: Int
}

private struct StructuredEditorSectionItem: Identifiable {
  let section: StructuredNoteSection
  let parent: StructuredNoteSectionParent
  let groupStyle: StructuredSectionStyle?
  let indexInContainer: Int
  let containerCount: Int
  let totalSectionCount: Int
  let previousMergeSectionID: UUID?
  let nextMergeSectionID: UUID?
  let availableGroups: [StructuredEditorGroupDestination]
  var position = 1
  var previousVisibleSectionID: UUID?
  var nextVisibleSectionID: UUID?

  init(
    section: StructuredNoteSection,
    parent: StructuredNoteSectionParent,
    groupStyle: StructuredSectionStyle?,
    indexInContainer: Int,
    containerCount: Int,
    totalSectionCount: Int,
    previousMergeSectionID: UUID?,
    nextMergeSectionID: UUID?,
    availableGroups: [StructuredEditorGroupDestination],
    position: Int = 1,
    previousVisibleSectionID: UUID? = nil,
    nextVisibleSectionID: UUID? = nil
  ) {
    self.section = section
    self.parent = parent
    self.groupStyle = groupStyle
    self.indexInContainer = indexInContainer
    self.containerCount = containerCount
    self.totalSectionCount = totalSectionCount
    self.previousMergeSectionID = previousMergeSectionID
    self.nextMergeSectionID = nextMergeSectionID
    self.availableGroups = availableGroups
    self.position = position
    self.previousVisibleSectionID = previousVisibleSectionID
    self.nextVisibleSectionID = nextVisibleSectionID
  }

  var id: UUID { section.id }
  var canMoveUp: Bool { indexInContainer > 0 }
  var canMoveDown: Bool { indexInContainer + 1 < containerCount }
  var canDelete: Bool { totalSectionCount > 1 }
  var isGrouped: Bool {
    guard case .group = parent else { return false }
    return true
  }
}

private struct StructuredSectionGroupContainer: View {
  @ObservedObject var store: NotesStore
  @ObservedObject var editorCoordinator: StructuredNoteEditorCoordinator
  let documentID: String
  let group: StructuredSectionGroup
  let rootNodeIndex: Int
  let sectionItems: [StructuredEditorSectionItem]
  let dragContext: StructuredEditorDragContext
  let accentColor: Color
  @State private var isHovering = false
  @State private var isRenaming = false
  @State private var titleDraft = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      groupHeader

      VStack(spacing: 0) {
        StructuredEditorDropZone(
          context: dragContext,
          target: .group(groupID: group.id, insertionIndex: 0),
          label: "Move into \(group.title)",
          accentColor: accentColor
        )

        ForEach(Array(sectionItems.enumerated()), id: \.element.id) { index, item in
          StructuredSectionEditorCard(
            store: store,
            editorCoordinator: editorCoordinator,
            documentID: documentID,
            item: item,
            dragContext: dragContext
          )
          .id(item.id)

          StructuredEditorDropZone(
            context: dragContext,
            target: .group(groupID: group.id, insertionIndex: index + 1),
            label: "Move into \(group.title)",
            accentColor: accentColor
          )
        }
      }
    }
    .padding(14)
    .background(groupBackground)
    .overlay(
      RoundedRectangle(cornerRadius: 28, style: .continuous)
        .strokeBorder(groupBorderColor, lineWidth: 1.5)
    )
    .onHover { isHovering = $0 }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Group \(rootNodeIndex + 1): \(group.title)")
    .alert("Rename Group", isPresented: $isRenaming) {
      TextField("Group name", text: $titleDraft)
      Button("Rename") {
        renameGroup()
      }
      .disabled(normalizedTitleDraft.isEmpty)
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("The group name is exported as a Markdown heading.")
    }
  }

  private var groupHeader: some View {
    HStack(spacing: 10) {
      Image(systemName: "square.stack.3d.up.fill")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(groupBorderColor)

      VStack(alignment: .leading, spacing: 2) {
        Text("GROUP")
          .font(.system(size: 9, weight: .bold))
          .tracking(1.1)
          .foregroundStyle(.tertiary)

        Text(group.title)
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(groupHeadingColor)
      }

      Text(sectionCountLabel)
        .font(.caption)
        .foregroundStyle(.tertiary)

      Spacer()

      StructuredEditorDragHandle(accessibilityLabel: "Move \(group.title) group") {
        dragContext.beginDrag(.group(group.id))
      }
      .opacity(isHovering || containsFocusedSection ? 1 : 0)
      .allowsHitTesting(isHovering || containsFocusedSection)

      groupOptionsMenu
        .opacity(isHovering || containsFocusedSection ? 1 : 0)
        .allowsHitTesting(isHovering || containsFocusedSection)
    }
    .padding(.horizontal, 6)
    .padding(.top, 2)
  }

  private var groupOptionsMenu: some View {
    Menu {
      Button("Rename Group", systemImage: "pencil") {
        titleDraft = group.title
        isRenaming = true
      }

      StructuredGroupAppearanceMenu(style: group.style, onChange: updateGroupStyle)

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

      Button("Ungroup Sections", systemImage: "square.stack.3d.up.slash") {
        ungroupSections()
      }
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
    .accessibilityLabel("\(group.title) group options")
  }

  private var normalizedTitleDraft: String {
    titleDraft.split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }

  private var sectionCountLabel: String {
    sectionItems.count == 1 ? "1 section" : "\(sectionItems.count) sections"
  }

  private var containsFocusedSection: Bool {
    guard let focusedSectionID = editorCoordinator.focusedSectionID else { return false }
    return sectionItems.contains(where: { $0.id == focusedSectionID })
  }

  private var themeColors: ThemeColorSet {
    store.effectiveAppearanceSettings.resolvedColors
  }

  private var groupBackground: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 28, style: .continuous)
        .fill(themeColors.sectionCardFill.color.opacity(0.45))
      if let colorName = group.style.backgroundColorName,
        let color = ThemePalette.color(named: colorName)
      {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
          .fill(Color(nsColor: color).opacity(0.12))
      }
    }
  }

  private var groupBorderColor: Color {
    guard let colorName = group.style.borderColorName,
      let color = ThemePalette.color(named: colorName)
    else {
      return themeColors.divider.color
    }
    return Color(nsColor: color).opacity(0.85)
  }

  private var groupHeadingColor: Color {
    guard let colorName = group.style.headingColorName,
      let color = ThemePalette.color(named: colorName)
    else { return .primary }
    return Color(nsColor: color)
  }

  // Normalizes the semantic title to the single-line heading used by portable export.
  private func renameGroup() {
    let title = normalizedTitleDraft
    guard !title.isEmpty else { return }
    performStructuralChange(actionName: "Rename Group") { document in
      try document.setGroupTitle(title, groupID: group.id)
    }
  }

  // Stores group defaults without copying them into individual child overrides.
  private func updateGroupStyle(_ style: StructuredSectionStyle) {
    performStructuralChange(actionName: "Change Group Appearance") { document in
      try document.setGroupStyle(style, groupID: group.id)
    }
  }

  // Lifts every child into the group's root position without changing child state.
  private func ungroupSections() {
    performStructuralChange(actionName: "Ungroup Sections") { document in
      try document.ungroup(id: group.id)
    }
  }

  // Applies one group mutation while retaining a valid child focus for undo and redo.
  private func performStructuralChange(
    actionName: String,
    mutate: (inout StructuredNoteDocument) throws -> Void
  ) {
    guard store.selectedStructuredNote?.id == documentID,
      let previousDocument = store.selectedStructuredNote
    else { return }
    var updatedDocument = previousDocument
    let focusSectionID =
      editorCoordinator.focusedSectionID.flatMap { focusedSectionID in
        sectionItems.contains(where: { $0.id == focusedSectionID }) ? focusedSectionID : nil
      } ?? sectionItems.first?.id

    do {
      try mutate(&updatedDocument)
      let focusTarget = focusSectionID.map {
        StructuredNoteEditorCoordinator.FocusTarget(sectionID: $0)
      }
      editorCoordinator.commitStructuralChange(
        from: previousDocument,
        to: updatedDocument,
        actionName: actionName,
        undoFocusTarget: focusTarget,
        redoFocusTarget: focusTarget
      ) { [weak store] document in
        store?.replaceStructuredDocument(document)
      }
      if let focusSectionID {
        editorCoordinator.requestFocus(sectionID: focusSectionID)
      }
    } catch {
      store.showTransientMessage(error.localizedDescription, kind: .error)
    }
  }
}

private struct StructuredSectionEditorCard: View {
  @ObservedObject var store: NotesStore
  @ObservedObject var editorCoordinator: StructuredNoteEditorCoordinator
  let documentID: String
  let item: StructuredEditorSectionItem
  let dragContext: StructuredEditorDragContext
  @State private var editorHeight: CGFloat = 132
  @State private var isHovering = false
  @State private var isConfirmingDeletion = false
  @State private var isCreatingGroup = false
  @State private var groupTitleDraft = "New Group"

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
    .alert("Create Group", isPresented: $isCreatingGroup) {
      TextField("Group name", text: $groupTitleDraft)
      Button("Create") {
        createGroup()
      }
      .disabled(normalizedGroupTitleDraft.isEmpty)
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This section becomes the first item in the new group without changing its content.")
    }
  }

  private var sectionHeader: some View {
    HStack(spacing: 8) {
      Button {
        editorCoordinator.requestFocus(sectionID: item.id)
      } label: {
        Text("Section \(item.position)")
          .font(.caption.weight(.semibold))
          .foregroundStyle(isFocused ? accentColor : Color(nsColor: .secondaryLabelColor))
      }
      .buttonStyle(.plain)

      Spacer()

      StructuredEditorDragHandle(accessibilityLabel: "Move section \(item.position)") {
        dragContext.beginDrag(.section(item.id))
      }
      .opacity(isHovering || isFocused ? 1 : 0)
      .allowsHitTesting(isHovering || isFocused)

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

      if item.isGrouped {
        Button("Detach from Group", systemImage: "rectangle.portrait.and.arrow.right") {
          detachSection()
        }
      } else {
        Button("Create Group", systemImage: "square.stack.3d.up") {
          groupTitleDraft = "New Group"
          isCreatingGroup = true
        }
      }

      if !item.availableGroups.isEmpty {
        Menu("Move to Group", systemImage: "arrow.right") {
          ForEach(item.availableGroups) { destination in
            Button(destination.title) {
              moveSection(toGroup: destination)
            }
          }
        }
      }

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
        inheritanceLabel: item.isGrouped ? "Inherit from Group" : "Inherit from Theme",
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
    .accessibilityLabel("Section \(item.position) options")
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

  private var normalizedGroupTitleDraft: String {
    groupTitleDraft.split(whereSeparator: \.isWhitespace).joined(separator: " ")
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

  // Wraps a root section in a semantic group without changing the section itself.
  private func createGroup() {
    let title = normalizedGroupTitleDraft
    guard !title.isEmpty, !item.isGrouped else { return }
    performStructuralChange(actionName: "Create Group", focusSectionID: item.id) { document in
      _ = try document.createGroup(title: title, aroundSectionID: item.id)
    }
  }

  // Appends a section to another group while retaining content, identity, and overrides.
  private func moveSection(toGroup destination: StructuredEditorGroupDestination) {
    performStructuralChange(actionName: "Move Section to Group", focusSectionID: item.id) {
      document in
      try document.moveSection(
        id: item.id,
        to: StructuredNoteSectionDestination(
          parent: .group(destination.id),
          index: destination.insertionIndex
        )
      )
    }
  }

  // Places a grouped section immediately after its group at the root level.
  private func detachSection() {
    guard item.isGrouped else { return }
    performStructuralChange(actionName: "Detach Section", focusSectionID: item.id) { document in
      try document.detachSection(id: item.id)
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
  let inheritanceLabel: String
  let onChange: (StructuredSectionStyleOverrides) -> Void

  var body: some View {
    Menu("Appearance", systemImage: "paintpalette") {
      StructuredColorOverrideMenu(
        title: "Background",
        currentValue: styleOverrides.backgroundColor,
        inheritanceLabel: inheritanceLabel
      ) { value in
        var updated = styleOverrides
        updated.backgroundColor = value
        onChange(updated)
      }

      StructuredColorOverrideMenu(
        title: "Border",
        currentValue: styleOverrides.borderColor,
        inheritanceLabel: inheritanceLabel
      ) { value in
        var updated = styleOverrides
        updated.borderColor = value
        onChange(updated)
      }

      StructuredColorOverrideMenu(
        title: "Headings",
        currentValue: styleOverrides.headingColor,
        inheritanceLabel: inheritanceLabel
      ) { value in
        var updated = styleOverrides
        updated.headingColor = value
        onChange(updated)
      }

      StructuredColorOverrideMenu(
        title: "Bullets",
        currentValue: styleOverrides.bulletColor,
        inheritanceLabel: inheritanceLabel
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
  let inheritanceLabel: String
  let onSelect: (StructuredColorOverride) -> Void

  var body: some View {
    Menu(title) {
      option(inheritanceLabel, value: .inherit)
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

private struct StructuredGroupAppearanceMenu: View {
  let style: StructuredSectionStyle
  let onChange: (StructuredSectionStyle) -> Void

  var body: some View {
    Menu("Appearance", systemImage: "paintpalette") {
      StructuredGroupColorMenu(title: "Background", currentValue: style.backgroundColorName) {
        value in
        var updated = style
        updated.backgroundColorName = value
        onChange(updated)
      }

      StructuredGroupColorMenu(title: "Border", currentValue: style.borderColorName) { value in
        var updated = style
        updated.borderColorName = value
        onChange(updated)
      }

      StructuredGroupColorMenu(title: "Headings", currentValue: style.headingColorName) { value in
        var updated = style
        updated.headingColorName = value
        onChange(updated)
      }

      StructuredGroupColorMenu(title: "Bullets", currentValue: style.bulletColorName) { value in
        var updated = style
        updated.bulletColorName = value
        onChange(updated)
      }
    }
  }
}

private struct StructuredGroupColorMenu: View {
  let title: String
  let currentValue: String?
  let onSelect: (String?) -> Void

  var body: some View {
    Menu(title) {
      option("Theme Default", value: nil)

      Divider()

      ForEach(ThemePalette.colors.map(\.name), id: \.self) { colorName in
        option(colorName.capitalized, value: colorName)
      }
    }
  }

  // Marks the active group default while keeping theme fallback represented as nil.
  private func option(_ title: String, value: String?) -> some View {
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
