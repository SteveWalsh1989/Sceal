//
//  NoteImageAttachmentStore.swift
//

// File-backed storage for images referenced by markdown notes.

import AppKit
import Foundation
import UniformTypeIdentifiers

struct StoredImageAttachment: Equatable, Sendable {
  let relativePath: String
  let title: String
}

enum NoteImageAttachmentStore {
  nonisolated static let attachmentsFolderName = "Attachments"
  nonisolated private static let scealFolderName = "Sceal"
  nonisolated private static let pastedImageBaseName = "pasted-image"

  nonisolated static func attachmentRootDirectoryURL(
    fileManager: FileManager = .default,
    rootURL: URL? = nil,
    createIfNeeded: Bool = true
  ) throws -> URL {
    if let rootURL {
      if createIfNeeded {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
      }
      return rootURL
    }

    let appSupportURL = try fileManager.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: createIfNeeded
    )
    let rootDirectoryURL =
      appSupportURL
      .appendingPathComponent(scealFolderName, isDirectory: true)
      .appendingPathComponent(attachmentsFolderName, isDirectory: true)

    if createIfNeeded {
      try fileManager.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)
    }

    return rootDirectoryURL
  }

  nonisolated static func noteAttachmentDirectoryURL(
    for noteID: DayNote.ID,
    fileManager: FileManager = .default,
    rootURL: URL? = nil,
    createIfNeeded: Bool = true
  ) throws -> URL {
    let rootDirectoryURL = try attachmentRootDirectoryURL(
      fileManager: fileManager,
      rootURL: rootURL,
      createIfNeeded: createIfNeeded
    )
    let directoryURL = rootDirectoryURL.appendingPathComponent(
      safePathComponent(noteID),
      isDirectory: true
    )

    if createIfNeeded {
      try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    return directoryURL
  }

  @MainActor
  static func storeImageFile(
    from sourceURL: URL,
    for noteID: DayNote.ID,
    fileManager: FileManager = .default,
    rootURL: URL? = nil
  ) throws -> StoredImageAttachment {
    guard isSupportedImageFile(sourceURL) else {
      throw NoteImageAttachmentStoreError.unsupportedImage(sourceURL)
    }

    let directoryURL = try noteAttachmentDirectoryURL(
      for: noteID,
      fileManager: fileManager,
      rootURL: rootURL
    )
    let destinationURL = uniqueDestinationURL(
      in: directoryURL,
      preferredFileName: sourceURL.lastPathComponent,
      fileManager: fileManager
    )

    try fileManager.copyItem(at: sourceURL, to: destinationURL)

    return StoredImageAttachment(
      relativePath: relativePath(for: noteID, fileName: destinationURL.lastPathComponent),
      title: title(from: sourceURL)
    )
  }

  @MainActor
  static func storePastedImage(
    _ image: NSImage,
    for noteID: DayNote.ID,
    fileManager: FileManager = .default,
    rootURL: URL? = nil
  ) throws -> StoredImageAttachment {
    guard let data = pngData(from: image) else {
      throw NoteImageAttachmentStoreError.imageEncodingFailed
    }

    let directoryURL = try noteAttachmentDirectoryURL(
      for: noteID,
      fileManager: fileManager,
      rootURL: rootURL
    )
    let destinationURL = uniqueDestinationURL(
      in: directoryURL,
      preferredFileName: "\(pastedImageBaseName).png",
      fileManager: fileManager
    )

    try data.write(to: destinationURL, options: .atomic)

    return StoredImageAttachment(
      relativePath: relativePath(for: noteID, fileName: destinationURL.lastPathComponent),
      title: "Image"
    )
  }

  nonisolated static func deleteAttachments(
    for noteID: DayNote.ID,
    fileManager: FileManager = .default,
    rootURL: URL? = nil
  ) throws {
    let directoryURL = try noteAttachmentDirectoryURL(
      for: noteID,
      fileManager: fileManager,
      rootURL: rootURL,
      createIfNeeded: false
    )
    guard fileManager.fileExists(atPath: directoryURL.path) else { return }
    try fileManager.removeItem(at: directoryURL)
  }

  nonisolated static func moveAttachments(
    from oldNoteID: DayNote.ID,
    to newNoteID: DayNote.ID,
    fileManager: FileManager = .default,
    rootURL: URL? = nil
  ) throws {
    let sourceURL = try noteAttachmentDirectoryURL(
      for: oldNoteID,
      fileManager: fileManager,
      rootURL: rootURL,
      createIfNeeded: false
    )
    guard fileManager.fileExists(atPath: sourceURL.path) else { return }

    let destinationURL = try noteAttachmentDirectoryURL(
      for: newNoteID,
      fileManager: fileManager,
      rootURL: rootURL,
      createIfNeeded: false
    )
    if fileManager.fileExists(atPath: destinationURL.path) {
      try fileManager.removeItem(at: destinationURL)
    }
    try fileManager.moveItem(at: sourceURL, to: destinationURL)
  }

  // Copies missing attachments without overwriting files already owned by the destination note.
  nonisolated static func copyAttachments(
    from oldNoteID: DayNote.ID,
    to newNoteID: DayNote.ID,
    fileManager: FileManager = .default,
    rootURL: URL? = nil
  ) throws {
    let sourceURL = try noteAttachmentDirectoryURL(
      for: oldNoteID,
      fileManager: fileManager,
      rootURL: rootURL,
      createIfNeeded: false
    )
    guard fileManager.fileExists(atPath: sourceURL.path) else { return }

    let destinationURL = try noteAttachmentDirectoryURL(
      for: newNoteID,
      fileManager: fileManager,
      rootURL: rootURL,
      createIfNeeded: false
    )
    let sourceFileURLs = try fileManager.contentsOfDirectory(
      at: sourceURL,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )

    for sourceFileURL in sourceFileURLs {
      let destinationFileURL = destinationURL.appendingPathComponent(
        sourceFileURL.lastPathComponent
      )
      guard fileManager.fileExists(atPath: destinationFileURL.path) else { continue }
      guard try Data(contentsOf: sourceFileURL) == Data(contentsOf: destinationFileURL) else {
        throw NoteImageAttachmentStoreError.conflictingAttachment(
          destinationFileURL.lastPathComponent,
          noteID: newNoteID
        )
      }
    }

    try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
    for sourceFileURL in sourceFileURLs {
      let destinationFileURL = destinationURL.appendingPathComponent(
        sourceFileURL.lastPathComponent
      )
      guard !fileManager.fileExists(atPath: destinationFileURL.path) else { continue }
      try fileManager.copyItem(at: sourceFileURL, to: destinationFileURL)
    }
  }

  nonisolated static func copyAttachmentFolders(
    for noteIDs: Set<DayNote.ID>,
    from sourceRootURL: URL,
    to targetRootURL: URL,
    fileManager: FileManager = .default
  ) throws {
    guard !noteIDs.isEmpty, fileManager.fileExists(atPath: sourceRootURL.path) else { return }
    try fileManager.createDirectory(at: targetRootURL, withIntermediateDirectories: true)

    for noteID in noteIDs {
      let folderName = safePathComponent(noteID)
      let sourceURL = sourceRootURL.appendingPathComponent(folderName, isDirectory: true)
      guard fileManager.fileExists(atPath: sourceURL.path) else { continue }

      let destinationURL = targetRootURL.appendingPathComponent(folderName, isDirectory: true)
      if fileManager.fileExists(atPath: destinationURL.path) {
        try fileManager.removeItem(at: destinationURL)
      }
      try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }
  }

  nonisolated static func attachmentRootInArchive(
    rootURL: URL,
    fileManager: FileManager = .default
  ) -> URL? {
    let directURL = rootURL.appendingPathComponent(attachmentsFolderName, isDirectory: true)
    if fileManager.fileExists(atPath: directURL.path) {
      return directURL
    }

    guard
      let enumerator = fileManager.enumerator(
        at: rootURL,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      )
    else { return nil }

    for case let candidateURL as URL in enumerator {
      guard candidateURL.lastPathComponent == attachmentsFolderName else { continue }
      var isDirectory: ObjCBool = false
      guard fileManager.fileExists(atPath: candidateURL.path, isDirectory: &isDirectory),
        isDirectory.boolValue
      else { continue }
      return candidateURL
    }

    return nil
  }

  nonisolated static func resolvedImageURL(
    for markdownPath: String,
    libraryRootURL: URL? = nil,
    fileManager: FileManager = .default
  ) -> URL? {
    if markdownPath.hasPrefix("/") {
      return URL(fileURLWithPath: markdownPath)
    }

    if let libraryRootURL {
      let normalizedPath =
        markdownPath.hasPrefix("../")
        ? String(markdownPath.dropFirst(3))
        : markdownPath
      return libraryRootURL.appendingPathComponent(normalizedPath)
    }

    guard
      let appSupportURL = try? fileManager.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: false
      )
    else { return nil }

    let scealURL = appSupportURL.appendingPathComponent(scealFolderName, isDirectory: true)
    let normalizedPath =
      markdownPath.hasPrefix("../")
      ? String(markdownPath.dropFirst(3))
      : markdownPath

    return scealURL.appendingPathComponent(normalizedPath)
  }

  nonisolated static func relativePath(for noteID: DayNote.ID, fileName: String) -> String {
    "../\(attachmentsFolderName)/\(safePathComponent(noteID))/\(fileName)"
  }

  nonisolated static func rewritingAttachmentReferences(
    in markdown: String,
    from oldNoteID: DayNote.ID,
    to newNoteID: DayNote.ID
  ) -> String {
    markdown.replacingOccurrences(
      of: "../\(attachmentsFolderName)/\(safePathComponent(oldNoteID))/",
      with: "../\(attachmentsFolderName)/\(safePathComponent(newNoteID))/"
    )
  }

  nonisolated static func safePathComponent(_ value: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    let scalars = value.unicodeScalars.map { scalar -> Character in
      allowed.contains(scalar) ? Character(scalar) : "-"
    }
    let sanitized = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return sanitized.isEmpty ? "note" : sanitized
  }

  @MainActor
  private static func pngData(from image: NSImage) -> Data? {
    guard
      let tiffData = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData)
    else { return nil }

    return bitmap.representation(using: .png, properties: [:])
  }

  nonisolated private static func isSupportedImageFile(_ url: URL) -> Bool {
    if let resourceValues = try? url.resourceValues(forKeys: [.contentTypeKey]),
      resourceValues.contentType?.conforms(to: .image) == true
    {
      return true
    }

    let knownExtensions = ["png", "jpg", "jpeg", "gif", "tiff", "tif", "heic", "webp"]
    return knownExtensions.contains(url.pathExtension.lowercased())
  }

  nonisolated private static func uniqueDestinationURL(
    in directoryURL: URL,
    preferredFileName: String,
    fileManager: FileManager
  ) -> URL {
    let sanitizedFileName = safeFileName(preferredFileName)
    let baseName = (sanitizedFileName as NSString).deletingPathExtension
    let fileExtension = (sanitizedFileName as NSString).pathExtension
    var candidateURL = directoryURL.appendingPathComponent(sanitizedFileName)
    var suffix = 2

    while fileManager.fileExists(atPath: candidateURL.path) {
      let fileName =
        fileExtension.isEmpty ? "\(baseName)-\(suffix)" : "\(baseName)-\(suffix).\(fileExtension)"
      candidateURL = directoryURL.appendingPathComponent(fileName)
      suffix += 1
    }

    return candidateURL
  }

  nonisolated private static func safeFileName(_ fileName: String) -> String {
    let name = (fileName as NSString).deletingPathExtension
    let fileExtension = (fileName as NSString).pathExtension.lowercased()
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    let sanitizedNameScalars = name.unicodeScalars.map { scalar -> Character in
      allowed.contains(scalar) ? Character(scalar) : "-"
    }
    let sanitizedName =
      String(sanitizedNameScalars)
      .replacingOccurrences(of: "--+", with: "-", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    let resolvedName = sanitizedName.isEmpty ? pastedImageBaseName : sanitizedName
    return fileExtension.isEmpty ? resolvedName : "\(resolvedName).\(fileExtension)"
  }

  nonisolated private static func title(from sourceURL: URL) -> String {
    let stem = sourceURL.deletingPathExtension().lastPathComponent
    let normalized = stem.replacingOccurrences(of: "[-_]+", with: " ", options: .regularExpression)
    let title = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    return title.isEmpty ? "Image" : title
  }
}

enum NoteImageAttachmentStoreError: LocalizedError {
  case unsupportedImage(URL)
  case imageEncodingFailed
  case conflictingAttachment(String, noteID: String)

  var errorDescription: String? {
    switch self {
    case .unsupportedImage(let url):
      return "\(url.lastPathComponent) is not a supported image file."
    case .imageEncodingFailed:
      return "Scéal could not encode the pasted image."
    case .conflictingAttachment(let fileName, let noteID):
      return "Attachment \(fileName) already has different contents for note \(noteID)."
    }
  }
}
