//
//  ScealArchiveExporter.swift
//

// Exports notes to a year-organized folder structure and zips the result.

import Foundation
import OSLog

// Exports notes to a year-organized zip archive using the native markdown format.
enum ScealArchiveExporter {
  private static let logger = Logger(subsystem: "com.sceal.app", category: "export")

  // Writes the given notes into a temp directory and zips it, returning the zip URL.
  static func exportNotes(_ notes: [DayNote]) throws -> URL {
    guard !notes.isEmpty else {
      throw ScealArchiveExporterError.noNotesToExport
    }

    let tempBase = FileManager.default.temporaryDirectory
      .appendingPathComponent("sceal-export-\(UUID().uuidString)", isDirectory: true)
    let stagingDir = tempBase.appendingPathComponent("sceal-export", isDirectory: true)

    try FileManager.default.createDirectory(
      at: stagingDir,
      withIntermediateDirectories: true
    )

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

    let zipURL = tempBase.appendingPathComponent("sceal-export.zip")
    try createZip(from: stagingDir, to: zipURL)

    // Clean up the staging directory, keep the zip
    try? FileManager.default.removeItem(at: stagingDir)

    return zipURL
  }

  // Removes the temp directory that contains the zip after the caller has moved it.
  static func cleanUp(zipURL: URL) {
    let parentDir = zipURL.deletingLastPathComponent()
    try? FileManager.default.removeItem(at: parentDir)
  }

  // Uses /usr/bin/ditto to create a zip — a macOS system binary, no external deps needed.
  private static func createZip(from sourceDir: URL, to zipURL: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    process.arguments = ["-c", "-k", "--sequesterRsrc", sourceDir.path, zipURL.path]

    let errorPipe = Pipe()
    process.standardError = errorPipe

    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
      let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
      let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown zip error"
      logger.error("ditto zip failed: \(errorMessage)")
      throw ScealArchiveExporterError.zipFailed(errorMessage)
    }
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
