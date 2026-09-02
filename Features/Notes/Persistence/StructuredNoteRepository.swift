//
//  StructuredNoteRepository.swift
//

// Isolated file-backed persistence and explicit legacy-copy import for structured notes.

import Foundation

nonisolated struct StructuredNoteImportResult: Equatable, Sendable {
  let imported: Int
  let skipped: Int
}

nonisolated enum StructuredNoteRepositoryKind: Hashable, Sendable {
  case daily
  case list
}

nonisolated struct StructuredNoteRepository {
  static let fileExtension = "scealnote"

  let storageDirectoryURL: URL
  let legacyNotesDirectoryURL: URL
  let fileManager: FileManager
  let kind: StructuredNoteRepositoryKind

  init(
    libraryLocation: ScealLibraryLocation,
    fileManager: FileManager = .default
  ) {
    self.init(
      storageDirectoryURL: libraryLocation.structuredNotesDirectoryURL,
      legacyNotesDirectoryURL: libraryLocation.legacyNotesDirectoryURL,
      fileManager: fileManager,
      kind: .daily
    )
  }

  // Builds the isolated structured list-note repository beside the legacy ListNotes folder.
  static func listNotes(
    libraryLocation: ScealLibraryLocation,
    fileManager: FileManager = .default
  ) -> StructuredNoteRepository {
    StructuredNoteRepository(
      storageDirectoryURL: libraryLocation.structuredListNotesDirectoryURL,
      legacyNotesDirectoryURL: libraryLocation.rootURL.appendingPathComponent(
        ScealLibraryLocation.listNotesFolderName,
        isDirectory: true
      ),
      fileManager: fileManager,
      kind: .list
    )
  }

  init(
    storageDirectoryURL: URL,
    legacyNotesDirectoryURL: URL,
    fileManager: FileManager = .default,
    kind: StructuredNoteRepositoryKind = .daily
  ) {
    self.storageDirectoryURL = storageDirectoryURL
    self.legacyNotesDirectoryURL = legacyNotesDirectoryURL
    self.fileManager = fileManager
    self.kind = kind
  }

  // Loads and validates every structured daily note rather than silently dropping corruption.
  func loadDocuments() throws -> [StructuredNoteDocument] {
    try validateStorageTarget()
    try createStorageDirectoryIfNeeded()

    return try structuredFileURLs()
      .map(loadDocument(from:))
      .sorted(by: { $0.date > $1.date })
  }

  // Atomically writes one validated daily document to its canonical structured filename.
  func save(_ document: StructuredNoteDocument) throws {
    try validateStorageTarget()
    try validateDocument(document)
    try createStorageDirectoryIfNeeded()
    try StructuredNoteDocumentCodec.write(document, to: fileURL(for: document.id))
  }

  // Removes one canonical structured document without touching the legacy Markdown library.
  func delete(documentID: String) throws {
    try validateStorageTarget()
    let documentURL = fileURL(for: documentID)
    guard fileManager.fileExists(atPath: documentURL.path) else { return }
    try fileManager.removeItem(at: documentURL)
  }

  // Copies all legacy Markdown daily notes after validating the complete source set first.
  func copyLegacyDailyNotes() throws -> StructuredNoteImportResult {
    try importPreparedDocuments(prepareLegacyDocuments())
  }

  // Decodes and validates the complete legacy source set without creating structured files.
  func prepareLegacyDocuments() throws -> [StructuredNoteDocument] {
    try validateStorageTarget()

    guard fileManager.fileExists(atPath: legacyNotesDirectoryURL.path) else {
      return []
    }

    let sourceURLs = try fileManager.contentsOfDirectory(
      at: legacyNotesDirectoryURL,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )
    .filter { $0.pathExtension == "md" }
    .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })

    let documents = try sourceURLs.map { sourceURL in
      try LegacyMarkdownStructuredNoteAdapter.importDocument(
        contents: String(contentsOf: sourceURL, encoding: .utf8),
        sourceURL: sourceURL,
        idOverride: kind == .list ? sourceURL.deletingPathExtension().lastPathComponent : nil
      )
    }
    try validateUniqueDocumentIDs(documents)
    return documents
  }

  // Writes a prevalidated source set while preserving any existing same-ID structured document.
  func importPreparedDocuments(
    _ documents: [StructuredNoteDocument]
  ) throws -> StructuredNoteImportResult {
    try validateUniqueDocumentIDs(documents)
    let existingDocumentIDs = Set(try loadDocuments().map(\.id))
    let documentsToImport = documents.filter { !existingDocumentIDs.contains($0.id) }
    for document in documentsToImport {
      try save(document)
    }

    return StructuredNoteImportResult(
      imported: documentsToImport.count,
      skipped: documents.count - documentsToImport.count
    )
  }

  // Resolves the canonical structured document URL for a stable storage ID.
  func fileURL(for documentID: String) -> URL {
    storageDirectoryURL
      .appendingPathComponent(documentID)
      .appendingPathExtension(Self.fileExtension)
  }

  // Prevents any structured operation from targeting the legacy Markdown directory.
  private func validateStorageTarget() throws {
    let storageURL = storageDirectoryURL.standardizedFileURL.resolvingSymlinksInPath()
    let legacyURL = legacyNotesDirectoryURL.standardizedFileURL.resolvingSymlinksInPath()
    guard storageURL != legacyURL else {
      throw StructuredNoteRepositoryError.refusingLegacyNotesDirectory(storageDirectoryURL)
    }
  }

  // Keeps structured filenames safe and daily documents date-keyed.
  private func validateDocument(_ document: StructuredNoteDocument) throws {
    try document.validate()
    if kind == .daily {
      let expectedID = NoteDateFormatters.storageDate.string(from: document.date)
      guard document.id == expectedID else {
        throw StructuredNoteRepositoryError.invalidDailyDocumentID(
          document.id,
          expected: expectedID
        )
      }
    }
    guard !document.id.isEmpty,
      !document.id.contains("/"),
      !document.id.contains(":"),
      document.id != ".",
      document.id != ".."
    else {
      throw StructuredNoteRepositoryError.invalidDocumentID(document.id)
    }

  }

  // Creates only the dedicated structured directory after the safety check passes.
  private func createStorageDirectoryIfNeeded() throws {
    try fileManager.createDirectory(
      at: storageDirectoryURL,
      withIntermediateDirectories: true
    )
  }

  // Returns only canonical structured-note files in the isolated directory.
  private func structuredFileURLs() throws -> [URL] {
    try fileManager.contentsOfDirectory(
      at: storageDirectoryURL,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )
    .filter { $0.pathExtension == Self.fileExtension }
  }

  // Adds source-file context to decode and validation failures.
  private func loadDocument(from fileURL: URL) throws -> StructuredNoteDocument {
    do {
      let document = try StructuredNoteDocumentCodec.read(from: fileURL)
      try validateDocument(document)
      guard fileURL.deletingPathExtension().lastPathComponent == document.id else {
        throw StructuredNoteRepositoryError.fileNameDoesNotMatchDocumentID(
          fileURL,
          documentID: document.id
        )
      }
      return document
    } catch let error as StructuredNoteRepositoryError {
      throw error
    } catch {
      throw StructuredNoteRepositoryError.invalidDocument(
        fileURL,
        reason: error.localizedDescription
      )
    }
  }

  // Rejects conflicting legacy sources before any structured copy is written.
  private func validateUniqueDocumentIDs(_ documents: [StructuredNoteDocument]) throws {
    var documentIDs = Set<String>()
    for document in documents {
      guard documentIDs.insert(document.id).inserted else {
        throw StructuredNoteRepositoryError.duplicateLegacyDocumentID(document.id)
      }
      try validateDocument(document)
    }
  }
}

