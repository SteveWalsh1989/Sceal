import Foundation
import OSLog

// Shared zip-archive utilities for export and backup flows.
enum ZipArchiveWriter {
  private static let logger = Logger(subsystem: "com.sceal.app", category: "archive")

  // Creates a temporary staging root that can later be zipped and cleaned up.
  nonisolated static func makeTemporaryStagingDirectory(prefix: String, rootFolderName: String)
    throws
    -> (temporaryBaseURL: URL, stagingDirectoryURL: URL)
  {
    let temporaryBaseURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    let stagingDirectoryURL = temporaryBaseURL.appendingPathComponent(
      rootFolderName, isDirectory: true)

    try FileManager.default.createDirectory(
      at: stagingDirectoryURL,
      withIntermediateDirectories: true
    )

    return (temporaryBaseURL, stagingDirectoryURL)
  }

  // Removes the temporary directory that contains an archive after the caller has moved it.
  nonisolated static func cleanUp(zipURL: URL) {
    let parentDirectoryURL = zipURL.deletingLastPathComponent()
    try? FileManager.default.removeItem(at: parentDirectoryURL)
  }

  // Uses the macOS ditto binary to zip a staging directory without external dependencies.
  nonisolated static func createZip(from sourceDirectoryURL: URL, to zipURL: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    process.arguments = ["-c", "-k", "--sequesterRsrc", sourceDirectoryURL.path, zipURL.path]

    let errorPipe = Pipe()
    process.standardError = errorPipe

    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
      let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
      let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown zip error"
      logger.error("ditto zip failed: \(errorMessage)")
      throw ZipArchiveWriterError.zipFailed(errorMessage)
    }
  }
}

enum ZipArchiveWriterError: LocalizedError {
  case zipFailed(String)

  var errorDescription: String? {
    switch self {
    case .zipFailed(let detail):
      return "Failed to create zip archive. \(detail)"
    }
  }
}
