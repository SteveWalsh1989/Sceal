//
//  ScealLibrarySnapshot.swift
//

// Complete in-memory source for versioned full-library export, safety backup, and migration checks.

import Foundation

nonisolated struct ScealLibrarySnapshot: Sendable {
  let legacyDailyNotes: [DayNote]
  let legacyListNotes: [DayNote]
  let legacyListManifest: ListNotesManifest
  let structuredDailyNotes: [StructuredNoteDocument]
  let structuredListNotes: [StructuredNoteDocument]
  let structuredListManifest: ListNotesManifest
  let templates: [NoteTemplate]
  let settings: ScealArchiveSettings
  let authority: ScealArchiveAuthority
  let legacySourceFiles: LegacyArchiveSourceFiles?
}
