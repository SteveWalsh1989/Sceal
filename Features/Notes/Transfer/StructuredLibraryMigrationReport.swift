//
//  StructuredLibraryMigrationReport.swift
//

// Records the safety and fidelity checks performed by an explicit full-library upgrade.

import Foundation

nonisolated struct StructuredLibraryMigrationReport: Codable, Equatable, Sendable {
  static let currentVersion = 1

  let version: Int
  let createdAt: Date
  let safetyArchiveName: String
  let legacyLibraryPreserved: Bool
  let sourceDailyNoteCount: Int
  let structuredDailyNoteCount: Int
  let matchingDailyNoteCount: Int
  let mismatchedDailyNoteIDs: [String]
  let sourceListNoteCount: Int
  let structuredListNoteCount: Int
  let matchingListNoteCount: Int
  let mismatchedListNoteIDs: [String]
  let listNoteOrderMatches: Bool
  let listNoteGroupsMatch: Bool
  let attachmentFolderCount: Int
  let attachmentFileCount: Int
  let templateCount: Int
  let themeID: String
  let includesCustomThemeColors: Bool
  let portableSettingsVersion: Int

  var passedContentValidation: Bool {
    mismatchedDailyNoteIDs.isEmpty
      && mismatchedListNoteIDs.isEmpty
      && matchingDailyNoteCount == sourceDailyNoteCount
      && matchingListNoteCount == sourceListNoteCount
      && listNoteOrderMatches
      && listNoteGroupsMatch
  }
}

