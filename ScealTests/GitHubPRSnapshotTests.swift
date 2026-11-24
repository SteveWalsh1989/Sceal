import Foundation
@testable import Sceal
import XCTest

final class GitHubPRSnapshotTests: XCTestCase {
  private let monday = Date(timeIntervalSince1970: 1_790_035_200)
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }

  // Updating Friday must never rewrite the four earlier daily values.
  func testMergePreservesEarlierDaysAndStopsCarryingForward() throws {
    let open = entry()
    let friday = monday.addingTimeInterval(4 * 86400)
    let earlierDays = (0..<4).map { offset in
      GitHubPRSnapshot().refreshed(
        with: [open], on: monday.addingTimeInterval(Double(offset) * 86400),
        at: monday, account: "author", calendar: calendar)
    }
    var merged = open
    merged.closedAt = friday.addingTimeInterval(3600)
    merged.mergedAt = merged.closedAt
    let fridaySnapshot = try XCTUnwrap(earlierDays.last).carriedForward().refreshed(
      with: [merged], on: friday, at: friday.addingTimeInterval(7200), account: "author",
      calendar: calendar)

    XCTAssertTrue(earlierDays.allSatisfy { $0.entries.first?.status == "Open" })
    XCTAssertEqual(fridaySnapshot.entries.first?.status, "Merged")
    XCTAssertTrue(fridaySnapshot.carriedForward().entries.isEmpty)
  }

  // A PR created and merged during the same day remains part of that day's work.
  func testSameDayMergedPRIsRetained() {
    var merged = entry()
    merged.createdAt = monday.addingTimeInterval(3600)
    merged.closedAt = monday.addingTimeInterval(7200)
    merged.mergedAt = merged.closedAt
    let snapshot = GitHubPRSnapshot().refreshed(
      with: [merged], on: monday,
      at: monday.addingTimeInterval(8000), account: "author", calendar: calendar)
    XCTAssertEqual(snapshot.entries, [merged])
  }

  // A stale copied PR is removed once GitHub reports it completed before the new day.
  func testRefreshDropsPreviouslyCompletedPRAndDeduplicates() {
    let original = entry()
    var merged = original
    merged.closedAt = monday.addingTimeInterval(3600)
    merged.mergedAt = merged.closedAt
    let copied = GitHubPRSnapshot(entries: [original])
    let nextDay = monday.addingTimeInterval(86400)
    XCTAssertTrue(
      copied.refreshed(
        with: [merged], on: nextDay, at: nextDay,
        account: "author", calendar: calendar
      ).entries.isEmpty)
    XCTAssertEqual(
      copied.refreshed(
        with: [original, original], on: monday, at: monday,
        account: "author", calendar: calendar
      ).entries.count, 1)
  }

  // The ordinary note codec owns the PR data so backups preserve snapshots without credentials.
  func testSnapshotRoundTripsAndExportsReadableMarkdown() throws {
    let snapshot = GitHubPRSnapshot(entries: [entry()], refreshedAt: monday, account: "author")
    let document = StructuredNoteDocument(
      id: "2026-09-22", date: monday, title: "", tags: [],
      nodes: [
        .section(
          StructuredNoteSection(
            markdown: StructuredNoteSection.githubMarker, githubSnapshot: snapshot))
      ])
    XCTAssertEqual(
      try StructuredNoteDocumentCodec.decode(StructuredNoteDocumentCodec.encode(document)), document
    )
    let exported = try StructuredNoteMarkdownExporter.body(for: document)
    XCTAssertTrue(exported.contains("https://github.com/Teamwork/teamwork-lightspeed/pull/1"))
    XCTAssertTrue(exported.contains("Open"))
    XCTAssertFalse(exported.contains(StructuredNoteSection.githubMarker))
  }

  // Notes written before the integration continue to decode without a snapshot field.
  func testLegacySectionDecodesWithoutSnapshot() throws {
    let section = StructuredNoteSection(markdown: "Ordinary note")
    let data = try JSONEncoder().encode(section)
    XCTAssertNil(try JSONDecoder().decode(StructuredNoteSection.self, from: data).githubSnapshot)
  }

  // The slash command creates a separate section while preserving surrounding prose.
  @MainActor
  func testGitHubSlashCommandPreservesSurroundingText() throws {
    let command = try XCTUnwrap(
      EditorSlashCommandHandler.commands.first { $0.command == "/github" })
    guard case .template(let template) = command.action else {
      return XCTFail("Expected a section template")
    }
    let result = try StructuredNoteTemplateAdapter.insert(
      StructuredTemplateInsertionRequest(
        leadingMarkdown: "Before\n", trailingMarkdown: "\nAfter",
        template: template, preservesReplacedLineBreak: false), replacing: StructuredNoteSection())
    XCTAssertEqual(result.sections.count, 3)
    XCTAssertEqual(result.sections.first?.markdown, "Before\n\nAfter")
    XCTAssertTrue(result.sections.contains(where: \.isGitHubSection))
    XCTAssertEqual(result.sections.last?.markdown, "")
    XCTAssertEqual(result.focusSectionID, result.sections.last?.id)
  }

  // Clearing an integration section is undoable without leaving hidden PR data attached.
  func testClearingSectionRemovesSnapshotAndMergeCannotLoseIt() throws {
    let section = StructuredNoteSection(
      markdown: StructuredNoteSection.githubMarker,
      githubSnapshot: GitHubPRSnapshot(entries: [entry()]))
    var document = StructuredNoteDocument(
      id: "test", date: monday, title: "", tags: [],
      nodes: [.section(section), .section(StructuredNoteSection(markdown: "Notes"))])
    XCTAssertThrowsError(try document.mergeSection(id: section.id, direction: .next))
    try document.setSectionMarkdown("", sectionID: section.id)
    guard case .section(let cleared) = document.nodes[0] else {
      return XCTFail("Expected a section")
    }
    XCTAssertNil(cleared.githubSnapshot)
    XCTAssertFalse(cleared.isGitHubSection)
  }

  // Refreshing hidden work retains current data for restoration without making it visible again.
  func testRemovedPRStaysHiddenAcrossRefreshAndPersistence() throws {
    let original = entry()
    var merged = original
    merged.closedAt = monday.addingTimeInterval(3600)
    merged.mergedAt = merged.closedAt
    let snapshot = GitHubPRSnapshot(
      entries: [original], refreshedAt: monday, account: "author", removedEntryIDs: [original.id])
    let refreshed = snapshot.refreshed(
      with: [merged], on: monday, at: monday.addingTimeInterval(7200),
      account: "author", calendar: calendar)
    let saved = try JSONDecoder().decode(
      GitHubPRSnapshot.self, from: JSONEncoder().encode(refreshed))

    XCTAssertTrue(saved.visibleEntries.isEmpty)
    XCTAssertEqual(saved.entries, [merged])
    XCTAssertEqual(saved.removedEntryIDs, [original.id])
    XCTAssertFalse(saved.markdown.contains(original.url.absoluteString))
    XCTAssertEqual(snapshot.entries, [original])
  }

  // Suppression belongs to one day's record and does not become a permanent account preference.
  func testRemovedPRDoesNotCarryForwardAndLegacySnapshotsShowAllEntries() throws {
    let original = entry()
    let snapshot = GitHubPRSnapshot(entries: [original], removedEntryIDs: [original.id])
    let nextDay = snapshot.carriedForward()
    XCTAssertTrue(nextDay.entries.isEmpty)
    XCTAssertNil(nextDay.removedEntryIDs)
    XCTAssertEqual(
      nextDay.refreshed(
        with: [original], on: monday.addingTimeInterval(86400), at: monday,
        account: "author", calendar: calendar
      ).visibleEntries, [original])

    let legacy = GitHubPRSnapshot(entries: [original])
    let saved = try JSONDecoder().decode(
      GitHubPRSnapshot.self, from: JSONEncoder().encode(legacy))
    XCTAssertNil(saved.removedEntryIDs)
    XCTAssertEqual(saved.visibleEntries, [original])
  }

  // Restoring a historical day's saved records needs no network and preserves neighboring sections.
  func testRemovedPRsCanBeRestoredFromHistoricalDocument() throws {
    let original = entry()
    let section = StructuredNoteSection(githubSnapshot: GitHubPRSnapshot(entries: [original]))
    let neighbor = StructuredNoteSection(markdown: "Keep my notes")
    var document = StructuredNoteDocument(
      id: "historical", date: monday, title: "", tags: [],
      nodes: [.section(section), .section(neighbor)])
    try document.setGitHubRemovedEntryIDs([original.id], sectionID: section.id)
    document = try StructuredNoteDocumentCodec.decode(StructuredNoteDocumentCodec.encode(document))
    XCTAssertTrue(
      try XCTUnwrap(document.githubSections.first?.githubSnapshot).visibleEntries.isEmpty)
    XCTAssertFalse(try StructuredNoteMarkdownExporter.body(for: document).contains(original.title))

    try document.setGitHubRemovedEntryIDs(nil, sectionID: section.id)

    XCTAssertEqual(document.nodes, [.section(section), .section(neighbor)])
    XCTAssertTrue(try StructuredNoteMarkdownExporter.body(for: document).contains(original.title))
    XCTAssertThrowsError(try document.setGitHubRemovedEntryIDs([original.id], sectionID: UUID()))
  }

  // Builds an authored PR that predates each test day.
  private func entry() -> GitHubPREntry {
    GitHubPREntry(
      id: 1, number: 1, title: "Fix the table", repository: "Teamwork/teamwork-lightspeed",
      url: URL(string: "https://github.com/Teamwork/teamwork-lightspeed/pull/1")!,
      createdAt: monday.addingTimeInterval(-86400), isDraft: false)
  }
}
