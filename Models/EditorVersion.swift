//
//  EditorVersion.swift
//

// App-level editor engine choice used during the TextKit migration.

import Foundation

enum EditorVersion: String, CaseIterable, Codable, Sendable {
  case legacy
  case next

  var title: String {
    switch self {
    case .legacy:
      return "Legacy"
    case .next:
      return "Next"
    }
  }

  var engineLabel: String {
    switch self {
    case .legacy:
      return "TextKit 1"
    case .next:
      return "TextKit 2"
    }
  }
}
