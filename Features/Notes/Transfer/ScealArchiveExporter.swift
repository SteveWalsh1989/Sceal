//
//  ScealArchiveExporter.swift
//

// Exports notes to a year-organized folder structure and zips the result.

import Foundation

// Exports notes to a year-organized zip archive using the native markdown format.
enum ScealArchiveExporter {
  // Writes the given notes into a temp directory and zips it, returning the zip URL.
  nonisolated static func exportNotes(_ notes: [DayNote]) throws -> URL {
    guard !notes.isEmpty else {
      throw ScealArchiveExporterError.noNotesToExport
    }

    let temporaryDirectories = try ZipArchiveWriter.makeTemporaryStagingDirectory(
      prefix: "sceal-export",
      rootFolderName: "sceal-export"
    )
    let stagingDir = temporaryDirectories.stagingDirectoryURL

    for note in notes {
      let year = Calendar.current.component(.year, from: note.date)
      let yearDir = stagingDir.appendingPathComponent(String(year), isDirectory: true)

      try FileManager.default.createDirectory(
        at: yearDir,
        withIntermediateDirectories: true
      )

      let fileURL = yearDir.appendingPathComponent(note.fileName)
      let contents = try MarkdownNoteCodec.encode(note)
      try contents.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    let zipURL = temporaryDirectories.temporaryBaseURL.appendingPathComponent("sceal-export.zip")
    try ZipArchiveWriter.createZip(from: stagingDir, to: zipURL)

    // Clean up the staging directory, keep the zip
    try? FileManager.default.removeItem(at: stagingDir)

    return zipURL
  }

  // Removes the temp directory that contains the zip after the caller has moved it.
  nonisolated static func cleanUp(zipURL: URL) {
    ZipArchiveWriter.cleanUp(zipURL: zipURL)
  }
}

enum ScealArchiveExporterError: LocalizedError {
  case noNotesToExport
  case zipFailed(String)

  var errorDescription: String? {
    switch self {
    case .noNotesToExport:
      return "There are no notes to export."
    case .zipFailed(let detail):
      return "Failed to create zip archive. \(detail)"
    }
  }
}
