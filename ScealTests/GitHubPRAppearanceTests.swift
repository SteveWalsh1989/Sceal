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

  // Section choices round-trip independently of PR records and can return to inheritance.
  func testSectionLayoutPersistenceAndReset() throws {
    let section = StructuredNoteSection(markdown: "<!-- sceal:github-prs -->")
    var document = StructuredNoteDocument(
      id: "2026-10-22", date: Date(), title: "", tags: [], nodes: [.section(section)])
    let layout = GitHubPRSectionLayout(
      firstGroup: .carriedForward, isCompact: true, showsIcons: false, showsDividers: false,
      colorMode: .custom, customColorName: "purple")
    try document.setGitHubLayout(layout, sectionID: section.id)
    let encoded = try JSONEncoder().encode(document)
    let decoded = try JSONDecoder().decode(StructuredNoteDocument.self, from: encoded)
    guard case .section(let savedSection) = decoded.nodes[0] else {
      return XCTFail("Expected a section")
    }
    XCTAssertEqual(savedSection.githubLayout, layout)
    XCTAssertNil(savedSection.githubSnapshot)
    try document.setGitHubLayout(nil, sectionID: section.id)
    XCTAssertEqual(document.nodes, [.section(section)])
  }

  // Notes saved before section layout existed retain app defaults.
  func testLegacySectionHasNoLayoutOverride() throws {
    let section = StructuredNoteSection()
    let encoded = try JSONEncoder().encode(section)
    let decoded = try JSONDecoder().decode(StructuredNoteSection.self, from: encoded)
    XCTAssertNil(decoded.githubLayout)
  }

  // Existing compact sections decode with the original icons, dividers, and default colours.
  func testLegacyLayoutRemainsCompatible() throws {
    let data = Data(#"{"firstGroup":"today","isCompact":true}"#.utf8)
    let layout = try JSONDecoder().decode(GitHubPRSectionLayout.self, from: data)
    XCTAssertTrue(layout.isCompact)
    XCTAssertTrue(layout.showsIcons ?? true)
    XCTAssertTrue(layout.showsDividers ?? true)
    XCTAssertEqual(layout.colorMode ?? .standard, .standard)
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
