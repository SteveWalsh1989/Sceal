//
//  AppRootView.swift
//
//

// Root NavigationSplitView combining the sidebar and note editor.

import AppKit
import SwiftUI

struct AppRootView: View {
  @ObservedObject var store: NotesStore
  let enablesDemoModeOnLaunch: Bool
  @State private var notePendingDeletionID: DayNote.ID?
  @State private var notePendingDateChangeID: DayNote.ID?
  @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
  @State private var transientToast: AppToastMessage?
  @State private var transientToastDismissTask: Task<Void, Never>?
  @State private var hasAppliedLaunchDemoMode = false

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
      .disabled(store.isLibraryRecoveryBlocked || store.isPerformingFileOperation)
    } detail: {
      Group {
        if store.isPerformingFileOperation {
          ProgressView(store.progressMessage ?? "Working...")
        } else if store.isLibraryRecoveryBlocked {
          ContentUnavailableView(
            "Library recovery required", systemImage: "externaldrive.badge.exclamationmark",
            description: Text(
              store.structuredNotesCutoverFailureDescription
                ?? "Retry opening the library before editing. Recovery copies have been retained."))
        } else if store.isStructuredEditorActive {
          StructuredNoteEditorView(
            store: store,
            sidebarCollapsed: columnVisibility == .detailOnly,
            requestDelete: { noteID in
              notePendingDeletionID = noteID
            }
          )
        } else if let activeNoteID = store.activeSelectedNoteID {
          NotesEditorView(
            store: store,
            noteID: activeNoteID,
            sidebarCollapsed: columnVisibility == .detailOnly,
            showToast: showToast
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
      if !isRunningUnitTests {
        #if DEBUG
          store.loadIfNeeded()
        #else
          store.prepareStructuredCutoverForProductionLaunch()
        #endif
      }

      #if DEBUG
        applyLaunchDemoModeIfNeeded()
      #endif
    }
    .alert(
      structuredCutoverAlertTitle,
      isPresented: structuredCutoverPromptBinding
    ) {
      Button(
        store.structuredNotesCutoverStatus == .recoveryRequired
          ? "Retry Opening Library" : "Back Up and Convert"
      ) {
        if store.structuredNotesCutoverStatus == .recoveryRequired {
          store.prepareStructuredCutoverForProductionLaunch()
        } else {
          store.backUpAndConvertLegacyLibrary()
        }
      }
      .keyboardShortcut(.defaultAction)

      if !store.isLibraryRecoveryBlocked {
        Button("Use Legacy for Now", role: .cancel) {
          store.continueUsingLegacyForNow()
        }
      }

      Button("Quit") {
        NSApplication.shared.terminate(nil)
      }
    } message: {
      Text(structuredCutoverAlertMessage)
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
      .keyboardShortcut(.defaultAction)

      Button("Cancel", role: .cancel) {
        notePendingDeletionID = nil
      }
      .keyboardShortcut(.cancelAction)
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
    .overlay(alignment: .bottomTrailing) {
      VStack(alignment: .trailing, spacing: 8) {
        if let message = store.userMessage {
          AppToastView(message: message.text, kind: message.kind) {
            store.dismissMessage()
          }
          .transition(.move(edge: .trailing).combined(with: .opacity))
        }

        if let transientToast {
          AppToastView(message: transientToast.text, kind: transientToast.kind)
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
      }
      .frame(maxWidth: 360, alignment: .trailing)
      .padding(.trailing, 18)
      .padding(.bottom, 18)
    }
    .animation(.spring(response: 0.28, dampingFraction: 0.9), value: store.userMessage?.text)
    .animation(.spring(response: 0.28, dampingFraction: 0.9), value: transientToast?.id)
    .onDisappear {
      transientToastDismissTask?.cancel()
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
          let note = store.activeDailyNoteSummary(withID: noteID)
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

  private var structuredCutoverPromptBinding: Binding<Bool> {
    Binding(
      get: { store.isStructuredCutoverPromptPresented },
      set: { _ in }
    )
  }

  private var structuredCutoverAlertTitle: String {
    switch store.structuredNotesCutoverStatus {
    case .recoveryRequired:
      return "Library needs recovery"
    case .failedValidation:
      return "Conversion needs attention"
    default:
      return "Upgrade notes for Structured Notes V2?"
    }
  }

  private var structuredCutoverAlertMessage: String {
    if let failure = store.structuredNotesCutoverFailureDescription {
      return
        "Scéal did not activate the structured library because validation failed: \(failure) Your notes have not been overwritten by this validation check. You can retry after addressing the problem or restore a known full-library backup."
    }
    return
      "Scéal will first create a complete restorable backup, convert every daily and list note in staging, and validate the result before activating it. Your existing Markdown files will remain unchanged. Existing structured notes will not be overwritten by conversion."
  }

  // Resolves the editor background from the active theme.
  private var editorBackgroundColor: Color {
    store.appearanceSettings.resolvedColors.editorBackground.color
  }

  #if DEBUG
    // Applies the DEBUG launch default once, after real notes have been loaded.
    private func applyLaunchDemoModeIfNeeded() {
      guard !store.isLibraryRecoveryBlocked else { return }
      guard enablesDemoModeOnLaunch,
        !hasAppliedLaunchDemoMode,
        store.dailyNoteStorageMode != .structuredExperimental
      else { return }
      hasAppliedLaunchDemoMode = true
      store.setDemoModeEnabled(true)
    }
  #endif

  // Shows short-lived local feedback for AppKit-hosted controls inside the editor.
  private func showToast(_ message: String, kind: UserMessageKind) {
    transientToastDismissTask?.cancel()

    let toast = AppToastMessage(text: message, kind: kind)
    transientToast = toast

    transientToastDismissTask = Task { @MainActor in
      try? await Task.sleep(nanoseconds: 1_800_000_000)
      guard !Task.isCancelled, transientToast?.id == toast.id else { return }

      withAnimation(.easeOut(duration: 0.18)) {
        transientToast = nil
      }
    }
  }
}

private struct DateChangeContext: Identifiable {
  let id: DayNote.ID
  let date: Date
}

private struct AppToastMessage: Identifiable, Equatable {
  let id = UUID()
  let text: String
  let kind: UserMessageKind
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

private struct AppToastView: View {
  let message: String
  let kind: UserMessageKind
  var dismiss: (() -> Void)?

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: iconName)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(iconColor)

      Text(message)
        .font(.callout)
        .lineLimit(3)
        .fixedSize(horizontal: false, vertical: true)

      if let dismiss {
        Button(action: dismiss) {
          Image(systemName: "xmark")
            .font(.system(size: 11, weight: .semibold))
            .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel("Dismiss")
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
    }
    .shadow(color: Color.black.opacity(0.12), radius: 18, y: 8)
  }

  private var iconName: String {
    kind == .error ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
  }

  private var iconColor: Color {
    kind == .error ? .orange : .green
  }
}
