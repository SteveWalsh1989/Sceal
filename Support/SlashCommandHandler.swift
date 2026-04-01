//
//  SlashCommandHandler.swift
//  dayra
//
//  Created by Steve Walsh on 01/04/2026.
//

import AppKit

enum SlashCommandHandler {
  enum BlockType: String, CaseIterable {
    case meeting
    case feature
    case pr
    case other

    var command: String {
      "/\(rawValue)"
    }

    var displayLabel: String {
      switch self {
      case .meeting: return "Meeting"
      case .feature: return "Feature"
      case .pr: return "PR"
      case .other: return "Other"
      }
    }

    var markdownComment: String {
      "<!-- block:\(rawValue) -->"
    }
  }

  /// Checks if the text in `lineRange` is a slash command. If yes, replaces it
  /// with the block marker comment and returns true. Returns false otherwise.
  static func detectAndReplace(in textStorage: NSTextStorage, lineRange: NSRange) -> Bool {
    let lineText = (textStorage.string as NSString).substring(with: lineRange)
    let trimmed = lineText.trimmingCharacters(in: .whitespaces)

    guard
      let matched = BlockType.allCases.first(where: {
        $0.command.caseInsensitiveCompare(trimmed) == .orderedSame
      })
    else {
      return false
    }

    textStorage.beginEditing()
    textStorage.replaceCharacters(in: lineRange, with: matched.markdownComment)
    textStorage.endEditing()

    return true
  }
}