nonisolated enum StructuredLibraryMigrationReporter {
  // Compares converted source documents with persisted targets while ignoring generated UUIDs.
  static func makeReport(
    createdAt: Date,
    safetyArchiveURL: URL,
    sourceDailyDocuments: [StructuredNoteDocument],
    sourceListDocuments: [StructuredNoteDocument],
    sourceListManifest: ListNotesManifest,
    structuredDailyDocuments: [StructuredNoteDocument],
    structuredListDocuments: [StructuredNoteDocument],
    structuredListManifest: ListNotesManifest,
    attachmentsRootURL: URL,
    templates: [NoteTemplate],
    settings: ScealArchiveSettings,
    legacyLibraryPreserved: Bool,
    fileManager: FileManager = .default
  ) throws -> StructuredLibraryMigrationReport {
    let dailyComparison = compare(
      sourceDocuments: sourceDailyDocuments,
      targetDocuments: structuredDailyDocuments
    )
    let listComparison = compare(
      sourceDocuments: sourceListDocuments,
      targetDocuments: structuredListDocuments
    )
    let attachmentCounts = try countAttachments(
      at: attachmentsRootURL,
      fileManager: fileManager
    )

    return StructuredLibraryMigrationReport(
      version: StructuredLibraryMigrationReport.currentVersion,
      createdAt: createdAt,
      safetyArchiveName: safetyArchiveURL.lastPathComponent,
      legacyLibraryPreserved: legacyLibraryPreserved,
      sourceDailyNoteCount: sourceDailyDocuments.count,
      structuredDailyNoteCount: structuredDailyDocuments.count,
      matchingDailyNoteCount: dailyComparison.matchingCount,
      mismatchedDailyNoteIDs: dailyComparison.mismatchedIDs,
      sourceListNoteCount: sourceListDocuments.count,
      structuredListNoteCount: structuredListDocuments.count,
      matchingListNoteCount: listComparison.matchingCount,
      mismatchedListNoteIDs: listComparison.mismatchedIDs,
      listNoteOrderMatches: sourceListManifest.ungroupedNoteIDs
        == structuredListManifest.ungroupedNoteIDs,
      listNoteGroupsMatch: sourceListManifest.groups == structuredListManifest.groups,
      attachmentFolderCount: attachmentCounts.folders,
      attachmentFileCount: attachmentCounts.files,
      templateCount: templates.count,
      themeID: settings.themeID,
      includesCustomThemeColors: settings.includesCustomThemeColors,
      portableSettingsVersion: settings.version
    )
  }

  // Writes a stable, human-inspectable JSON report beside migration safety archives.
  static func writeReport(
    _ report: StructuredLibraryMigrationReport,
    to directoryURL: URL,
    fileManager: FileManager = .default
  ) throws -> URL {
    try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
    var reportURL = directoryURL.appendingPathComponent(
      "structured-upgrade-\(formatter.string(from: report.createdAt)).json"
    )
    if fileManager.fileExists(atPath: reportURL.path) {
      reportURL = directoryURL.appendingPathComponent(
        "structured-upgrade-\(formatter.string(from: report.createdAt))-\(UUID().uuidString).json"
      )
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(report).write(to: reportURL, options: .atomic)
    return reportURL
  }

  private static func compare(
    sourceDocuments: [StructuredNoteDocument],
    targetDocuments: [StructuredNoteDocument]
  ) -> (matchingCount: Int, mismatchedIDs: [String]) {
    let targetByID = Dictionary(uniqueKeysWithValues: targetDocuments.map { ($0.id, $0) })
    let mismatchedIDs = sourceDocuments.compactMap { sourceDocument -> String? in
      guard let targetDocument = targetByID[sourceDocument.id],
        signature(for: sourceDocument) == signature(for: targetDocument)
      else { return sourceDocument.id }
      return nil
    }
    return (sourceDocuments.count - mismatchedIDs.count, mismatchedIDs.sorted())
  }

  private static func signature(for document: StructuredNoteDocument) -> DocumentSignature {
    DocumentSignature(
      date: document.date,
      title: document.title,
      tags: document.tags,
      nodes: document.nodes.map { node in
        switch node {
        case .section(let section):
          return .section(sectionSignature(for: section))
        case .group(let group):
          return .group(
            title: group.title,
            style: group.style,
            isCollapsed: group.isCollapsed,
            showsTypeLabel: group.showsTypeLabel,
            showsSectionCount: group.showsSectionCount,
            sections: group.sections.map(sectionSignature(for:))
          )
        }
      }
    )
  }

  private static func sectionSignature(for section: StructuredNoteSection) -> SectionSignature {
    SectionSignature(
      markdown: normalizedMarkdown(section.markdown),
      styleOverrides: section.styleOverrides,
      isCollapsed: section.isCollapsed
    )
  }

  private static func normalizedMarkdown(_ markdown: String) -> String {
    markdown
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .split(separator: "\n", omittingEmptySubsequences: false)
      .map { $0.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression) }
      .joined(separator: "\n")
      .trimmingCharacters(in: .newlines)
  }

  private static func countAttachments(
    at rootURL: URL,
    fileManager: FileManager
  ) throws -> (folders: Int, files: Int) {
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else { return (0, 0) }

    let folderURLs = try fileManager.contentsOfDirectory(
      at: rootURL,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    ).filter {
      (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
    let fileCount = try folderURLs.reduce(into: 0) { count, folderURL in
      count += try fileManager.contentsOfDirectory(
        at: folderURL,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
      ).filter {
        (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
      }.count
    }
    return (folderURLs.count, fileCount)
  }
}

private nonisolated struct DocumentSignature: Equatable {
  let date: Date
  let title: String
  let tags: [String]
  let nodes: [NodeSignature]
}

private nonisolated enum NodeSignature: Equatable {
  case section(SectionSignature)
  case group(
    title: String,
    style: StructuredSectionStyle,
    isCollapsed: Bool,
    showsTypeLabel: Bool?,
    showsSectionCount: Bool?,
    sections: [SectionSignature]
  )
}

private nonisolated struct SectionSignature: Equatable {
  let markdown: String
  let styleOverrides: StructuredSectionStyleOverrides
  let isCollapsed: Bool
}
