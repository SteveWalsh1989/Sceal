//
//  NoteGroup.swift
//

// A named, ordered group of list notes with collapsible sidebar state.

import Foundation

struct NoteGroup: Identifiable, Codable, Equatable, Sendable {
  let id: String
  var name: String
  var noteIDs: [String]
  var isCollapsed: Bool

  init(name: String, noteIDs: [String] = [], isCollapsed: Bool = false) {
    self.id = UUID().uuidString
    self.name = name
    self.noteIDs = noteIDs
    self.isCollapsed = isCollapsed
  }
}
