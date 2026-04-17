//
//  AppRootView.swift
//
//

// Root NavigationSplitView combining the sidebar and note editor.

import SwiftUI

struct AppRootView: View {
  @ObservedObject var store: NotesStore
  @State private var notePendingDeletionID: DayNote.ID?
  @State private var notePendingDateChangeID: DayNote.ID?
  @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

  // Prevents app-hosted unit tests from loading real user data into the test runner.
  private let isRunningUnitTests =
    ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

  var body: some View {
    NavigationSplitView(columnVisibility: $columnVisibility) {
      NotesSidebarView(store: store) { noteID in
        notePendingDeletionID = noteID
      } requestChangeDate: { noteID in
        notePendingDateChangeID = noteID
      }
      .navigationSplitViewColumnWidth(min: 240, ideal: 290, max: 360)
    } detail: {
      Group {
        if let activeNoteID = store.activeSelectedNoteID {
          NotesEditorView(
            store: store,
            noteID: activeNoteID,
            sidebarCollapsed: columnVisibility == .detailOnly
          ) { noteID in
            notePendingDeletionID = noteID
          }
        } else if store.isLoading {
          ProgressView("Loading notes…")
        } else {
          ContentUnavailableView(
            "No note selected",
            systemImage: store.sidebarMode.usesDailyNotes ? "calendar" : "list.bullet",
            description: Text(
              store.sidebarMode.usesDailyNotes
                ? "Choose a day from the sidebar to start writing."
                : "Select a note from the sidebar or add a new one."
            )
          )
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(editorBackgroundColor)
      .ignoresSafeArea(.container, edges: .top)
    }
    .navigationSplitViewStyle(.balanced)
    .task {
      guard !isRunningUnitTests else {
        return
      }
      store.loadIfNeeded()
    }
    .alert("Delete this note?", isPresented: isShowingDeleteConfirmation) {
      Button("Delete", role: .destructive) {
        guard let notePendingDeletionID else {
          return
        }

        switch store.sidebarMode {
        case .calendar, .daily:
          store.delete(noteID: notePendingDeletionID)
        case .list:
          store.deleteListNote(noteID: notePendingDeletionID)
        }
        self.notePendingDeletionID = nil
      }

      Button("Cancel", role: .cancel) {
        notePendingDeletionID = nil
      }
    } message: {
      Text("This cannot be undone.")
    }
    .sheet(item: notePendingDateChangeBinding) { wrapper in
      ChangeDateSheet(
        currentDate: wrapper.date,
        onConfirm: { newDate in
          store.changeDate(noteID: wrapper.id, to: newDate)
          notePendingDateChangeID = nil
        },
        onCancel: {
          notePendingDateChangeID = nil
        }
      )
    }
    .overlay(alignment: .top) {
      if let message = store.userMessage {
        ErrorBanner(message: message.text, kind: message.kind) {
          store.dismissMessage()
        }
        .padding(.top, 12)
      }
    }
    .overlay(alignment: .center) {
      if store.isPerformingFileOperation {
        ZStack {
          Color.black.opacity(0.25)
            .ignoresSafeArea()
          VStack(spacing: 12) {
            ProgressView(store.progressMessage ?? "Working…")
              .progressViewStyle(.circular)
              .controlSize(.large)
            if let msg = store.progressMessage {
              Text(msg)
                .font(.callout)
                .foregroundStyle(.secondary)
            }
          }
          .padding(20)
          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
          .shadow(radius: 16)
        }
      }
    }
  }

  // Keeps delete confirmation shared between header settings and sidebar actions.
  private var isShowingDeleteConfirmation: Binding<Bool> {
    Binding(
      get: { notePendingDeletionID != nil },
      set: { isPresented in
        if !isPresented {
          notePendingDeletionID = nil
        }
      }
    )
  }

  private var notePendingDateChangeBinding: Binding<DateChangeContext?> {
    Binding(
      get: {
        guard let noteID = notePendingDateChangeID,
          let note = store.note(withID: noteID)
        else { return nil }
        return DateChangeContext(id: noteID, date: note.date)
      },
      set: { value in
        if value == nil {
          notePendingDateChangeID = nil
        }
      }
    )
  }

  // Resolves the editor background from the active theme.
  private var editorBackgroundColor: Color {
    store.appearanceSettings.resolvedColors.editorBackground.color
  }
}

private struct DateChangeContext: Identifiable {
  let id: DayNote.ID
  let date: Date
}

private struct ChangeDateSheet: View {
  let currentDate: Date
  let onConfirm: (Date) -> Void
  let onCancel: () -> Void

  @State private var selectedDate: Date

  init(currentDate: Date, onConfirm: @escaping (Date) -> Void, onCancel: @escaping () -> Void) {
    self.currentDate = currentDate
    self.onConfirm = onConfirm
    self.onCancel = onCancel
    self._selectedDate = State(initialValue: currentDate)
  }

  var body: some View {
    VStack(spacing: 20) {
      Text("Change date")
        .font(.headline)

      DatePicker(
        "New date",
        selection: $selectedDate,
        displayedComponents: .date
      )
      .datePickerStyle(.graphical)
      .labelsHidden()

      HStack(spacing: 12) {
        Button("Cancel", role: .cancel, action: onCancel)
          .keyboardShortcut(.cancelAction)

        Button("Confirm") {
          onConfirm(selectedDate)
        }
        .keyboardShortcut(.defaultAction)
        .disabled(Calendar.current.isDate(selectedDate, inSameDayAs: currentDate))
      }
    }
    .padding(20)
    .frame(width: 300)
  }
}

private struct ErrorBanner: View {
  let message: String
  let kind: UserMessageKind
  let dismiss: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: kind == .error ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
        .foregroundStyle(kind == .error ? .orange : .green)

      Text(message)
        .font(.callout)
        .lineLimit(2)

      Button("Dismiss", action: dismiss)
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(.regularMaterial, in: Capsule())
    .shadow(color: Color.black.opacity(0.12), radius: 18, y: 8)
  }
}
