import Foundation

// A byte snapshot preserves recovery sources without requiring them to parse as active notes.
nonisolated struct LibraryArchiveFiles: Equatable, Sendable {
  var files: [String: Data] = [:]

  var markdownFileCount: Int {
    files.keys.filter {
      !$0.hasPrefix(".") && !$0.contains("/") && ($0 as NSString).pathExtension == "md"
    }.count
  }

  // Reject links and special files rather than following them outside the selected library.
  static func read(from rootURL: URL, fileManager: FileManager = .default) throws -> Self {
    var result = Self()
    let values: URLResourceValues
    do {
      values = try rootURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    } catch CocoaError.fileReadNoSuchFile {
      return result
    }
    guard values.isDirectory == true, values.isSymbolicLink != true else {
      throw LibraryArchiveFilesError.unsupportedFile(rootURL)
    }
    try readDirectory(rootURL, prefix: "", into: &result.files, fileManager: fileManager)
    return result
  }

  // Only write into fresh staging storage; the original source folders remain read-only.
  func write(to rootURL: URL, fileManager: FileManager = .default) throws {
    try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    for (path, data) in files {
      let components = path.components(separatedBy: "/")
      guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
        throw LibraryArchiveFilesError.invalidPath(path)
      }
      let destinationURL = rootURL.appendingPathComponent(path)
      try fileManager.createDirectory(
        at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true
      )
      try data.write(to: destinationURL, options: .atomic)
    }
  }

  // Enumerating explicitly propagates unreadable-directory errors instead of skipping files.
  private static func readDirectory(
    _ directoryURL: URL, prefix: String, into files: inout [String: Data], fileManager: FileManager
  ) throws {
    for url in try fileManager.contentsOfDirectory(
      at: directoryURL,
      includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
    ) {
      let values = try url.resourceValues(forKeys: [
        .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
      ])
      guard values.isSymbolicLink != true else {
        throw LibraryArchiveFilesError.unsupportedFile(url)
      }
      let path = prefix + url.lastPathComponent
      if values.isDirectory == true {
        try readDirectory(url, prefix: path + "/", into: &files, fileManager: fileManager)
      } else if values.isRegularFile == true {
        files[path] = try Data(contentsOf: url)
      } else {
        throw LibraryArchiveFilesError.unsupportedFile(url)
      }
    }
  }
}

nonisolated struct LegacyArchiveSourceFiles: Equatable, Sendable {
  let daily: LibraryArchiveFiles
  let list: LibraryArchiveFiles

  // Capture both original note trees, including manifest bytes and non-note recovery files.
  static func read(dailyURL: URL, listURL: URL, fileManager: FileManager = .default) throws -> Self
  {
    try Self(
      daily: LibraryArchiveFiles.read(from: dailyURL, fileManager: fileManager),
      list: LibraryArchiveFiles.read(from: listURL, fileManager: fileManager)
    )
  }
}

nonisolated enum LibraryArchiveFilesError: LocalizedError {
  case unsupportedFile(URL)
  case invalidPath(String)
  case sourceChanged

  var errorDescription: String? {
    switch self {
    case .unsupportedFile(let url):
      return "Cannot archive a link or unsupported file: \(url.path)."
    case .invalidPath(let path):
      return "The archive contains an unsafe file path: \(path)."
    case .sourceChanged:
      return "The original recovery files changed during restore. The replacement was not accepted."
    }
  }
}

// Historical raw values remain readable without depending on the removable UI mode enum.
nonisolated enum ScealArchiveAuthority: String, Sendable {
  case legacy = "legacyMarkdown"
  case structured = "structuredExperimental"
}
