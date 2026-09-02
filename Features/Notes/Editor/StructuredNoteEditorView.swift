//
//  StructuredNoteEditorView.swift
//

// Multi-section daily-note editor backed directly by StructuredNoteDocument values.

import AppKit
import SwiftUI

struct StructuredNoteEditorView: View {
  @Environment(\.openWindow) private var openWindow
  @ObservedObject var store: NotesStore
  var sidebarCollapsed: Bool
  let requestDelete: (DayNote.ID) -> Void
  @StateObject private var editorCoordinator = StructuredNoteEditorCoordinator()
  @State private var activeDragPayload: StructuredNoteDragPayload?
  @State private var activeDropTarget: StructuredNoteDropTarget?
  @State private var isShowingAppearancePopover = false
  @State private var fontPanelController = FontPanelController()

  var body: some View {
    if let document = store.selectedStructuredNote {
      editor(document)
        .onAppear {
          activateEditor(for: document)
        }
        .onChange(of: store.activeStructuredSelectedNoteID) { _, _ in
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
    let editableSectionIDs = items.filter(\.isEditable).map(\.id)
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
      editorCoordinator.updateSectionOrder(editableSectionIDs)
    }
    .onChange(of: editableSectionIDs) { _, sectionIDs in
      editorCoordinator.updateSectionOrder(sectionIDs)
    }
    .onChange(of: store.activeStructuredSearchText) { _, _ in
      guard let selectedDocument = store.selectedStructuredNote else { return }
      revealFirstSearchMatch(in: selectedDocument, requestsFocus: false)
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
    let isListMode = store.sidebarMode == .list
    let controlColor = themeColors.controlBackground.color

    return HStack(alignment: .center, spacing: 12) {
      HStack(spacing: 8) {
        Text(NoteDateFormatters.editorDate.string(from: document.date))
          .font(.callout)
          .foregroundStyle(.secondary)

        if !isListMode, let previousID = adjacentNoteIDs.previous {
          HeaderNavigationButton(
            systemImage: "chevron.left",
            accessibilityLabel: "Open older note",
            controlColor: controlColor
          ) {
            store.selectStructuredNote(previousID)
          }
        }

        if !isListMode, let nextID = adjacentNoteIDs.next {
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

      if !isListMode {
        Button {
          store.selectToday()
        } label: {
          Label("Today", systemImage: "calendar")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
      }

      Button {
        isShowingAppearancePopover.toggle()
      } label: {
        Image(systemName: "slider.vertical.3")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(.secondary)
          .frame(width: 28, height: 28)
          .background(controlColor, in: RoundedRectangle(cornerRadius: 8))
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Open note appearance settings")
      .popover(isPresented: $isShowingAppearancePopover, arrowEdge: .top) {
        QuickAppearancePopover(
          store: store,
          showsStructuredSectionControls: true,
          openSettings: {
            isShowingAppearancePopover = false
            openWindow(id: "settings")
          },
          openFontPanel: openFontPanel,
          confirmDelete: {
            isShowingAppearancePopover = false
            requestDelete(document.id)
          },
          allowsDelete: true
        )
      }
    }
  }

  private var themeColors: ThemeColorSet {
    store.effectiveAppearanceSettings.resolvedColors
  }

  private var accentColor: Color {
    Color(nsColor: store.effectiveAppearanceSettings.accentColor)
  }

  // Reuses the legacy header's quick font picker from the structured appearance popover.
  private func openFontPanel() {
    isShowingAppearancePopover = false
    fontPanelController.present(
      using: store.appearanceSettings,
      onChange: store.updateBodyFontName
    )
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

  // Starts a local move session using a private pasteboard type that editors cannot insert.
  private func beginDrag(_ payload: StructuredNoteDragPayload) -> NSItemProvider {
    activeDragPayload = payload
    activeDropTarget = nil
    return payload.makeItemProvider()
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
              availableGroups: groupDestinations.filter { $0.id != group.id },
              isHiddenByCollapsedGroup: group.isCollapsed
            )
          )
        }
      }
    }

    return items.enumerated().map { index, item in
      var item = item
      item.position = index + 1
      item.previousVisibleSectionID = items[..<index].last(where: \.isEditable)?.id
      if items.indices.contains(index + 1) {
        item.nextVisibleSectionID = items[(index + 1)...].first(where: \.isEditable)?.id
      }
      return item
    }
  }

  private func activateEditor(for document: StructuredNoteDocument) {
    var visibleDocument = document
    let searchMatch = StructuredNoteCollapse.revealFirstSearchMatch(
      for: store.activeStructuredSearchText,
      in: &visibleDocument
    )
    if visibleDocument != document {
      editorCoordinator.invalidateStructuralUndo()
      store.replaceStructuredDocument(visibleDocument)
    }
    let sectionIDs = StructuredNoteCollapse.editableSectionIDs(in: visibleDocument)
    editorCoordinator.activate(
      documentID: visibleDocument.id,
      initialSectionID: searchMatch?.sectionID ?? sectionIDs.first
    )
    editorCoordinator.updateSectionOrder(sectionIDs)
    if let searchMatch, editorCoordinator.focusedSectionID != searchMatch.sectionID {
      editorCoordinator.requestFocus(sectionID: searchMatch.sectionID)
    }
  }

  // Reveals hidden matching content while leaving search-field focus intact during typing.
  private func revealFirstSearchMatch(
    in document: StructuredNoteDocument,
    requestsFocus: Bool
  ) {
    var visibleDocument = document
    guard
      let searchMatch = StructuredNoteCollapse.revealFirstSearchMatch(
        for: store.activeStructuredSearchText,
        in: &visibleDocument
      )
    else { return }

    if visibleDocument != document {
      editorCoordinator.invalidateStructuralUndo()
      store.replaceStructuredDocument(visibleDocument)
    }
    editorCoordinator.updateSectionOrder(
      StructuredNoteCollapse.editableSectionIDs(in: visibleDocument)
    )
    if requestsFocus {
      editorCoordinator.requestFocus(sectionID: searchMatch.sectionID)
    }
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
    HStack(spacing: 7) {
      if isActive {
        Image(systemName: "arrow.down.to.line.compact")
          .font(.system(size: 11, weight: .bold))

        Text(label)
          .font(.system(size: 11, weight: .semibold))
          .fixedSize()
      } else if isAvailable {
        Capsule()
          .fill(accentColor.opacity(0.5))
          .frame(width: 54, height: 2)
      }
    }
    .foregroundStyle(accentColor)
    .padding(.horizontal, 12)
    .frame(maxWidth: .infinity)
    .frame(height: isActive ? 40 : (isAvailable ? 28 : 14))
    .background {
      if isActive {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(accentColor.opacity(0.12))
          .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
              .stroke(
                accentColor.opacity(0.8),
                style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
              )
          }
      } else if isAvailable {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
          .fill(accentColor.opacity(0.04))
      }
    }
    .contentShape(Rectangle())
    .animation(.easeOut(duration: 0.14), value: isActive)
    .onDrop(
      of: [StructuredNoteDragPayload.contentType],
      delegate: StructuredEditorDropDelegate(context: context, target: target)
    )
    .accessibilityHidden(!isActive)
    .accessibilityLabel(label)
  }

  private var isActive: Bool {
    context.activeTarget.wrappedValue == target
  }

  private var isAvailable: Bool {
    guard let payload = context.activePayload.wrappedValue else { return false }
    return context.canDrop(payload, target)
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
    guard let activePayload = context.activePayload.wrappedValue,
      info.hasItemsConforming(to: [StructuredNoteDragPayload.contentType])
    else { return nil }
    return activePayload
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
  let isHiddenByCollapsedGroup: Bool

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
    nextVisibleSectionID: UUID? = nil,
    isHiddenByCollapsedGroup: Bool = false
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
    self.isHiddenByCollapsedGroup = isHiddenByCollapsedGroup
  }

  var id: UUID { section.id }
  var canMoveUp: Bool { indexInContainer > 0 }
  var canMoveDown: Bool { indexInContainer + 1 < containerCount }
  var canDelete: Bool { totalSectionCount > 1 }
  var isEditable: Bool { !section.isCollapsed && !isHiddenByCollapsedGroup }
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
    VStack(alignment: .leading, spacing: 10) {
      groupHeader

      if group.isCollapsed {
        collapsedGroupSummary
      } else {
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
    }
    .padding(12)
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
      Button(action: toggleGroupCollapsed) {
        Image(systemName: group.isCollapsed ? "chevron.right" : "chevron.down")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.secondary)
          .frame(width: 18, height: 24)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(group.isCollapsed ? "Expand \(group.title)" : "Collapse \(group.title)")
      .help(group.isCollapsed ? "Expand group" : "Collapse group")

      Image(systemName: "square.stack.3d.up.fill")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(groupBorderColor)

      if group.displaysTypeLabel {
        VStack(alignment: .leading, spacing: 2) {
          Text("GROUP")
            .font(.system(size: 9, weight: .bold))
            .tracking(1.1)
            .foregroundStyle(.tertiary)

          Text(group.title)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(groupHeadingColor)
        }
      } else {
        Text(group.title)
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(groupHeadingColor)
      }

      if group.displaysSectionCount {
        Text(sectionCountLabel)
          .font(.caption)
          .foregroundStyle(.tertiary)
      }

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
    .frame(minHeight: 30)
  }

  private var groupOptionsMenu: some View {
    Menu {
      Button(
        group.isCollapsed ? "Expand Group" : "Collapse Group",
        systemImage: group.isCollapsed ? "chevron.down" : "chevron.right"
      ) {
        toggleGroupCollapsed()
      }

      Button("Rename Group", systemImage: "pencil") {
        titleDraft = group.title
        isRenaming = true
      }

      StructuredGroupAppearanceMenu(style: group.style, onChange: updateGroupStyle)

      Menu("Header", systemImage: "rectangle.topthird.inset.filled") {
        Toggle(
          "Show Group Label",
          isOn: Binding(
            get: { group.displaysTypeLabel },
            set: { updateGroupHeaderVisibility(showsTypeLabel: $0) }
          )
        )
        Toggle(
          "Show Section Count",
          isOn: Binding(
            get: { group.displaysSectionCount },
            set: { updateGroupHeaderVisibility(showsSectionCount: $0) }
          )
        )
      }

      Divider()

      Button("Undo", systemImage: "arrow.uturn.backward") {
        editorCoordinator.undoStructuralChange()
      }
      .disabled(!editorCoordinator.structuralUndoManager.canUndo)

      Button("Redo", systemImage: "arrow.uturn.forward") {
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

  private var collapsedGroupSummary: some View {
    Button(action: toggleGroupCollapsed) {
      HStack(spacing: 8) {
        Image(systemName: "text.alignleft")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(.tertiary)

        Text(collapsedGroupPreview)
          .font(.system(size: 13))
          .foregroundStyle(.secondary)
          .lineLimit(1)

        Spacer(minLength: 0)
      }
      .padding(.leading, 38)
      .padding(.trailing, 8)
      .padding(.bottom, 4)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Expand \(group.title). Preview: \(collapsedGroupPreview)")
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

  private var collapsedGroupPreview: String {
    let section =
      group.sections.first(where: {
        !$0.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }) ?? group.sections.first
    return section.map { StructuredNoteCollapse.previewText(for: $0.markdown) }
      ?? StructuredNoteCollapse.emptySectionPreview
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

  private func updateGroupHeaderVisibility(
    showsTypeLabel: Bool? = nil,
    showsSectionCount: Bool? = nil
  ) {
    performStructuralChange(actionName: "Change Group Header") { document in
      try document.setGroupHeaderVisibility(
        showsTypeLabel: showsTypeLabel ?? group.displaysTypeLabel,
        showsSectionCount: showsSectionCount ?? group.displaysSectionCount,
        groupID: group.id
      )
    }
  }

  // Collapses children as one unit without changing their independent collapse preferences.
  private func toggleGroupCollapsed() {
    let willCollapse = !group.isCollapsed
    let childIDs = Set(sectionItems.map(\.id))
    let focusedSectionID = editorCoordinator.focusedSectionID
    let focusIsInsideGroup = focusedSectionID.map(childIDs.contains) ?? false
    let adjacentVisibleSectionID =
      sectionItems.last?.nextVisibleSectionID
      ?? sectionItems.first?.previousVisibleSectionID
    let undoFocusTarget = focusedSectionID.map {
      StructuredNoteEditorCoordinator.FocusTarget(sectionID: $0)
    }
    let redoFocusSectionID =
      willCollapse && focusIsInsideGroup ? adjacentVisibleSectionID : focusedSectionID
    let redoFocusTarget = redoFocusSectionID.map {
      StructuredNoteEditorCoordinator.FocusTarget(sectionID: $0)
    }

    performStructuralChange(
      actionName: willCollapse ? "Collapse Group" : "Expand Group",
      undoFocusTarget: undoFocusTarget,
      redoFocusTarget: redoFocusTarget
    ) { document in
      try document.setGroupCollapsed(willCollapse, groupID: group.id)
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
    let focusSectionID =
      editorCoordinator.focusedSectionID.flatMap { focusedSectionID in
        sectionItems.contains(where: { $0.id == focusedSectionID }) ? focusedSectionID : nil
      } ?? sectionItems.first?.id

    let focusTarget = focusSectionID.map {
      StructuredNoteEditorCoordinator.FocusTarget(sectionID: $0)
    }
    performStructuralChange(
      actionName: actionName,
      undoFocusTarget: focusTarget,
      redoFocusTarget: focusTarget,
      mutate: mutate
    )
  }

  // Applies a group mutation with explicit focus targets for hidden-content transitions.
  private func performStructuralChange(
    actionName: String,
    undoFocusTarget: StructuredNoteEditorCoordinator.FocusTarget?,
    redoFocusTarget: StructuredNoteEditorCoordinator.FocusTarget?,
    mutate: (inout StructuredNoteDocument) throws -> Void
  ) {
    guard store.selectedStructuredNote?.id == documentID,
      let previousDocument = store.selectedStructuredNote
    else { return }
    var updatedDocument = previousDocument

    do {
      try mutate(&updatedDocument)
      editorCoordinator.commitStructuralChange(
        from: previousDocument,
        to: updatedDocument,
        actionName: actionName,
        undoFocusTarget: undoFocusTarget,
        redoFocusTarget: redoFocusTarget
      ) { [weak store] document in
        store?.replaceStructuredDocument(document)
      }
      if let redoFocusTarget {
        editorCoordinator.requestFocus(
          sectionID: redoFocusTarget.sectionID,
          caretPlacement: redoFocusTarget.caretPlacement
        )
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
  @State private var isShowingOptionsPopover = false
  @State private var isAppearanceExpanded = false
  @State private var isIndividualColorsExpanded = false
  @State private var groupTitleDraft = "New Group"

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      sectionHeader

      if item.section.isCollapsed {
        collapsedSectionSummary
      } else {
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
            attachmentNoteID: documentID,
            text: store.structuredSectionMarkdownBinding(
              documentID: documentID,
              sectionID: item.id
            ),
            appearanceSettings: store.effectiveAppearanceSettings,
            continuousSpellCheckingEnabled: store.continuousSpellCheckingEnabled,
            searchText: store.activeStructuredSearchText,
            customSlashTemplates: store.enabledSlashCommandTemplates(),
            libraryRootURL: store.libraryLocation.rootURL,
            imageAttachmentRootURL: store.libraryRepository.attachmentsRootURL,
            allowsImageAttachments: true,
            allowsSectionColorEditing: false,
            allowsSlashCommands: true,
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
            onStructuredTemplateInsert: insertTemplate,
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
            },
            onPromptCopied: {
              store.showTransientMessage("Copied", kind: .info)
            }
          )
          .frame(height: editorHeight)
        }
      }
    }
    .background(sectionBackground)
    .overlay {
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .strokeBorder(sectionBorderColor, lineWidth: sectionBorderLineWidth)
    }
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
        setSectionCollapsed(!item.section.isCollapsed)
      } label: {
        Image(systemName: item.section.isCollapsed ? "chevron.right" : "chevron.down")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.secondary)
          .frame(width: 18, height: 24)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(
        item.section.isCollapsed
          ? "Expand section \(item.position)" : "Collapse section \(item.position)"
      )
      .help(item.section.isCollapsed ? "Expand section" : "Collapse section")

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
    .padding(.top, 9)
    .frame(minHeight: 28)
  }

  private var collapsedSectionSummary: some View {
    Button {
      setSectionCollapsed(false)
    } label: {
      HStack(spacing: 8) {
        Image(systemName: "text.alignleft")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(.tertiary)

        Text(collapsedSectionPreview)
          .font(.system(size: 15, weight: .medium))
          .foregroundStyle(.primary)
          .lineLimit(1)

        Spacer(minLength: 0)
      }
      .padding(.horizontal, 28)
      .padding(.top, 4)
      .padding(.bottom, 18)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Expand section. Preview: \(collapsedSectionPreview)")
  }

  private var sectionOptionsMenu: some View {
    Button {
      isShowingOptionsPopover.toggle()
    } label: {
      Image(systemName: "ellipsis")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.secondary)
        .frame(width: 28, height: 24)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .fixedSize()
    .accessibilityLabel("Section \(item.position) options")
    .popover(isPresented: $isShowingOptionsPopover, arrowEdge: .trailing) {
      sectionOptionsPopover
    }
  }

  private var sectionOptionsPopover: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Section options")
        .font(.system(size: 14, weight: .semibold))

      StructuredOptionsActionButton(
        title: item.section.isCollapsed ? "Expand Section" : "Collapse Section",
        systemImage: item.section.isCollapsed ? "chevron.down" : "chevron.right"
      ) {
        performOptionAction {
          setSectionCollapsed(!item.section.isCollapsed)
        }
      }

      StructuredOptionsActionButton(title: "Add Section Below", systemImage: "plus") {
        performOptionAction {
          splitSection(
            markdown: item.section.markdown,
            atUTF16Offset: item.section.markdown.utf16.count
          )
        }
      }

      HStack(spacing: 8) {
        StructuredOptionsActionButton(
          title: "Move Up",
          systemImage: "arrow.up",
          isDisabled: !item.canMoveUp
        ) {
          performOptionAction { moveSection(to: item.indexInContainer - 1) }
        }
        StructuredOptionsActionButton(
          title: "Move Down",
          systemImage: "arrow.down",
          isDisabled: !item.canMoveDown
        ) {
          performOptionAction { moveSection(to: item.indexInContainer + 1) }
        }
      }

      if item.isGrouped {
        StructuredOptionsActionButton(
          title: "Detach from Group",
          systemImage: "rectangle.portrait.and.arrow.right"
        ) {
          performOptionAction(detachSection)
        }
      } else {
        StructuredOptionsActionButton(title: "Create Group", systemImage: "square.stack.3d.up") {
          performOptionAction {
            groupTitleDraft = "New Group"
            isCreatingGroup = true
          }
        }
      }

      if !item.availableGroups.isEmpty {
        Menu {
          ForEach(item.availableGroups) { destination in
            Button(destination.title) {
              performOptionAction { moveSection(toGroup: destination) }
            }
          }
        } label: {
          StructuredOptionsActionLabel(title: "Move to Group", systemImage: "arrow.right")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
      }

      HStack(spacing: 8) {
        StructuredOptionsActionButton(
          title: "Merge Previous",
          systemImage: "arrow.up.to.line",
          isDisabled: item.previousMergeSectionID == nil
        ) {
          performOptionAction { mergeSection(direction: .previous) }
        }
        StructuredOptionsActionButton(
          title: "Merge Next",
          systemImage: "arrow.down.to.line",
          isDisabled: item.nextMergeSectionID == nil
        ) {
          performOptionAction { mergeSection(direction: .next) }
        }
      }

      Divider()

      DisclosureGroup(isExpanded: $isAppearanceExpanded) {
        StructuredSectionAppearanceControls(
          styleOverrides: item.section.styleOverrides,
          inheritanceLabel: item.isGrouped ? "Inherit from Group" : "Inherit from Theme",
          showsIndividualColors: $isIndividualColorsExpanded,
          onChange: updateStyleOverrides
        )
        .padding(.top, 10)
      } label: {
        Label("Appearance", systemImage: "paintpalette")
          .font(.system(size: 12, weight: .semibold))
      }

      Divider()

      HStack(spacing: 8) {
        StructuredOptionsActionButton(
          title: "Undo",
          systemImage: "arrow.uturn.backward",
          isDisabled: !editorCoordinator.structuralUndoManager.canUndo
        ) {
          performOptionAction(editorCoordinator.undoStructuralChange)
        }
        StructuredOptionsActionButton(
          title: "Redo",
          systemImage: "arrow.uturn.forward",
          isDisabled: !editorCoordinator.structuralUndoManager.canRedo
        ) {
          performOptionAction(editorCoordinator.redoStructuralChange)
        }
      }

      StructuredOptionsActionButton(
        title: "Delete Section",
        systemImage: "trash",
        role: .destructive,
        isDisabled: !item.canDelete
      ) {
        performOptionAction(requestSectionDeletion)
      }
    }
    .padding(14)
    .frame(width: 380)
  }

  private func performOptionAction(_ action: () -> Void) {
    isShowingOptionsPopover = false
    action()
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
    RoundedRectangle(cornerRadius: 22, style: .continuous)
      .fill(themeColors.sectionCardFill.color)
  }

  private var sectionBorderColor: Color {
    if let colorName = resolvedStyle.borderColorName,
      let color = ThemePalette.color(named: colorName)
    {
      return Color(nsColor: color).opacity(0.8)
    }
    return themeColors.divider.color
  }

  private var sectionBorderLineWidth: CGFloat {
    isFocused && store.effectiveAppearanceSettings.highlightsFocusedSectionBorder ? 2 : 1.25
  }

  private var collapsedSectionPreview: String {
    StructuredNoteCollapse.previewText(for: item.section.markdown)
  }

  private var normalizedGroupTitleDraft: String {
    groupTitleDraft.split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }

  // Persists collapse through structural undo while moving focus only to editable neighbors.
  private func setSectionCollapsed(_ isCollapsed: Bool) {
    guard item.section.isCollapsed != isCollapsed, let previousDocument = currentDocument else {
      return
    }
    var updatedDocument = previousDocument
    let collapsedFocusSectionID = item.nextVisibleSectionID ?? item.previousVisibleSectionID
    let undoFocusSectionID = item.section.isCollapsed ? collapsedFocusSectionID : item.id
    let redoFocusSectionID = isCollapsed ? collapsedFocusSectionID : item.id

    do {
      try updatedDocument.setSectionCollapsed(isCollapsed, sectionID: item.id)
      commitStructuralChange(
        from: previousDocument,
        to: updatedDocument,
        actionName: isCollapsed ? "Collapse Section" : "Expand Section",
        undoFocusSectionID: undoFocusSectionID,
        focusSectionID: redoFocusSectionID,
        caretPlacement: .preserve
      )
    } catch {
      reportStructuralError(error)
    }
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

  // Replaces a slash row with template content and converts template-owned dividers to sections.
  private func insertTemplate(_ request: StructuredTemplateInsertionRequest) {
    guard let previousDocument = currentDocument else { return }
    var updatedDocument = previousDocument

    do {
      let result = try StructuredNoteTemplateAdapter.insert(
        request,
        replacing: item.section
      )
      try updatedDocument.replaceSection(id: item.id, with: result.sections)
      let focusSection = result.sections.first(where: { $0.id == result.focusSectionID })
      let caretOffset =
        focusSection.map { section in
          let display = MarkdownEditorFormatter.formatForDisplay(
            section.markdown,
            appearance: store.effectiveAppearanceSettings,
            interpretsSectionDirectives: false
          )
          return NoteTemplateCursorResolver.offset(
            in: display,
            placement: request.template.cursorPlacement
          )
        } ?? 0
      commitStructuralChange(
        from: previousDocument,
        to: updatedDocument,
        actionName: "Insert Template",
        undoFocusSectionID: item.id,
        focusSectionID: result.focusSectionID,
        caretPlacement: .offset(caretOffset)
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

  // Persists section color links and independent fallbacks as one undoable mutation.
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

private struct StructuredSectionAppearanceControls: View {
  let styleOverrides: StructuredSectionStyleOverrides
  let inheritanceLabel: String
  @Binding var showsIndividualColors: Bool
  let onChange: (StructuredSectionStyleOverrides) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      StructuredColorOverridePalette(
        title: "Main color",
        currentValue: displayedPrimaryColor,
        inheritanceLabel: inheritanceLabel,
        onSelect: updatePrimaryColor
      )

      VStack(alignment: .leading, spacing: 7) {
        Text("Use main color for")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(.secondary)

        HStack(spacing: 14) {
          colorRoleToggle(.heading, title: "Heading")
          colorRoleToggle(.border, title: "Border")
          colorRoleToggle(.bullet, title: "Bullet points")
        }
      }

      DisclosureGroup("Individual colors", isExpanded: $showsIndividualColors) {
        VStack(alignment: .leading, spacing: 14) {
          if allRolesFollowPrimaryColor {
            Text("Turn off a main-color option to set its individual color.")
              .font(.caption)
              .foregroundStyle(.secondary)
          } else {
            individualColorControl(.heading, title: "Heading")
            individualColorControl(.border, title: "Border")
            individualColorControl(.bullet, title: "Bullet points and checkboxes")
          }
        }
        .padding(.top, 9)
      }
      .font(.system(size: 12, weight: .medium))
    }
  }

  private var displayedPrimaryColor: StructuredColorOverride {
    styleOverrides.primaryColor ?? styleOverrides.headingColor
  }

  @ViewBuilder
  private func colorRoleToggle(
    _ role: StructuredSectionColorRole,
    title: String
  ) -> some View {
    Toggle(
      title,
      isOn: Binding(
        get: { styleOverrides.followsPrimaryColor(role) },
        set: { updateFollowState($0, for: role) }
      )
    )
    .toggleStyle(.checkbox)
    .controlSize(.small)
    .font(.system(size: 11, weight: .medium))
  }

  @ViewBuilder
  private func individualColorControl(
    _ role: StructuredSectionColorRole,
    title: String
  ) -> some View {
    if !styleOverrides.followsPrimaryColor(role) {
      StructuredColorOverridePalette(
        title: "\(title) color",
        currentValue: styleOverrides.independentColorOverride(for: role),
        inheritanceLabel: inheritanceLabel
      ) { color in
        var updated = styleOverrides
        updated.setIndependentColorOverride(color, for: role)
        onChange(updated)
      }
    }
  }

  private var allRolesFollowPrimaryColor: Bool {
    StructuredSectionColorRole.allCases.allSatisfy(styleOverrides.followsPrimaryColor)
  }

  // Preserves existing independent choices while changing every linked role immediately.
  private func updatePrimaryColor(_ color: StructuredColorOverride) {
    var updated = styleOverrides
    updated.setPrimaryColor(color)
    onChange(updated)
  }

  // Materializes legacy inferred links before changing one persisted follow toggle.
  private func updateFollowState(
    _ followsPrimaryColor: Bool,
    for role: StructuredSectionColorRole
  ) {
    var updated = styleOverrides
    if updated.primaryColor == nil {
      updated.setPrimaryColor(displayedPrimaryColor)
    }
    updated.setFollowsPrimaryColor(followsPrimaryColor, for: role)
    onChange(updated)
  }
}

private struct StructuredOptionsActionButton: View {
  let title: String
  let systemImage: String
  var role: ButtonRole? = nil
  var isDisabled = false
  let action: () -> Void

  var body: some View {
    Button(role: role, action: action) {
      StructuredOptionsActionLabel(title: title, systemImage: systemImage)
    }
    .buttonStyle(.plain)
    .disabled(isDisabled)
    .opacity(isDisabled ? 0.45 : 1)
    .frame(maxWidth: .infinity)
  }
}

private struct StructuredOptionsActionLabel: View {
  let title: String
  let systemImage: String

  var body: some View {
    Label(title, systemImage: systemImage)
      .font(.system(size: 11, weight: .medium))
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 9)
      .padding(.vertical, 7)
      .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
      .contentShape(Rectangle())
  }
}

private struct StructuredColorOverridePalette: View {
  let title: String
  let currentValue: StructuredColorOverride
  let inheritanceLabel: String
  let onSelect: (StructuredColorOverride) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      Text(title)
        .font(.system(size: 12, weight: .medium))

      HStack(spacing: 8) {
        textOption(inheritanceLabel, value: .inherit)
        textOption("Theme default", value: .themeDefault)
      }

      HStack(spacing: 10) {
        ForEach(ThemePalette.colors, id: \.name) { entry in
          Button {
            onSelect(.colorName(entry.name))
          } label: {
            Circle()
              .fill(Color(nsColor: entry.color))
              .frame(width: 20, height: 20)
              .overlay {
                Circle()
                  .strokeBorder(
                    paletteBorderColor(for: entry.name),
                    lineWidth: currentValue == .colorName(entry.name) ? 2 : 1
                  )
              }
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Use \(entry.name) for \(title.lowercased())")
        }
      }
    }
  }

  private func textOption(
    _ label: String,
    value: StructuredColorOverride
  ) -> some View {
    Button {
      onSelect(value)
    } label: {
      HStack(spacing: 5) {
        if currentValue == value {
          Image(systemName: "checkmark")
            .font(.system(size: 9, weight: .bold))
        }
        Text(label)
          .lineLimit(1)
      }
      .font(.system(size: 11, weight: .medium))
      .padding(.horizontal, 9)
      .padding(.vertical, 5)
      .background(
        currentValue == value ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08),
        in: Capsule()
      )
    }
    .buttonStyle(.plain)
  }

  private func paletteBorderColor(for colorName: String) -> Color {
    if currentValue == .colorName(colorName) {
      return .primary
    }
    return colorName == "white" ? Color.primary.opacity(0.2) : .clear
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
