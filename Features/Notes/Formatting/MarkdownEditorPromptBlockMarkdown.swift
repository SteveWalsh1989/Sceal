//
//  MarkdownEditorPromptBlockMarkdown.swift
//

// Markdown and layout helpers for Sceal prompt block directives.

import AppKit

nonisolated enum MarkdownEditorPromptBlockMarkdown {
  static let startMarker = "<!-- prompt -->"
  static let endMarker = "<!-- /prompt -->"
  static let startBoundaryKind = "start"
  static let endBoundaryKind = "end"

  static var emptyBlock: String {
    "\(startMarker)\n\n\(endMarker)"
  }

  // Parses a persisted prompt boundary marker into the editor boundary kind.
  static func boundaryKind(for line: String) -> String? {
    if line == startMarker {
      return startBoundaryKind
    }
    if line == endMarker {
      return endBoundaryKind
    }
    return nil
  }

  // Builds the persisted prompt boundary marker for an editor boundary kind.
  static func marker(forBoundaryKind kind: String) -> String {
    kind == startBoundaryKind ? startMarker : endMarker
  }

  static func isStartBoundaryKind(_ kind: String) -> Bool {
    kind == startBoundaryKind
  }

  static func isEndBoundaryKind(_ kind: String) -> Bool {
    kind == endBoundaryKind
  }
}

enum MarkdownEditorPromptBlockLayout {
  static let blockHorizontalInset: CGFloat = 18
  static let cornerRadius: CGFloat = 8
  static let textHorizontalInset: CGFloat = 18
  static let editorTextContainerHorizontalInset: CGFloat = 22
  static let copyButtonWidth: CGFloat = 58
  static let clearButtonWidth: CGFloat = 58
  static let copyButtonHeight: CGFloat = 22
  static let actionButtonSpacing: CGFloat = 6
  static let closeButtonSize: CGFloat = 22
  static let closeButtonGap: CGFloat = 8
  static let actionPadding: CGFloat = 10
  static let bottomPaddingLineHeight: CGFloat = 12

  static var closeButtonLaneWidth: CGFloat {
    closeButtonGap + closeButtonSize
  }

  static var actionRowHeight: CGFloat {
    copyButtonHeight + actionPadding * 2
  }

  static var copyButtonTopOffset: CGFloat {
    (actionRowHeight - copyButtonHeight) / 2
  }

  // Keeps prompt text aligned with the drawn box while leaving the close-button lane clear.
  static var paragraphTailIndent: CGFloat {
    let insetFromTextContainerRight =
      blockHorizontalInset + closeButtonLaneWidth + textHorizontalInset
      - editorTextContainerHorizontalInset
    return -max(insetFromTextContainerRight, textHorizontalInset)
  }

  // Reserves the start marker row for prompt actions so content never sits beneath Copy.
  static func boundaryLineHeight(for kind: String) -> CGFloat {
    MarkdownEditorPromptBlockMarkdown.isStartBoundaryKind(kind)
      ? actionRowHeight
      : bottomPaddingLineHeight
  }
}
