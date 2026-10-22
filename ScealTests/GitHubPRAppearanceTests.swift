@testable import Sceal
import XCTest

@MainActor
final class GitHubPRAppearanceTests: NotesStoreTestCase {
  // Preferences survive a fresh store instance rather than being stored in individual notes.
  func testAppearancePersistsAcrossStoresAndResetRestoresDefaults() {
    let defaults = makeUserDefaults()
    let store = makeStore(userDefaults: defaults)
    store.githubPRAppearance.title = "My pull requests"
    store.githubPRAppearance.titleColorName = "purple"
    store.githubPRAppearance.firstGroup = .carriedForward
    store.githubPRAppearance.todayLabel = "New"
    store.githubPRAppearance.carriedForwardLabel = "In progress"
    store.githubPRAppearance.hidesEmptyGroups = false
    let reopened = makeStore(userDefaults: defaults)
    XCTAssertEqual(reopened.githubPRAppearance, store.githubPRAppearance)
    XCTAssertEqual(reopened.githubPRAppearance.orderedGroups, [.carriedForward, .today])
    reopened.githubPRAppearance = GitHubPRAppearance()
    XCTAssertEqual(makeStore(userDefaults: defaults).githubPRAppearance, GitHubPRAppearance())
  }

  // Blank labels retain readable headings while a user edits their preferences.
  func testBlankLabelsUseDefaults() {
    var appearance = GitHubPRAppearance()
    appearance.title = " "
    appearance.todayLabel = "\n"
    appearance.carriedForwardLabel = ""
    XCTAssertEqual(appearance.displayedTitle, "PRs")
    XCTAssertEqual(appearance.label(for: .today), "Opened today")
    XCTAssertEqual(appearance.label(for: .carriedForward), "Carried forward")
    XCTAssertTrue(appearance.hidesEmptyGroups)
  }
}
