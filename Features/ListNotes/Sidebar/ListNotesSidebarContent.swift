//
//  ListNotesSidebarContent.swift
//

// Sidebar content for list mode — shows ungrouped notes and collapsible groups
// with drag-and-drop reordering for both notes and groups.

import SwiftUI
import UniformTypeIdentifiers

struct ListNotesSidebarContent: View {
  @ObservedObject var store: NotesStore
  let requestDelete: (DayNote.ID) -> Void

  // Prefix used to distinguish group drags from note drags in plain-text payloads.
  static let groupDragPrefix = "group:"

  @State private var isShowingNewGroupAlert = false
  @State private var newGroupName = ""
  @State private var renamingGroupID: String?

  var body: some View {
    let manifest = store.listNoteManifest
    let isSearching = store.isListSearchActive
    let filteredIDs = Set(store.filteredListNotes.map(\.id))

    ZStack(alignment: .top) {
      if manifest.isEmpty, !isSearching {
        ListSidebarEmptyStateView {
          store.createListNote()
        }
      } else if store.filteredListNotes.isEmpty, isSearching {
        VStack {
          Spacer()
          Text("No matching notes")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
          Spacer()
        }
        .frame(maxWidth: .infinity)
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 10) {
            // Add note + new group buttons
            HStack(spacing: 8) {
              AddListNoteButton(accentColor: sidebarAccentColor) {
                store.createListNote()
              }

              NewGroupButton(accentColor: sidebarAccentColor) {
                renamingGroupID = nil
                newGroupName = ""
                isShowingNewGroupAlert = true
              }
            }

            // Ungrouped section drop target (accepts notes dragged here)
            let ungroupedNotes =
              isSearching
              ? manifest.ungroupedNoteIDs.filter { filteredIDs.contains($0) }
              : manifest.ungroupedNoteIDs

            if !ungroupedNotes.isEmpty || !isSearching {
              // Drop zone at the top of ungrouped — inserts at index 0.
              UngroupedDropZone()
                .onDrop(
                  of: [UTType.plainText],
                  delegate: NoteDropDelegate(
                    store: store,
                    targetGroupID: nil,
                    targetIndex: 0
                  ))
            }

            ForEach(Array(ungroupedNotes.enumerated()), id: \.element) { offset, noteID in
              if let note = store.listNote(withID: noteID) {
                listNoteButton(note: note)
                  .onDrag {
                    NSItemProvider(object: note.id as NSString)
                  }
                  .onDrop(
                    of: [UTType.plainText],
                    delegate: NoteDropDelegate(
                      store: store,
                      targetGroupID: nil,
                      targetIndex: offset + 1
                    ))
              }
            }

            // Groups
            ForEach(Array(manifest.groups.enumerated()), id: \.element.id) { groupOffset, group in
              let groupNoteIDs =
                isSearching
                ? group.noteIDs.filter { filteredIDs.contains($0) }
                : group.noteIDs

              if !isSearching || !groupNoteIDs.isEmpty {
                GroupHeaderView(
                  group: group,
                  noteCount: groupNoteIDs.count,
                  accentColor: sidebarAccentColor,
                  dividerColor: themeColors.divider.color
                ) {
                  store.toggleGroupCollapsed(groupID: group.id)
                }
                .onDrag {
                  NSItemProvider(object: ("\(Self.groupDragPrefix)\(group.id)" as NSString))
                }
                .onDrop(
                  of: [UTType.plainText],
                  delegate: GroupHeaderDropDelegate(
                    store: store,
                    targetGroupID: group.id,
                    groupIndex: groupOffset
                  )
                )
                .contextMenu {
                  Button {
                    renamingGroupID = group.id
                    newGroupName = group.name
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                      isShowingNewGroupAlert = true
                    }
                  } label: {
                    Label("Rename group…", systemImage: "pencil")
                  }

                  Button(role: .destructive) {
                    store.deleteGroup(groupID: group.id)
                  } label: {
                    Label("Delete group", systemImage: "trash")
                  }
                }

                if !group.isCollapsed {
                  ForEach(Array(groupNoteIDs.enumerated()), id: \.element) { noteOffset, noteID in
                    if let note = store.listNote(withID: noteID) {
                      listNoteButton(note: note)
                        .onDrag {
                          NSItemProvider(object: note.id as NSString)
                        }
                        .onDrop(
                          of: [UTType.plainText],
                          delegate: NoteDropDelegate(
                            store: store,
                            targetGroupID: group.id,
                            targetIndex: noteOffset + 1
                          ))
                    }
                  }

                  // Drop zone at the end of a group when it has notes — appends.
                  if !groupNoteIDs.isEmpty {
                    Color.clear
                      .frame(height: 2)
                      .onDrop(
                        of: [UTType.plainText],
                        delegate: NoteDropDelegate(
                          store: store,
                          targetGroupID: group.id,
                          targetIndex: groupNoteIDs.count
                        ))
                  }
                }
              }
            }
          }
          .padding(.bottom, 20)
        }
        .scrollIndicators(
          store.appearanceSettings.showEditorScrollbar ? .visible : .hidden
        )
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .alert("Group name", isPresented: $isShowingNewGroupAlert) {
      TextField("Name", text: $newGroupName)
      Button("Cancel", role: .cancel) {
        renamingGroupID = nil
      }
      Button("OK") {
        let trimmed = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let groupID = renamingGroupID {
          store.renameGroup(groupID: groupID, name: trimmed)
        } else if !store.listNoteManifest.groups.contains(where: { $0.name == trimmed }) {
          store.createGroup(name: trimmed)
        }
        renamingGroupID = nil
      }
    }
  }

  @ViewBuilder
  private func listNoteButton(note: DayNote) -> some View {
    Button {
      store.selectedListNoteID = note.id
    } label: {
      ListNoteCardView(
        note: note,
        appearanceSettings: store.appearanceSettings,
        isSelected: store.selectedListNoteID == note.id,
        accentColor: sidebarAccentColor,
        selectedCardColor: themeColors.selectedCard.color,
        unselectedCardColor: themeColors.unselectedCard.color,
        searchText: store.listSearchText
      )
    }
    .buttonStyle(.plain)
    .contextMenu {
      Menu("Move to group…") {
        Button("Ungrouped") {
          store.moveNoteToUngrouped(noteID: note.id)
        }

        if !store.listNoteManifest.groups.isEmpty {
          Divider()

          ForEach(store.listNoteManifest.groups) { group in
            Button(group.name) {
              store.moveNoteToGroup(noteID: note.id, groupID: group.id)
            }
          }
        }
      }

      Divider()

      Button(role: .destructive) {
        requestDelete(note.id)
      } label: {
        Label("Delete note…", systemImage: "trash")
      }
    }
  }

  private var themeColors: ThemeColorSet {
    store.appearanceSettings.resolvedColors
  }

  private var sidebarAccentColor: Color {
    Color(nsColor: store.appearanceSettings.accentColor)
  }
}

