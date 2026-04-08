//
//  ListNotesSidebarContent.swift
//

// Sidebar content for list mode — shows ungrouped notes and collapsible groups.

import SwiftUI

struct ListNotesSidebarContent: View {
  @ObservedObject var store: NotesStore
  let requestDelete: (DayNote.ID) -> Void

  @State private var isShowingNewGroupAlert = false
  @State private var newGroupName = ""

  var body: some View {
    let manifest = store.listNoteManifest
    let isSearching = store.isListSearchActive
    let filteredIDs = Set(store.filteredListNotes.map(\.id))

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
              newGroupName = ""
              isShowingNewGroupAlert = true
            }
          }

          // Ungrouped notes
          let ungroupedNotes = isSearching
            ? manifest.ungroupedNoteIDs.filter { filteredIDs.contains($0) }
            : manifest.ungroupedNoteIDs

          ForEach(ungroupedNotes, id: \.self) { noteID in
            if let note = store.listNote(withID: noteID) {
              listNoteButton(note: note, filteredIDs: filteredIDs)
            }
          }

          // Groups
          ForEach(manifest.groups) { group in
            let groupNoteIDs = isSearching
              ? group.noteIDs.filter { filteredIDs.contains($0) }
              : group.noteIDs

            // Hide empty groups during search
            if !isSearching || !groupNoteIDs.isEmpty {
              GroupHeaderView(
                group: group,
                noteCount: groupNoteIDs.count,
                accentColor: sidebarAccentColor,
                dividerColor: themeColors.divider.color
              ) {
                store.toggleGroupCollapsed(groupID: group.id)
              }
              .contextMenu {
                Button {
                  newGroupName = group.name
                  // Use a small delay so the context menu dismisses first.
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
                ForEach(groupNoteIDs, id: \.self) { noteID in
                  if let note = store.listNote(withID: noteID) {
                    listNoteButton(note: note, filteredIDs: filteredIDs)
                  }
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

    // Invisible modifier to attach the alert — avoids nesting issues.
    Color.clear
      .frame(width: 0, height: 0)
      .alert("Group name", isPresented: $isShowingNewGroupAlert) {
        TextField("Name", text: $newGroupName)
        Button("Cancel", role: .cancel) {}
        Button("OK") {
          let trimmed = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
          guard !trimmed.isEmpty else { return }
          // Check if we're renaming an existing group.
          if let existing = store.listNoteManifest.groups.first(where: { $0.name == newGroupName && trimmed != newGroupName }) {
            store.renameGroup(groupID: existing.id, name: trimmed)
          } else if store.listNoteManifest.groups.contains(where: { $0.name == trimmed }) {
            // Already exists with that name, do nothing.
          } else {
            store.createGroup(name: trimmed)
          }
        }
      }
  }

  // Renders a single list note card with selection and context menu.
  @ViewBuilder
  private func listNoteButton(note: DayNote, filteredIDs: Set<String>) -> some View {
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

// MARK: - Subviews

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
  }
}
