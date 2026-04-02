//
//  SlashCommandHandler.swift
//  dayra
//
//

import AppKit

struct SlashCommandEntry {
  let command: String
  let description: String
  let action: SlashCommandAction
}

enum SlashCommandAction: Equatable {
  case sectionDivider
  case heading(level: Int)
  case codeBlock
}

enum SlashCommandHandler {

  static let commands: [SlashCommandEntry] = [
    SlashCommandEntry(
      command: "/section", description: "Insert section divider", action: .sectionDivider),
    SlashCommandEntry(
      command: "/div", description: "Insert section divider", action: .sectionDivider),
    SlashCommandEntry(
      command: "/heading-1", description: "Start heading 1", action: .heading(level: 1)),
    SlashCommandEntry(
      command: "/heading-2", description: "Start heading 2", action: .heading(level: 2)),
    SlashCommandEntry(
      command: "/heading-3", description: "Start heading 3", action: .heading(level: 3)),
    SlashCommandEntry(
      command: "/code", description: "Insert fenced code block", action: .codeBlock),
  ]

  /// Returns commands whose name starts with the given prefix (e.g. "/" or "/d").
  static func filteredCommands(for prefix: String) -> [SlashCommandEntry] {
    let lower = prefix.lowercased()
    if lower == "/" { return commands }
    return commands.filter { $0.command.lowercased().hasPrefix(lower) }
  }

  /// Returns the matching slash command for the current line, if any.
  static func matchedCommand(in textStorage: NSTextStorage, lineRange: NSRange)
    -> SlashCommandEntry?
  {
    let lineText = (textStorage.string as NSString).substring(with: lineRange)
    let trimmed = lineText.trimmingCharacters(in: .whitespaces)

    return commands.first { $0.command.caseInsensitiveCompare(trimmed) == .orderedSame }
  }
}
