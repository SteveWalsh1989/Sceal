//
//  DailyNoteStorageMode.swift
//

// Selects the isolated persistence and editor path used for daily notes.

import Foundation

nonisolated enum DailyNoteStorageMode: String, CaseIterable, Identifiable, Sendable {
  case legacyMarkdown
  case structuredExperimental

  var id: String { rawValue }

}
