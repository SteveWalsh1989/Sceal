//
//  SlashCommandHandler.swift
//  dayra
//
//

import AppKit

enum SlashCommandHandler {

  private static let supportedCommands = ["/section", "/div"]

  /// Checks if the text in `lineRange` is a slash command. If yes, replaces it
  /// with a markdown horizontal rule and returns true. Returns false otherwise.
  static func detectAndReplace(in textStorage: NSTextStorage, lineRange: NSRange) -> Bool {
    let lineText = (textStorage.string as NSString).substring(with: lineRange)
    let trimmed = lineText.trimmingCharacters(in: .whitespaces)

    guard supportedCommands.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame })
    else {
      return false
    }

    textStorage.beginEditing()
    textStorage.replaceCharacters(in: lineRange, with: "---")
    textStorage.endEditing()

    return true
  }
}
