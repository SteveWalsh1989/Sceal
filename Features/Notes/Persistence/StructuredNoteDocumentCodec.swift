//
//  StructuredNoteDocumentCodec.swift
//

// Encodes and decodes versioned structured-note JSON with atomic file writes.

import Foundation

nonisolated enum StructuredNoteDocumentCodec {
  private struct SchemaHeader: Decodable {
    let schemaVersion: Int
  }

  // Encodes a validated document into deterministic, readable JSON data.
  static func encode(_ document: StructuredNoteDocument) throws -> Data {
    try document.validate()
    return try makeEncoder().encode(document)
  }

  // Decodes supported JSON only after checking its schema version explicitly.
  static func decode(_ data: Data) throws -> StructuredNoteDocument {
    let decoder = makeDecoder()
    let header = try decoder.decode(SchemaHeader.self, from: data)
    guard header.schemaVersion == StructuredNoteDocument.currentSchemaVersion else {
      throw StructuredNoteDocumentError.unsupportedSchemaVersion(
        found: header.schemaVersion,
        supported: StructuredNoteDocument.currentSchemaVersion
      )
    }

    let document = try decoder.decode(StructuredNoteDocument.self, from: data)
    try document.validate()
    return document
  }

  // Writes a validated structured note atomically to a caller-provided file URL.
  static func write(_ document: StructuredNoteDocument, to fileURL: URL) throws {
    try encode(document).write(to: fileURL, options: .atomic)
  }

  // Reads and validates a structured note from a caller-provided file URL.
  static func read(from fileURL: URL) throws -> StructuredNoteDocument {
    try decode(Data(contentsOf: fileURL))
  }

  // Creates the canonical encoder used for files and archive payloads.
  private static func makeEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return encoder
  }

  // Creates a decoder that mirrors the canonical date representation.
  private static func makeDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}