// MARK: - Drop Delegates

// Handles dropping a note onto another note card or a drop zone within a section.
// Inserts the dragged note at `targetIndex` in the target location (ungrouped or a group).
// Ignores group drags (prefixed payloads).
private struct NoteDropDelegate: DropDelegate {
  let store: NotesStore
  let targetGroupID: String?
  let targetIndex: Int

  func validateDrop(info: DropInfo) -> Bool {
    info.hasItemsConforming(to: [.plainText])
  }

  func performDrop(info: DropInfo) -> Bool {
    guard let item = info.itemProviders(for: [.plainText]).first else { return false }

    item.loadObject(ofClass: NSString.self) { reading, _ in
      guard let payload = reading as? String else { return }
      // Ignore group drags — they're handled by GroupHeaderDropDelegate.
      guard !payload.hasPrefix(ListNotesSidebarContent.groupDragPrefix) else { return }
      DispatchQueue.main.async {
        if let groupID = targetGroupID {
          store.moveNoteToGroup(noteID: payload, groupID: groupID, atIndex: targetIndex)
        } else {
          store.moveNoteToUngrouped(noteID: payload, atIndex: targetIndex)
        }
      }
    }
    return true
  }
}

// Handles drops on a group header — accepts notes (moves into the group)
// and other groups (reorders groups). Both use plain-text payloads;
// group drags are distinguished by a "group:" prefix.
private struct GroupHeaderDropDelegate: DropDelegate {
  let store: NotesStore
  let targetGroupID: String
  let groupIndex: Int

