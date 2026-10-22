import Foundation
@testable import Sceal
import XCTest

@MainActor
final class NotesStoreGitHubTests: NotesStoreTestCase {
  // A background PR request must not prevent entering or validating a replacement token.
  func testConnectionValidationIsAvailableDuringBackgroundRefresh() async {
    let store = makeStore()
    store.isRefreshingGitHub = true

    await store.connectGitHub(token: " ")

    XCTAssertEqual(store.githubError, "Enter a GitHub personal access token.")
    XCTAssertFalse(store.isConnectingGitHub)
    XCTAssertTrue(store.isRefreshingGitHub)
  }

  // The real copy-previous path preserves yesterday and creates only unfinished carryover.
  func testCopyPreviousKeepsSourceSnapshotAndDropsCompletedPRs() throws {
    let calendar = Calendar.current
    let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: .now))!
    let open = GitHubPREntry(
      id: 1, number: 1, title: "Open work", repository: "Teamwork/teamwork-lightspeed",
      url: URL(string: "https://github.com/Teamwork/teamwork-lightspeed/pull/1")!,
      createdAt: yesterday, isDraft: false)
    var merged = open
    merged.id = 2
    merged.number = 2
    merged.closedAt = yesterday.addingTimeInterval(3600)
    merged.mergedAt = merged.closedAt
    let source = StructuredNoteDocument(
      id: NoteDateFormatters.storageDate.string(from: yesterday),
      date: yesterday, title: "", tags: [],
      nodes: [
        .section(
          StructuredNoteSection(
            markdown: StructuredNoteSection.githubMarker,
            githubSnapshot: GitHubPRSnapshot(
              entries: [open, merged], refreshedAt: yesterday, account: "author"),
            githubLayout: GitHubPRSectionLayout(
              firstGroup: .carriedForward, isCompact: true, showsIcons: false, showsDividers: false,
              colorMode: .section)))
      ])
    let store = makeStore()
    store.structuredNotes = [source]
    store.selectedStructuredNoteID = source.id
    store.updateNewNoteDefault(.copyPrevious)

    store.selectStructuredDailyDate(.now)

    let created = try XCTUnwrap(store.selectedStructuredNote)
    XCTAssertNotEqual(created.id, source.id)
    XCTAssertEqual(created.githubSections.first?.githubSnapshot?.entries, [open])
    XCTAssertNil(created.githubSections.first?.githubSnapshot?.refreshedAt)
    XCTAssertEqual(
      created.githubSections.first?.githubLayout, source.githubSections.first?.githubLayout)
    XCTAssertNotEqual(created.githubSections.first?.id, source.githubSections.first?.id)
    XCTAssertEqual(store.structuredNotes.first(where: { $0.id == source.id }), source)
  }

  // Historical refresh returns before credentials or the network are accessed.
  func testHistoricalNoteCannotBeRefreshed() async {
    let date = makeDate(year: 2020, month: 1, day: 1)
    let original = StructuredNoteDocument(
      id: "2020-01-01", date: date, title: "", tags: [],
      nodes: [
        .section(
          StructuredNoteSection(
            markdown: StructuredNoteSection.githubMarker,
            githubSnapshot: GitHubPRSnapshot(refreshedAt: date, account: "author")))
      ])
    let store = makeStore()
    store.structuredNotes = [original]
    store.selectedStructuredNoteID = original.id

    await store.refreshGitHub(documentID: original.id)

    XCTAssertEqual(store.selectedStructuredNote, original)
    XCTAssertNil(store.githubError)
    XCTAssertFalse(store.isRefreshingGitHub)
  }
}
