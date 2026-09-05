import Foundation

enum LibraryOperationError: LocalizedError {
  case pendingChanges
  case operationInProgress

  var errorDescription: String? {
    switch self {
    case .pendingChanges:
      return
        "Some note changes could not be saved. Your edits remain open for retry. Check disk space and folder permissions, then try again before closing Scéal."
    case .operationInProgress:
      return "Wait for the current file operation or backup to finish."
    }
  }
}
