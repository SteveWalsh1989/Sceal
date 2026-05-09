//
//  EditorSlashCommandHandler.swift
//
//

// Defines available slash commands and handles detection in the editor.

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
  case promptBlock
  case template(NoteTemplate)
}

enum EditorSlashCommandHandler {

  static let commands: [SlashCommandEntry] = [
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
    SlashCommandEntry(
      command: "/prompt", description: "Insert copyable prompt block", action: .promptBlock),
  ]

  private static let hiddenCommands: [SlashCommandEntry] = [
    SlashCommandEntry(
      command: "/section", description: "Insert section divider", action: .sectionDivider)
  ]

  static var reservedCommandNames: Set<String> {
    Set((commands + hiddenCommands).map { String($0.command.dropFirst()).lowercased() })
  }

  private static func templateCommands(from templates: [NoteTemplate]) -> [SlashCommandEntry] {
    templates
      .filter(\.isEnabled)
      .sorted { $0.command.localizedCaseInsensitiveCompare($1.command) == .orderedAscending }
      .map { template in
        SlashCommandEntry(
          command: template.slashCommand,
          description: template.menuDescription,
          action: .template(template)
        )
      }
  }

  private static func visibleCommands(customTemplates: [NoteTemplate]) -> [SlashCommandEntry] {
    commands + templateCommands(from: customTemplates)
  }

  private static func matchableCommands(customTemplates: [NoteTemplate]) -> [SlashCommandEntry] {
    visibleCommands(customTemplates: customTemplates) + hiddenCommands
  }

  // Returns commands whose name starts with the given prefix (e.g. "/" or "/d").
  static func filteredCommands(for prefix: String, customTemplates: [NoteTemplate] = [])
    -> [SlashCommandEntry]
  {
    let lower = prefix.lowercased()
    let visibleCommands = visibleCommands(customTemplates: customTemplates)
    if lower == "/" { return visibleCommands }
    return visibleCommands.filter { $0.command.lowercased().hasPrefix(lower) }
  }

  // Returns the matching slash command for the current line, if any.
  static func matchedCommand(
    in textStorage: NSTextStorage,
    lineRange: NSRange,
    customTemplates: [NoteTemplate] = []
  ) -> SlashCommandEntry? {
    let lineText = (textStorage.string as NSString).substring(with: lineRange)
    let trimmed = lineText.trimmingCharacters(in: .whitespaces)

    return matchableCommands(customTemplates: customTemplates).first {
      $0.command.caseInsensitiveCompare(trimmed) == .orderedSame
    }
  }
}
