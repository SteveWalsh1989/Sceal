import AppKit
import SwiftUI

// Expandable search bar — shows as a magnifying glass icon, expands into a native NSSearchField on tap.
// The icon always occupies its natural 28pt in the HStack so nothing around it ever shifts.
// When expanded, the native search field appears as a trailing-aligned overlay growing leftward.
struct EditorSearchBar: View {
  @Binding var searchText: String
  @Binding var isExpanded: Bool
  let controlColor: Color

  private let expandedWidth: CGFloat = 168

  var body: some View {
    // Icon button stays in the layout at 28pt at all times to prevent HStack reflow.
    Button {
      expand()
    } label: {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
        .frame(width: 28, height: 28)
        .background(controlColor, in: RoundedRectangle(cornerRadius: 8))
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Search notes")
    .opacity(isExpanded ? 0 : 1)
    .allowsHitTesting(!isExpanded)
    .overlay(alignment: .trailing) {
      if isExpanded {
        NativeSearchField(text: $searchText, onCollapse: collapse)
          .frame(width: expandedWidth)
          .transition(.opacity)
      }
    }
  }

  private func expand() {
    withAnimation(.easeInOut(duration: 0.2)) {
      isExpanded = true
    }
  }

  private func collapse() {
    withAnimation(.easeInOut(duration: 0.2)) {
      searchText = ""
      isExpanded = false
    }
  }
}

// NSSearchField wrapper — provides the native macOS search field with its built-in
// magnifying glass icon, × clear button, and Escape key handling.
private struct NativeSearchField: NSViewRepresentable {
  @Binding var text: String
  let onCollapse: () -> Void

  func makeNSView(context: Context) -> NSSearchField {
    let field = NSSearchField()
    field.placeholderString = "Search"
    field.delegate = context.coordinator
    field.focusRingType = .none
    // Auto-focus after the view is inserted into the window.
    DispatchQueue.main.async {
      field.window?.makeFirstResponder(field)
    }
    return field
  }

  func updateNSView(_ nsView: NSSearchField, context: Context) {
    context.coordinator.onCollapse = onCollapse
    // Sync external clears (e.g. Escape from SwiftUI) back into the field.
    if nsView.stringValue != text {
      nsView.stringValue = text
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(text: $text, onCollapse: onCollapse)
  }

  @MainActor
  final class Coordinator: NSObject, NSSearchFieldDelegate {
    @Binding var text: String
    var onCollapse: () -> Void

    init(text: Binding<String>, onCollapse: @escaping () -> Void) {
      _text = text
      self.onCollapse = onCollapse
    }

    // Fires on every keystroke.
    func controlTextDidChange(_ obj: Notification) {
      guard let field = obj.object as? NSSearchField else { return }
      text = field.stringValue
    }

    // Fires when the user clicks the built-in × button or presses Escape.
    func searchFieldDidEndSearching(_ sender: NSSearchField) {
      text = ""
      onCollapse()
    }
  }
}

// Keeps header note-jump actions compact and visually aligned with the date.
struct HeaderNavigationButton: View {
  let systemImage: String
  let accessibilityLabel: String
  let controlColor: Color
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
        .frame(width: 24, height: 24)
        .background(controlColor, in: RoundedRectangle(cornerRadius: 8))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(accessibilityLabel)
  }
}
