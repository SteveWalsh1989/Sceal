import Foundation

// Library-scoped authority survives lost preferences, including deliberately empty libraries.
nonisolated struct StructuredLibraryState: Codable {
  let version: Int
  let storageFormat: String

  // Only a missing record means unknown authority; unreadable or invalid records are errors.
  static func isCompleted(at location: ScealLibraryLocation) throws -> Bool {
    let data: Data
    do {
      data = try Data(contentsOf: location.structuredLibraryStateURL)
    } catch CocoaError.fileReadNoSuchFile {
      return false
    }
    let state = try JSONDecoder().decode(Self.self, from: data)
    guard state.version == 1, state.storageFormat == "structured" else {
      throw StructuredLibraryStateError.unsupportedState
    }
    return true
  }

  // Write only after both structured folders have been installed and validated.
  static func markCompleted(at location: ScealLibraryLocation) throws {
    let state = Self(version: 1, storageFormat: "structured")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(state).write(to: location.structuredLibraryStateURL, options: .atomic)
  }

  // Loading must not recreate a missing authoritative folder as an apparently empty library.
  static func requireStorageDirectories(at location: ScealLibraryLocation) throws {
    for directoryURL in [
      location.structuredNotesDirectoryURL, location.structuredListNotesDirectoryURL,
    ] {
      guard try directoryURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
        throw StructuredLibraryStateError.invalidStorageDirectory(directoryURL)
      }
    }
  }
}

nonisolated enum StructuredLibraryStateError: LocalizedError {
  case unsupportedState
  case invalidStorageDirectory(URL)
  case ambiguousLibraries
  case alreadyCompleted

  var errorDescription: String? {
    switch self {
    case .unsupportedState:
      return "The structured library completion record is not supported by this version of Scéal."
    case .invalidStorageDirectory(let url):
      return
        "The structured storage folder is unavailable: \(url.path). Restore or recover the library before editing."
    case .ambiguousLibraries:
      return
        "Both Markdown and structured notes exist without a verified conversion record. Scéal will not overwrite either library. Restore a known full-library backup to establish which library to use."
    case .alreadyCompleted:
      return
        "This library is already converted. Scéal will not replace structured notes with older Markdown copies."
    }
  }
}