nonisolated enum StructuredNoteRepositoryError: LocalizedError, Equatable, Sendable {
  case refusingLegacyNotesDirectory(URL)
  case invalidDocumentID(String)
  case invalidDailyDocumentID(String, expected: String)
  case invalidDocument(URL, reason: String)
  case fileNameDoesNotMatchDocumentID(URL, documentID: String)
  case duplicateLegacyDocumentID(String)

  var errorDescription: String? {
    switch self {
    case .refusingLegacyNotesDirectory(let directoryURL):
      return "Refusing to store structured notes in the legacy folder at \(directoryURL.path)."
    case .invalidDocumentID(let documentID):
      return "Structured note ID \(documentID) is not safe for file storage."
    case .invalidDailyDocumentID(let documentID, let expectedID):
      return "Structured daily note \(documentID) must use date-based ID \(expectedID)."
    case .invalidDocument(let fileURL, let reason):
      return "Scéal could not load \(fileURL.lastPathComponent). \(reason)"
    case .fileNameDoesNotMatchDocumentID(let fileURL, let documentID):
      return "Structured note \(fileURL.lastPathComponent) contains mismatched ID \(documentID)."
    case .duplicateLegacyDocumentID(let documentID):
      return "More than one legacy note resolves to daily note ID \(documentID)."
    }
  }
}
