import Foundation
import XCTest

@testable import Sceal

final class ScealLibraryLocationTests: XCTestCase {
  // Keeps test roots injectable so migration tests never need the real app-support library.
  func testInjectedRootCreatesLibraryDirectoriesUnderThatRoot() throws {
    let rootURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("ScealLibraryLocationTests-\(UUID().uuidString)", isDirectory: true)
    addTeardownBlock {
      try? FileManager.default.removeItem(at: rootURL)
    }

    let location = ScealLibraryLocation.test(rootURL: rootURL)
    let notesURL = try location.notesDirectoryURL()
    let listNotesURL = try location.listNotesDirectoryURL()
    let attachmentsURL = try location.attachmentsRootURL()
    let restoreURL = try location.restoreSafetyArchiveDirectoryURL()

    XCTAssertEqual(notesURL.deletingLastPathComponent(), rootURL)
    XCTAssertEqual(listNotesURL.deletingLastPathComponent(), rootURL)
    XCTAssertEqual(attachmentsURL.deletingLastPathComponent(), rootURL)
    XCTAssertEqual(restoreURL.deletingLastPathComponent(), rootURL)
    XCTAssertTrue(FileManager.default.fileExists(atPath: notesURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: listNotesURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: attachmentsURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: restoreURL.path))
  }

  #if DEBUG
    // Protects DEBUG builds from defaulting to the production note library.
    func testDebugDefaultUsesDeveloperLibraryFolder() {
      let location = ScealLibraryLocation.defaultForCurrentBuild()

      XCTAssertEqual(location.rootURL.lastPathComponent, ScealLibraryLocation.developerFolderName)
    }
  #endif
}
