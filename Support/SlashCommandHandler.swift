//
//  SlashCommandHandler.swift
//  dayra
//
//

import AppKit

struct SlashCommandEntry {
  let command: String
  let description: String
}

enum SlashCommandHandler {

  static let commands: [SlashCommandEntry] = [
    SlashCommandEntry(command: "/section", description: "Insert section divider"),
    SlashCommandEntry(command: "/div", description: "Insert section divider"),
  ]

  /// Returns commands whose name starts with the given prefix (e.g. "/" or "/d").
  static func filteredCommands(for prefix: String) -> [SlashCommandEntry] {
    let lower = prefix.lowercased()
    if lower == "/" { return commands }
    return commands.filter { $0.command.lowercased().hasPrefix(lower) }
  }

  /// Checks if the text in `lineRange` is a slash command. If yes, replaces it
  /// with a markdown horizontal rule and returns true. Returns false otherwise.
  static func detectAndReplace(in textStorage: NSTextStorage, lineRange: NSRange) -> Bool {
    let lineText = (textStorage.string as NSString).substring(with: lineRange)
    let trimmed = lineText.trimmingCharacters(in: .whitespaces)

    guard commands.contains(where: { $0.command.caseInsensitiveCompare(trimmed) == .orderedSame })
    else {
      return false
    }

    textStorage.beginEditing()
    textStorage.replaceCharacters(in: lineRange, with: "<!-- section -->")
    textStorage.endEditing()

    return true
  }
}