  func validateDrop(info: DropInfo) -> Bool {
    info.hasItemsConforming(to: [.plainText])
  }

  func performDrop(info: DropInfo) -> Bool {
    guard let item = info.itemProviders(for: [.plainText]).first else { return false }

    item.loadObject(ofClass: NSString.self) { reading, _ in
      guard let payload = reading as? String else { return }
      DispatchQueue.main.async {
        let prefix = ListNotesSidebarContent.groupDragPrefix
        if payload.hasPrefix(prefix) {
          let draggedGroupID = String(payload.dropFirst(prefix.count))
          guard draggedGroupID != targetGroupID else { return }
          store.reorderGroup(groupID: draggedGroupID, toIndex: groupIndex)
        } else {
          store.moveNoteToGroup(noteID: payload, groupID: targetGroupID)
        }
      }
    }
    return true
  }
}

// MARK: - Subviews

// Thin drop target at the top of the ungrouped section.
private struct UngroupedDropZone: View {
  var body: some View {
    Color.clear
      .frame(height: 2)
  }
}

private struct ListSidebarEmptyStateView: View {
  let addNote: () -> Void

  var body: some View {
    VStack(spacing: 10) {
      Image(systemName: "list.bullet.rectangle")
        .font(.system(size: 32, weight: .light))
        .foregroundStyle(.tertiary)

      Text("No list notes yet")
        .font(.headline)
        .foregroundStyle(.secondary)

      Button(action: addNote) {
        Label("Add note", systemImage: "plus")
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private struct AddListNoteButton: View {
  let accentColor: Color
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Image(systemName: "plus")
          .font(.system(size: 12, weight: .semibold))

        Text("Add note")
          .font(.system(size: 13, weight: .medium))
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 8)
      .background(
        accentColor.opacity(0.1),
        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
      )
    }
    .buttonStyle(.plain)
    .foregroundStyle(accentColor)
  }
}

private struct NewGroupButton: View {
  let accentColor: Color
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Image(systemName: "folder.badge.plus")
          .font(.system(size: 12, weight: .semibold))

        Text("Group")
          .font(.system(size: 13, weight: .medium))
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(
        accentColor.opacity(0.1),
        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
      )
    }
    .buttonStyle(.plain)
    .foregroundStyle(accentColor)
  }
}

private struct GroupHeaderView: View {
  let group: NoteGroup
  let noteCount: Int
  let accentColor: Color
  let dividerColor: Color
  let toggleCollapse: () -> Void

  var body: some View {
    Button(action: toggleCollapse) {
      HStack(spacing: 8) {
        Image(systemName: group.isCollapsed ? "chevron.right" : "chevron.down")
          .font(.system(size: 10, weight: .bold))
          .foregroundStyle(accentColor)
          .frame(width: 12)

        Text(group.name.uppercased())
          .font(.caption.weight(.bold))
          .foregroundStyle(accentColor)
          .fixedSize()

        Rectangle()
          .fill(dividerColor)
          .frame(height: 1)

        Text("\(noteCount)")
          .font(.caption2.weight(.medium))
          .foregroundStyle(.secondary)
      }
    }
    .buttonStyle(.plain)
    .padding(.top, 4)
    .contentShape(Rectangle())
  }
}
