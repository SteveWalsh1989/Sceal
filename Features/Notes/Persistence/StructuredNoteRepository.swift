//
//  StructuredNoteRepository.swift
//

// Isolated file-backed persistence and explicit legacy-copy import for structured daily notes.

import Foundation

nonisolated struct StructuredNoteImportResult: Equatable, Sendable {
  let imported: Int
  let skipped: Int
}

nonisolated struct StructuredNoteRepository {
  static let fileExtension = "scealnote"

  let storageDirectoryURL: URL
  let legacyNotesDirectoryURL: URL
  let fileManager: FileManager

  init(
    libraryLocation: ScealLibraryLocation,
    fileManager: FileManager = .default
  ) {
    self.init(
      storageDirectoryURL: libraryLocation.structuredNotesDirectoryURL,
      legacyNotesDirectoryURL: libraryLocation.legacyNotesDirectoryURL,
      fileManager: fileManager
    )
  }

  init(
    storageDirectoryURL: URL,
    legacyNotesDirectoryURL: URL,
    fileManager: FileManager = .default
  ) {
    self.storageDirectoryURL = storageDirectoryURL
    self.legacyNotesDirectoryURL = legacyNotesDirectoryURL
    self.fileManager = fileManager
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
    try validateDailyDocument(document)
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
    try validateStorageTarget()

    guard fileManager.fileExists(atPath: legacyNotesDirectoryURL.path) else {
      return StructuredNoteImportResult(imported: 0, skipped: 0)
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
        sourceURL: sourceURL
      )
    }
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

  // Resolves a canonical file URL only after validating the daily-note storage ID.
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

  // Keeps daily structured filenames date-based and unable to escape their storage directory.
  private func validateDailyDocument(_ document: StructuredNoteDocument) throws {
    try document.validate()
    let expectedID = NoteDateFormatters.storageDate.string(from: document.date)
    guard document.id == expectedID,
      !document.id.contains("/"),
      !document.id.contains(":")
    else {
      throw StructuredNoteRepositoryError.invalidDailyDocumentID(
        document.id,
        expected: expectedID
      )
    }
  }

  // Creates only the dedicated StructuredNotes directory after the safety check passes.
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
      try validateDailyDocument(document)
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
      try validateDailyDocument(document)
    }
  }
}

nonisolated enum StructuredNoteRepositoryError: LocalizedError, Equatable, Sendable {
  case refusingLegacyNotesDirectory(URL)
  case invalidDailyDocumentID(String, expected: String)
  case invalidDocument(URL, reason: String)
  case fileNameDoesNotMatchDocumentID(URL, documentID: String)
  case duplicateLegacyDocumentID(String)

  var errorDescription: String? {
    switch self {
    case .refusingLegacyNotesDirectory(let directoryURL):
      return "Refusing to store structured notes in the legacy folder at \(directoryURL.path)."
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
