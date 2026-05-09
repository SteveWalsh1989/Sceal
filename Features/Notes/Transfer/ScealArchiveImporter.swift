//
//  ScealArchiveImporter.swift
//

// Imports notes from an unzipped Scéal export using the native markdown format.

import Foundation

// Imports notes from an unzipped Scéal export folder using the native markdown format.
enum ScealArchiveImporter {

  struct ImportResult: Sendable {
    let imported: [DayNote]
    let templates: [NoteTemplate]
    let skipped: Int
    let failed: Int
  }

  // Walks a Scéal export folder for .md files, decodes via front matter, and skips existing dates.
  nonisolated static func importNotes(
    from folderURL: URL,
    existingNoteIDs: Set<DayNote.ID>
  ) throws -> ImportResult {
    let fileManager = FileManager.default
    var imported: [DayNote] = []
    var skipped = 0
    var failed = 0
    let templates = try importTemplates(from: folderURL, fileManager: fileManager)

    let mdFiles = collectMarkdownFiles(in: folderURL, fileManager: fileManager)

    for fileURL in mdFiles {
      do {
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        let note = try MarkdownNoteCodec.decode(contents: contents, sourceURL: fileURL)

        if existingNoteIDs.contains(note.id) {
          skipped += 1
          continue
        }

        imported.append(note)
      } catch {
        failed += 1
      }
    }

    return ImportResult(
      imported: imported.sorted(by: { $0.date > $1.date }),
      templates: templates,
      skipped: skipped,
      failed: failed
    )
  }

  nonisolated private static func importTemplates(from folderURL: URL, fileManager: FileManager)
    throws
    -> [NoteTemplate]
  {
    guard
      let fileURL = NoteTemplateArchive.findTemplatesFile(
        in: folderURL,
        fileManager: fileManager
      )
    else {
      return []
    }

    return try JSONDecoder().decode([NoteTemplate].self, from: Data(contentsOf: fileURL))
  }

  // Recursively collects all .md files from a directory, supporting both flat and year-subfolder layouts.
  nonisolated private static func collectMarkdownFiles(
    in directoryURL: URL,
    fileManager: FileManager
  ) -> [URL] {
    guard
      let enumerator = fileManager.enumerator(
        at: directoryURL,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
      )
    else {
      return []
    }

    var results: [URL] = []

    for case let fileURL as URL in enumerator {
      if fileURL.pathExtension == "md" {
        results.append(fileURL)
      }
    }

    return results
  }
}
